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
// 突变自证（本守卫自己的有效性，实测计数写进 commit message）：
//   T-1 `_extensionDeclaredMethods` 的 extension 正则改成匹配不到 ⇒ 只有 `门禁自证` 红
//       （`extensionMethods` 塌成空集 ⇒ `violations` 恒空 ⇒ 真实那条判据**照样绿**）；
//   T-2 判据里 `if (!extensionMethods.contains(name)) continue;` 后面加一句恒 `continue` ⇒
//       `判据自证` 红；
//   T-3 反向锁：把「实例方法代次」也当成违规的那条一刀切写法 ⇒ `判据自证` 里
//       `_sync` / `_onRgbFocusChanged` 那格红（文件头写明这正是本守卫**不能**做的事）。
//
// ── 审计 TE-TST-04 / R12（2026-10-16）：上面那段自证此前**只是注释** ──
// 真实那条判据是 `expect(violations, isEmpty)`，而 `violations` 恒空有两种成因：
// ① 真的都收口成字段了；② `extensionMethods` 是空集（extension 正则或大括号配对坏了），
// 或 `callRe` 坏了抽不到任何调用点。②在断言层与①完全同形——本文件头那句「跑在修复前的
// 工作树上命中 9 处」是 2026-10-12 手工做的，之后没有任何东西再响过一次。
// 补两件事：`门禁自证` 钉扫描面与两个抽取器的分母下限；`判据自证` 用人造源码对
// （extension 声明 + `addListener(_onFoo)`）证明这条守卫**该报的时候会报**，
// 并用「实例方法代次不许报」钉住反向锁。
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

/// 判据本体：给定「路径 → 源码」，报出把 extension 成员方法代次当监听器实参的调用点。
///
/// 从 `main()` 里抽出来只为了**能喂人造样本**（见 `判据自证`）——真实库那条 `isEmpty`
/// 断言在 `extensionMethods` 塌成空集时同样成立，那种绿什么都不保证。
List<String> listenerTeardownViolations(Map<String, String> sources) {
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
  return violations;
}

/// 抽取所有 `add/removeListener(名字)` 调用点（用于分母下限）。
int listenerCallSites(Map<String, String> sources) {
  final callRe = RegExp(r'\b(?:add|remove)Listener\(\s*(\w+)\s*\)');
  var n = 0;
  for (final src in sources.values) {
    n += callRe.allMatches(src).length;
  }
  return n;
}

Map<String, String> readLibSources() {
  final sources = <String, String>{};
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    sources[entity.path.replaceAll(r'\', '/')] = entity.readAsStringSync();
  }
  return sources;
}

void main() {
  final sources = readLibSources();

  test('lib 下 add/removeListener 不得传 extension 成员方法代次（DN-101）', () {
    final violations = listenerTeardownViolations(sources);
    expect(
      violations,
      isEmpty,
      reason:
          'extension 成员的方法代次每次求值都新分配闭包，removeListener 摘不掉（DN-101）。\n'
          '请把回调收口成 State 字段（`late final VoidCallback _xListener = _onX;`）'
          '并让 add/remove 复用同一对象：\n${violations.join('\n')}',
    );
  });

  test('门禁自证：扫描面与两个抽取器的分母塌掉 ⇒ 红（TE-TST-04）', () {
    expect(
      sources.length,
      greaterThanOrEqualTo(300),
      reason:
          '只读到 ${sources.length} 个 .dart（实测基线 354）⇒ 扫描根或后缀判定动了，'
          '此时上面那句 `isEmpty` 是在空集上做的，没有裁决力。',
    );
    final extensionMethods = <String>{};
    for (final src in sources.values) {
      extensionMethods.addAll(_extensionDeclaredMethods(src));
    }
    expect(
      extensionMethods.length,
      greaterThanOrEqualTo(10),
      reason:
          '全库只认出 ${extensionMethods.length} 个 extension 体内方法名（实测基线 50 个文件'
          '含 extension）⇒ extension 正则或大括号配对坏了，`violations` 会恒空（突变 T-1）。',
    );
    expect(
      listenerCallSites(sources),
      greaterThanOrEqualTo(20),
      reason: '只认出 ${listenerCallSites(sources)} 处 add/removeListener 调用点（实测基线 29）'
          '⇒ 调用点正则塌空，同样让 `violations` 恒空。',
    );
  });

  test('判据自证：extension 代次必须报，字段与实例方法代次不许报（T-2/T-3 的落点）', () {
    // 正控：这正是 DN-101 发作过三次的那种形状。
    const bad = <String, String>{
      'lib/features/x/a.dart': '''
extension EA on B {
  void _onFoo() {}
}
class C {
  void wire(Object o) {
    o.addListener(_onFoo);
    o.removeListener(_onFoo);
  }
}
''',
    };
    expect(
      listenerTeardownViolations(bad),
      hasLength(2),
      reason: 'add 与 remove 两处各自报出（摘不掉的正是这一对）。突变 T-2：判据里那句 '
          '`if (!extensionMethods.contains(name)) continue;` 若被加一行恒 continue，'
          '这里就零报了——而真实库那条照样绿',
    );

    // 反向锁：实例方法代次会被 Dart 规范化，成对 add/remove 是**合规**的；
    // 一刀切把 `_sync` / `_onRgbFocusChanged` 这类也报掉，正是文件头写明不能做的事（突变 T-3）。
    const ok = <String, String>{
      'lib/features/x/b.dart': '''
class C {
  final _sync = 0;
  void _onRgbFocusChanged() {}
  void wire(Listenable l) {
    l.addListener(_onRgbFocusChanged);
    l.removeListener(_onRgbFocusChanged);
  }
}
''',
    };
    expect(
      listenerTeardownViolations(ok),
      isEmpty,
      reason: '反向锁：不是「凡是带下划线的回调就报」，否则这条门禁天天红而被绕过',
    );
    expect(listenerTeardownViolations(const <String, String>{}), isEmpty);
  });
}
