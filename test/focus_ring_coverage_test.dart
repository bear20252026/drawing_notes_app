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
// 遮蔽器已于 P1 修正（审计 2026-10-04）抽到 `test/helpers/dart_lexical_mask.dart`
// 的 `maskDartLexically`，与 C-06（security_static_access_gate_test）共用同一份
// 实现：原先两处各自复制的状态机不认 `${...}` 插值里的嵌套引号、不真正
// 处理三引号与 raw string，一处嵌套引号即让字符串态错位、把其后的纯代码
// 整段抹成空格——本门禁的覆盖区间随之失真（错位区间内的裸 `InkWell(` 与
// 被多算的假区间都会放行）。词法细节与等长契约见该文件头注释；词法回归
// 见 dart_lexical_mask_test.dart。
//
// 分母加固（2026-10-04，测试侧）：原先只有 `expect(offenders, isEmpty)`，
// 而 `total`（全库 InkWell 计数）只进 reason 字符串——若遮蔽器/正则失明或
// 扫描到 0 个文件，本门禁恒绿。现补两条分母断言（被扫描文件数下限
// [_minScannedFiles] + InkWell 分母 `total > 0`），并把单文件判定抽成
// `_scanDartSource` 供四条反向锁用例与主循环**共用同一份实现**，证明遮蔽器、
// 分母与覆盖区间都真的在干活（含历史病灶「嵌套引号导致后续纯代码被抹空」
// 的复现样本）。
//
// 豁免：当前为空。若将来出现**已自带焦点绘制**的容器，把相对 lib/ 的
// posix 路径加进 [_exempt] 并写明理由——不要为了让门禁变绿而删断言。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'helpers/dart_lexical_mask.dart';

/// 已自带焦点绘制、无需再包一层的文件（相对 lib/ 的 posix 路径）。
const Set<String> _exempt = {};

/// 被扫描文件数下限（2026-10-04 测试侧加固：封堵「分母可为 0 而恒绿」）。
///
/// 依据：实测 2026-10-04 `lib/**/*.dart` 共 **320** 个文件进入扫描。取
/// **180**（≈56%）——本门禁扫整棵 lib 树，正常重构（文件合并/拆分、下线
/// 个别页面）不会让整树缩掉四成；而本门禁真病灶（根目录写错、后缀判定
/// 失效、遮蔽器把整段代码抹成空格）会让计数塌到 0 或个位数，而不是「少
/// 几个」。同批 `architecture_test` 的 `Metrics.martin('domain/**')` 匹配
/// 零文件（commit 96261cc）即此类病灶——恒绿的门禁比没有门禁更危险。
const int _minScannedFiles = 180;

/// 对**单个 Dart 源文件文本**跑 V-12 判定：遮蔽 → 求 AppleFocusRing 覆盖
/// 区间 → 数 `InkWell(` 分母并挑出未被包裹者。
///
/// 主循环与反向锁共用这一份实现：反向锁若另写一遍逻辑，就测不出主路径失明。
({int inkWellCount, List<String> uncovered}) _scanDartSource(
  String source, {
  required String label,
}) {
  final code = maskDartLexically(source);

  // 本文件内每个 AppleFocusRing 的覆盖区间（在遮蔽文本上求括号，
  // 避开注释/字符串里的假括号；偏移与原文一一对应）。
  final covered = <({int start, int end})>[];
  for (final m in RegExp(r'AppleFocusRing\(').allMatches(code)) {
    final close = _matchParen(code, m.start + m.group(0)!.length - 1);
    if (close >= 0) covered.add((start: m.start, end: close));
  }

  var inkWellCount = 0;
  final uncovered = <String>[];
  for (final m in RegExp(r'\bInkWell\(').allMatches(code)) {
    inkWellCount++;
    final inRing = covered.any((r) => m.start > r.start && m.start < r.end);
    if (!inRing) {
      final line = code.substring(0, m.start).split('\n').length;
      uncovered.add('$label:$line');
    }
  }
  return (inkWellCount: inkWellCount, uncovered: uncovered);
}

/// 反向锁样本 A：裸 `InkWell(`——必须进分母**且**被判为 offender。
/// 只断言「offenders 为空」的门禁在扫描面塌成 0 时会恒绿，本样本证明
/// 判定链路（遮蔽 → 分母 → 覆盖区间 → 挑出未包裹）真的会响。
const String _sampleBareInkWell = r'''
class A {
  Widget w() => InkWell(onTap: () {}, child: const SizedBox());
}
''';

/// 反向锁样本 B：`AppleFocusRing` 包裹的 `InkWell(`——进分母但不得成为
/// offender（证明覆盖区间/括号配对逻辑活着，反向锁不是「一律报警」）。
const String _sampleWrappedInkWell = r'''
class A {
  Widget w() => AppleFocusRing(
    radius: 8,
    child: InkWell(onTap: () {}, child: const SizedBox()),
  );
}
''';

/// 反向锁样本 C：字样只出现在文档注释与字符串里——分母必须为 0。
/// `apple_focus.dart` 的用法示例注释正是首跑假红的来源。
const String _sampleMaskedOnly = r'''
class A {
  /// 用法示例：AppleFocusRing(child: InkWell(...))
  String s = 'InkWell(';
}
''';

/// 反向锁样本 D：**历史病灶复现**。插值里的嵌套引号曾让旧版状态机字符串态
/// 错位，把其后的纯代码整段抹成空格（P1 修复缘起，见 helpers/
/// dart_lexical_mask.dart 头注释与 lib/features/notes/presentation/
/// conflict_resolution_dialog.dart:92）——覆盖区间随之失真，区间内的裸
/// `InkWell(` 与多算的假区间都会放行。现必须仍把第 3 行的裸 InkWell 计入
/// 分母并判为 offender。
const String _sampleNestedQuoteTrap = r'''
class A {
  String f(String n) => 'conflict ${"nested " + n} tail';
  Widget w() => InkWell(onTap: () {}, child: const SizedBox());
}
''';

void main() {
  test('V-12：全库 InkWell 均被 AppleFocusRing 包裹（键盘焦点可见）', () {
    final offenders = <String>[];
    var total = 0;
    var scannedFiles = 0;

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final rel = entity.path.replaceAll(r'\', '/');
      final relToLib = rel.substring(rel.indexOf('lib/'));
      if (_exempt.contains(relToLib)) continue;

      scannedFiles++;
      final scan = _scanDartSource(entity.readAsStringSync(), label: relToLib);
      total += scan.inkWellCount;
      offenders.addAll(scan.uncovered);
    }

    // 分母下限先于结论：扫描面塌掉时直接报「门禁失明」，
    // 别让「零命中」被误读成「零违规」。
    expect(
      scannedFiles,
      greaterThanOrEqualTo(_minScannedFiles),
      reason:
          'V-12 门禁扫描面异常：只扫到 $scannedFiles 个 .dart 文件（下限 '
          '$_minScannedFiles，实测 2026-10-04 为 320）。说明扫描根目录/后缀'
          '判定/豁免表或遮蔽器出了问题——此时「零 offender」是失明而非合规。'
          '必须修扫描口径，绝不能靠放宽下限变绿。',
    );

    // 分母本身也必须非零：扫到了一堆文件却一个 InkWell 都没匹配上，
    // 同样说明正则/遮蔽器失明（本库实测 38 处调用点）。
    expect(
      total,
      greaterThan(0),
      reason:
          'V-12 门禁分母为 0：扫了 $scannedFiles 个文件却匹配到 0 个 `InkWell('
          '`（实测基线 38 处）——正则或遮蔽器已失明，下面的 isEmpty 断言'
          '此时毫无裁决力。',
    );

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
          '命中 ${offenders.length} 处 / 共 $total 处 InkWell（扫描 '
          '$scannedFiles 个文件）：\n'
          '${offenders.take(30).join('\n')}',
    );
  });

  // 反向锁（2026-10-04 加固）：证明「遮蔽器 + 分母 + 覆盖区间」三件套都在
  // 正常工作，两个相反方向都成立——真代码里的裸 InkWell 必须被抓到，
  // 注释/字符串里的字样必须不被计数。样本走内存字符串、不落盘。
  test('V-12 反向锁：裸 InkWell 必进分母且被判为未包裹', () {
    final scan = _scanDartSource(_sampleBareInkWell, label: '<inline>');
    expect(
      scan.inkWellCount,
      1,
      reason:
          '分母失明：样本文本里的裸 `InkWell(` 没被计数，'
          '说明遮蔽器把真代码也抹掉了，主用例的 isEmpty 断言不再可信。',
    );
    expect(
      scan.uncovered,
      hasLength(1),
      reason: '裸 InkWell 未被判为 offender——覆盖判定本身失效。',
    );
    // 等长遮蔽契约：行号与原文一一对应。Dart 规范里三引号后紧跟的首个换行
    // **不计入内容**，故样本的 `class` 是第 1 行、裸 InkWell 是第 2 行。
    expect(
      scan.uncovered.single,
      '<inline>:2',
      reason: '行号漂移说明遮蔽不再是等长替换，reason 里的定位会指错地方。',
    );
  });

  test('V-12 反向锁：AppleFocusRing 包裹的 InkWell 进分母但不报警', () {
    final scan = _scanDartSource(_sampleWrappedInkWell, label: '<inline>');
    expect(scan.inkWellCount, 1, reason: '包裹样本的分母也必须是 1，否则上一条用例的「报警」是白送的。');
    expect(
      scan.uncovered,
      isEmpty,
      reason:
          '括号配对/覆盖区间失效——已合规写法被判为违规，门禁会假红，'
          '最终结局是被人删断言而非修包裹。',
    );
  });

  test('V-12 反向锁：注释与字符串里的字样不得计入分母', () {
    final scan = _scanDartSource(_sampleMaskedOnly, label: '<inline>');
    expect(
      scan.inkWellCount,
      0,
      reason:
          '注释/字符串里的 `InkWell(` 字样被当成真实调用——遮蔽器已失效，'
          '门禁会在任何人写一句用法注释时假红。',
    );
    expect(scan.uncovered, isEmpty);
  });

  test('V-12 反向锁：嵌套引号插值之后的裸 InkWell 仍被抓到（历史病灶）', () {
    final scan = _scanDartSource(_sampleNestedQuoteTrap, label: '<inline>');
    expect(
      scan.inkWellCount,
      1,
      reason:
          '历史病灶复现：嵌套引号一旦让字符串状态机错位，其后的纯代码'
          '会被整段抹成空格，区间内的裸 `InkWell(` 就从分母里消失，'
          '门禁对该文件彻底失明。',
    );
    expect(
      scan.uncovered.single,
      '<inline>:3',
      reason:
          '应命中样本第 3 行的真代码裸 InkWell（三引号后首个换行不计入内容，'
          '故 class 为第 1 行）。',
    );
  });
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
