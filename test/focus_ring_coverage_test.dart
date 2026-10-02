// V-12（审计 2026-09-27）覆盖门禁：全库可交互 `InkWell` 必须被
// `AppleFocusRing` 包裹。
//
// 背景：审计实测「全库 0 处 FocusableActionDetector；裸
// Semantics+Tooltip+InkWell 按钮键盘聚焦仅主题 focusColor（深色底几乎
// 不可见），无 2px Focus Blue 描边」——键盘用户 Tab 到按钮时看不出焦点
// 在哪。`AppleFocusRing` 外扩绘制 2px 环且 `canRequestFocus: false`
// 只观察不抢焦点（不多出 Tab 停靠），是本项目的统一解法。
//
// 为什么用静态扫描而不是 widget 测试：38 个调用点分散在 20+ 文件，且
// 多数位于重上下文（编辑器、表格、PIN 码盘）里，逐个搭桩既脆又漏——
// 扫描能一次性锁死「新增裸 InkWell 即红」，与 architecture_test / 棘轮
// 测试同一门禁思路。
//
// 扫描前先做**等长遮蔽**（注释与字符串替换为空格、保留换行）：否则
// `apple_focus.dart` 文档注释里的用法示例 `/// AppleFocusRing(` 会被当成
// 真实调用（首跑即栽在这），注释里的撇号也会把字符串状态机骗跑偏。
//
// 豁免：当前为空。若将来出现**已自带焦点绘制**的容器，把相对 lib/ 的
// posix 路径加进 [_exempt] 并写明理由——不要为了让门禁变绿而删断言。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 已自带焦点绘制、无需再包一层的文件（相对 lib/ 的 posix 路径）。
const Set<String> _exempt = {};

void main() {
  test('V-12：全库 InkWell 均被 AppleFocusRing 包裹（键盘焦点可见）', () {
    final offenders = <String>[];
    var total = 0;

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final rel = entity.path.replaceAll(r'\', '/');
      final relToLib = rel.substring(rel.indexOf('lib/'));
      if (_exempt.contains(relToLib)) continue;

      final raw = entity.readAsStringSync();
      final code = _maskCommentsAndStrings(raw);

      // 本文件内每个 AppleFocusRing 的覆盖区间（在遮蔽文本上求括号，
      // 避开注释/字符串里的假括号；偏移与原文一一对应）。
      final covered = <({int start, int end})>[];
      for (final m in RegExp(r'AppleFocusRing\(').allMatches(code)) {
        final close = _matchParen(code, m.start + m.group(0)!.length - 1);
        if (close >= 0) covered.add((start: m.start, end: close));
      }

      for (final m in RegExp(r'\bInkWell\(').allMatches(code)) {
        total++;
        final inRing = covered.any((r) => m.start > r.start && m.start < r.end);
        if (!inRing) {
          final line = code.substring(0, m.start).split('\n').length;
          offenders.add('$relToLib:$line');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'V-12（审计 2026-09-27）：以下 InkWell 没有被 AppleFocusRing 包裹，'
          '键盘 Tab 到它时只有 focusColor overlay，深色底上几乎不可见。\n'
          '修法：AppleFocusRing(child: InkWell(...)) 包一层——环外扩绘制不占布局，'
          'Focus 节点 canRequestFocus:false 不增加 Tab 停靠；半径取 InkWell 自身 '
          'borderRadius（无圆角则 0）。若外层有 Card / Material(clipBehavior) '
          '裁剪件，环要包在裁剪件**外层**，否则外扩部分会被切掉。\n'
          '命中 ${offenders.length} 处 / 共 $total 处 InkWell：\n'
          '${offenders.take(30).join('\n')}',
    );
  });
}

/// 等长遮蔽：注释与字符串内容换为空格（保留换行，行号不变）。
String _maskCommentsAndStrings(String src) {
  final b = StringBuffer();
  var i = 0;
  while (i < src.length) {
    final c = src[i];
    // 行注释（含 ///）——必须先于引号判断，否则注释里的撇号会被当字符串。
    if (c == '/' && i + 1 < src.length && src[i + 1] == '/') {
      while (i < src.length && src[i] != '\n') {
        b.write(' ');
        i++;
      }
      continue;
    }
    // 块注释。
    if (c == '/' && i + 1 < src.length && src[i + 1] == '*') {
      b.write('  ');
      i += 2;
      while (i < src.length) {
        if (src[i] == '*' && i + 1 < src.length && src[i + 1] == '/') {
          b.write('  ');
          i += 2;
          break;
        }
        b.write(src[i] == '\n' ? '\n' : ' ');
        i++;
      }
      continue;
    }
    // 字符串字面量（单双引号；含三引号——遇前三个同引号自然终止）。
    if (c == "'" || c == '"') {
      final quote = c;
      b.write(' ');
      i++;
      while (i < src.length) {
        if (src[i] == r'\') {
          b.write('  ');
          i += 2;
          continue;
        }
        if (src[i] == quote) break;
        b.write(src[i] == '\n' ? '\n' : ' ');
        i++;
      }
      if (i < src.length) {
        b.write(' ');
        i++;
      }
      continue;
    }
    b.write(c);
    i++;
  }
  return b.toString();
}

/// 从 `i`（指向 `(`）找配对 `)`；未闭合返回 -1。
/// 配对在**遮蔽后**的文本上求：注释/字符串已是空格，无假括号。
int _matchParen(String s, int i) {
  var depth = 0;
  while (i < s.length) {
    final c = s[i];
    if (c == '(') {
      depth++;
    } else if (c == ')') {
      depth--;
      if (depth == 0) return i;
    }
    i++;
  }
  return -1;
}
