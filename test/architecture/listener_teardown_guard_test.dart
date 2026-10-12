// DN-101 守卫（专家审计 2026-10-12）：**extension 成员的方法代次不能作为
// addListener/removeListener 的实参**。
//
// 根因：Dart 里**实例方法代次会被规范化**（`o.m == o.m` 为真），所以
// `addListener(o.m)` / `removeListener(o.m)` 成对有效；但 **extension 成员的
// 方法代次每次求值都新分配一个闭包**，于是 remove 摘的是另一个对象 ⇒ 摘不掉，
// 监听在常驻控制器上逐次累积，之后每次变化触发 N 份回调与多余重建。
//
// 同一病灶已发作三次：
//   · `dd7a740` 修的是 `_EditorPagePersistence` 的 `_onSavingStateChanged` /
//     `_onSaveFailureChanged`（云端 20 条 defunct 断言的根因）；
//   · 本批修的是 `doc_editor_selection` 的 `_onFocusChange` /
//     `_onSelectionChanged`（主推的打字笔记链路）；
//   · 本批守卫另扫出 `doc_editor_history` 的 `_onTitleEdited`（审计报告未列）。
//
// 修法统一为「把回调收口成 State 字段，add/remove 复用同一对象」。本守卫锁定
// 该纪律。
//
// **判定必须只针对 extension 体内声明的方法**：实例方法代次是合规的（会被
// 规范化），一刀切会把 `_sync` / `_onRgbFocusChanged` / `_onDataVersionChanged`
// 这类正常写法误报。另外调用点与声明常分处同一 library 的不同 part 文件
// （`doc_editor.dart` 调用、`doc_editor_selection.dart` 声明），所以必须跨文件
// 汇总判定，不能只看同文件。
//
// 突变自证：把本守卫跑在修复前的工作树上命中 9 处（含上述三组），修复后为 0。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 提取 [src] 中所有 `extension X on Y {` 体内声明的方法名（按大括号配对取体）。
Set<String> _extensionDeclaredMethods(String src) {
  final names = <String>{};
  final extRe = RegExp(r'\bextension\s+\w+\s+on\s+[\w<>,.\s]+\{');
  final declRe = RegExp(
    r'\b(?:void|Future(?:<[^>]*>)?|bool|int|String|double)\s+(_\w+)\s*\(',
  );
  for (final m in extRe.allMatches(src)) {
    var depth = 0;
    var i = m.end - 1;
    while (i < src.length) {
      final c = src[i];
      if (c == '{') {
        depth++;
      } else if (c == '}') {
        depth--;
        if (depth == 0) break;
      }
      i++;
    }
    final body = src.substring(m.end, i < src.length ? i : src.length);
    for (final d in declRe.allMatches(body)) {
      names.add(d.group(1)!);
    }
  }
  return names;
}

void main() {
  test('lib 下 add/removeListener 不得传 extension 方法代次（DN-101）', () {
    final sources = <String, String>{};
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      sources[entity.path.replaceAll(r'\', '/')] = entity.readAsStringSync();
    }

    // 跨文件汇总：extension 体内声明过的方法名。
    final extensionMethods = <String>{};
    for (final src in sources.values) {
      extensionMethods.addAll(_extensionDeclaredMethods(src));
    }

    final callRe = RegExp(r'\b(?:add|remove)Listener\(\s*(\w+)\s*\)');
    final violations = <String>[];
    for (final entry in sources.entries) {
      for (final m in callRe.allMatches(entry.value)) {
        final name = m.group(1)!;
        if (!extensionMethods.contains(name)) continue; // 字段/实例方法：合规
        final line = entry.value.substring(0, m.start).split('\n').length;
        violations.add('${entry.key}:$line  add/removeListener($name)');
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'extension 成员的方法代次每次求值都新分配闭包，removeListener 摘不掉（DN-101）。\n'
          '请把回调收口成 State 字段（`late final VoidCallback _xListener = _onX;`）'
          '并让 add/remove 复用同一对象：\n${violations.join('\n')}',
    );
  });
}
