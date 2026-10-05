// D-14（审计台账 2026-09-27:291，条目至今无闭环记录）设计令牌纪律门禁：
// `lib/` 里的**裸数字间距**必须逐文件钉在上限内，且增量一律拦住。
//
// 背景：间距只许走 `AppleSpacing.*`（`lib/core/theme/apple_design.dart:131`，
// base=8，档位 4/8/12/16/24/32/48）。但台账 D-14 记的存量从未被任何批次认领，
// 实测裸 `EdgeInsets` / `SizedBox` 各上百处，而 `AppleSpacing.*` 引用仅 53 处。
//
// 为什么是棘轮而不是「人工批量替换 300+ 处」：那种改法 diff 巨大、且把
// off-scale 值（如 14 / 10 / 44 / 560）就近取到档位上会造成**视觉上不等价**的
// 隐蔽改版，UI 回归没人能逐屏复核。本门禁把存量钉死、把增量挡住，收敛交由
// 后续批次按文件逐片做（一次改一个文件、改完即可视检）。做法与本仓已有的
// `test/architecture_boundary_ratchet_test.dart`、`test/architecture/
// architecture_test.dart`（7 个 feature domain 文件逐文件钉上限）一致。
//
// ⚠️ 这张表是**止血措施，只紧不松**：任何下调数字 / 删除行都是进步；想把数字
// 调大必须先评审并写明理由。**不要把它当永久豁免登记处**——目标是把表清空。
// 收敛后的正确收尾是把整个 `_baseline` 换成空表，让所有文件回到上限 0。
//
// ── 判定口径（务必看清，与逐行 grep 不同）────────────────────────────
// - 计数单位 = **违规调用点数**（一个 `EdgeInsets.xxx(...)` 调用记 1，一个
//   `SizedBox(...)` 记 1），即便同一次调用里 horizontal 与 vertical 都是裸数字
//   也只记 1；同一行写两个 `SizedBox` 记 2。逐行 grep 会把「多行调用」整个漏掉
//   （实测 29 个 EdgeInsets 点 + 70 个 SizedBox 点在调用行上看不到数字），
//   也会把「同行多点」压成 1，两者不可比。
// - 检出形态：`EdgeInsets.all / symmetric / only / fromLTRB` 带非零数字字面量；
//   `SizedBox` 的 `height:` / `width:` 带非零数字字面量。
// - **0 合法**（`EdgeInsets.only(bottom: 0)`、`SizedBox(height: 0)` 无需令牌）。
// - **比例/缩放因子合法**：紧跟在 `*` `/` `.` 之后的数字不算间距取值——
//   `SizedBox(height: MediaQuery.sizeOf(ctx).height * 0.6)`
//   （`lib/features/doc/presentation/doc_outline_rail.dart:179`）与
//   `gap * 2`（`lib/shared/widgets/pin_pad.dart:410`）若被计入，就是**永久假红**
//   （令牌里没有 0.6 / 2 倍这一档，没人能把它改成 `AppleSpacing.*`）。
//   而 `+ 16`、`? 2 : 0` 这类仍是裸间距，照计。
// - 标识符整体成词后再判定，故 `_pad8`、`AppDesign.pagePadding`、
//   `AppleSpacing.xs`、`Theme.of(context).spacing` 里的数字/名字都不算违规。
// - 扫描前先做**等长遮蔽**（`helpers/dart_lexical_mask.dart`）：注释与字符串
//   字面量里的字样不计，`const` 与 `final` 变量引用不计。
// - 本条只覆盖 EdgeInsets / SizedBox 两类；`BorderSide(width:)`、`Spacer(length:)`、
//   `BorderRadius.circular(n)`、`TextStyle(fontSize:)`、列表 `spacing:` 等裸数值
//   不在 D-14 口径内（见报告「下一步」）。
//
// 反向锁用例见 `main()` 后半：本门禁与全部静态门禁共有的病灶是「恒绿」
// （扫描面塌成 0、遮蔽器把真代码抹空、正则写错都会让 isEmpty 白过），
// 故用内联样本从**两个相反方向**钉判定链路，并给被扫描文件数设下限。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'helpers/dart_lexical_mask.dart';

/// 被扫描文件数下限（封堵「glob/根目录写错 → 扫 0 文件而恒绿」，
/// 本仓实测病灶见 `focus_ring_coverage_test.dart` 头注释）。
///
/// 依据：立卡时实测 `lib/**/*.dart` 共 **320** 个文件进入扫描，取 **180**
/// （≈56%）——正常重构不会让整棵树缩掉四成，而口径失配会让计数塌到 0。
const int _minScannedFiles = 180;

/// 具名基线棘轮：**文件（相对仓库根的 posix 路径）→ 允许的裸间距调用点数上限**。
///
/// 快照实测 2026-10-05：共 66 个文件、411 个调用点（EdgeInsets 198 +
/// SizedBox 213）。**不在这张表里的文件上限为 0**——新文件引入裸间距直接红。
/// 某文件被清零后请把它的整行删掉（下方用例会对残留的 0 命中行报警，
/// 防止表腐化）。
const Map<String, int> _baseline = {
  'lib/features/all_docs/presentation/all_docs_sidebar.dart': 17,
  'lib/features/doc/presentation/doc_page_widgets.dart': 16,
  'lib/features/drawing/presentation/dialogs/color_picker_dialog.dart': 15,
  'lib/features/doc/presentation/doc_editor_blocks.dart': 14,
  'lib/shared/widgets/pin_pad.dart': 14,
  'lib/features/all_docs/presentation/all_docs_page_widgets.dart': 13,
  'lib/features/notes/presentation/settings_page.dart': 13,
  'lib/features/all_docs/presentation/all_docs_page_mobile.dart': 12,
  'lib/features/doc/presentation/database/database_kanban_view.dart': 11,
  'lib/features/drawing/presentation/editor_context_bar.dart': 11,
  'lib/features/drawing/presentation/properties_panel.dart': 11,
  'lib/features/drawing/presentation/components/editor_widgets.dart': 10,
  'lib/features/drawing/presentation/pdf_export_panel.dart': 10,
  'lib/features/notes/presentation/home_page_tabs.dart': 8,
  'lib/features/all_docs/presentation/all_doc_row.dart': 8,
  'lib/features/doc/application/doc_pdf_adapter.dart': 8,
  'lib/features/doc/presentation/database_block_view.dart': 8,
  'lib/features/notes/presentation/notebook_view_page_widgets.dart': 7,
  'lib/features/all_docs/presentation/tags_view.dart': 6,
  'lib/features/drawing/presentation/editor_page_dialogs.dart': 6,
  'lib/features/drawing/presentation/layer_panel.dart': 6,
  'lib/features/doc/presentation/table_editor_widget.dart': 5,
  'lib/features/drawing/presentation/editor_page_appbar.dart': 5,
  'lib/features/drawing/presentation/editor_page_text_overlays.dart': 5,
  'lib/features/doc/presentation/doc_editor_ui.dart': 4,
  'lib/features/notes/presentation/webdav_sync_settings_page.dart': 4,
  'lib/core/security/app_lock_gate.dart': 4,
  'lib/features/doc/presentation/doc_page_info.dart': 4,
  'lib/features/doc/presentation/pdf_attachment_preview.dart': 4,
  'lib/features/doc/presentation/database/database_table_view.dart': 4,
  'lib/features/doc/presentation/trash_page.dart': 4,
  'lib/features/notes/presentation/notebook_view_page.dart': 4,
  'lib/features/drawing/application/editor_exporter.dart': 4,
  'lib/features/drawing/presentation/editor_page_actions.dart': 3,
  'lib/features/doc/presentation/doc_outline_rail.dart': 3,
  'lib/features/doc/presentation/image_preview_dialog.dart': 3,
  'lib/features/notes/presentation/search_page.dart': 3,
  'lib/features/drawing/presentation/selection_bar.dart': 3,
  'lib/features/drawing/presentation/shape_library.dart': 3,
  'lib/core/theme/app_design.dart': 2,
  'lib/features/doc/presentation/doc_editor_selection.dart': 2,
  'lib/features/doc/presentation/doc_editor_toolbar.dart': 2,
  'lib/core/theme/apple_design.dart': 2,
  'lib/features/notes/presentation/notebook_reader_page.dart': 2,
  'lib/features/drawing/presentation/editor_page_persistence.dart': 2,
  'lib/features/drawing/rendering/pdf_hybrid_exporter.dart': 1,
  'lib/features/drawing/presentation/selection_action_button.dart': 1,
  'lib/features/drawing/presentation/editor_page_editing.dart': 1,
  'lib/features/doc/presentation/database/database_cell_editor.dart': 1,
  'lib/features/notes/presentation/home_page.dart': 1,
};

final RegExp _edgeRe = RegExp(
  r'EdgeInsets\.(all|symmetric|only|fromLTRB)\s*\(',
);
final RegExp _boxRe = RegExp(r'SizedBox\s*\(');
final RegExp _namedArgRe = RegExp(r'^\s*[A-Za-z_$][A-Za-z0-9_$]*\s*:(.*)$');
final RegExp _boxWHRe = RegExp(r'^\s*(height|width)\s*:(.*)$');

/// 数字字面量 vs 标识符：标识符**整体成词**后被跳过，所以 `_pad8`、
/// `AppleSpacing.xs`、`h2` 里的数字都不会被误读成间距取值。
final RegExp _tokenRe = RegExp(r'[A-Za-z_$][A-Za-z0-9_$]*|\d+(?:\.\d+)?');
final RegExp _leadingDigitRe = RegExp(r'^\d');

/// [expr] 里是否存在「作为间距取值」的非零数字字面量。
bool _hasBareSpacingLiteral(String expr) {
  for (final m in _tokenRe.allMatches(expr)) {
    final t = m.group(0)!;
    if (!_leadingDigitRe.hasMatch(t)) continue; // 标识符
    if (double.parse(t) == 0) continue; // 0 合法
    var p = m.start - 1;
    while (p >= 0 && _isWs(expr[p])) {
      p--;
    }
    // 比例 / 缩放因子（`* 0.6`、`/ 2`、`* 2`）不是间距取值，见头注释口径。
    if (p >= 0 && (expr[p] == '*' || expr[p] == '/' || expr[p] == '.')) {
      continue;
    }
    return true;
  }
  return false;
}

bool _isWs(String ch) => ch == ' ' || ch == '\n' || ch == '\r' || ch == '\t';

/// 从 [open]（指向 `(`）求配对 `)` 下标；未闭合返回 -1。
/// 在**遮蔽后**的文本上求，注释/字符串已是空格，无假括号。
int _matchParen(String s, int open) {
  var depth = 0;
  for (var i = open; i < s.length; i++) {
    final c = s[i];
    if (c == '(') {
      depth++;
    } else if (c == ')') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

/// 按顶层逗号切分实参（括号/方括号/花括号内的逗号不切）。
List<String> _splitTopLevel(String args) {
  final parts = <String>[];
  var depth = 0;
  final buf = StringBuffer();
  for (var i = 0; i < args.length; i++) {
    final c = args[i];
    if (c == '(' || c == '[' || c == '{') {
      depth++;
    } else if (c == ')' || c == ']' || c == '}') {
      depth--;
    }
    if (c == ',' && depth == 0) {
      parts.add(buf.toString());
      buf.clear();
      continue;
    }
    buf.write(c);
  }
  if (buf.toString().trim().isNotEmpty) parts.add(buf.toString());
  return parts;
}

/// 对**单个 Dart 源文本**跑 D-14 判定，返回违规调用点的 `label:行号` 列表。
///
/// 主循环与全部反向锁共用这一份实现：反向锁若另写一遍逻辑，就测不出主路径失明。
List<String> _scanDartSource(String source, {required String label}) {
  final code = maskDartLexically(source);
  final sites = <String>[];

  void add(int at) =>
      sites.add('$label:${code.substring(0, at).split('\n').length}');

  for (final m in _edgeRe.allMatches(code)) {
    final open = m.start + m.group(0)!.length - 1;
    final close = _matchParen(code, open);
    if (close < 0) continue;
    final bad = _splitTopLevel(code.substring(open + 1, close)).where((part) {
      final v = _namedArgRe.firstMatch(part)?.group(1) ?? part;
      return _hasBareSpacingLiteral(v);
    }).isNotEmpty;
    if (bad) add(m.start);
  }

  for (final m in _boxRe.allMatches(code)) {
    final open = m.start + m.group(0)!.length - 1;
    final close = _matchParen(code, open);
    if (close < 0) continue;
    final bad = _splitTopLevel(code.substring(open + 1, close)).any(
      (part) =>
          _boxWHRe.firstMatch(part) != null &&
          _hasBareSpacingLiteral(_boxWHRe.firstMatch(part)!.group(2)!),
    );
    if (bad) add(m.start);
  }
  return sites;
}

/// 扫全棵 `lib/`：返回「扫描到的文件相对路径集合」与「每文件裸间距调用点数」。
({Set<String> scanned, Map<String, int> measured}) _measureRepo() {
  final measured = <String, int>{};
  final scanned = <String>{};
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final rel = entity.path.replaceAll(r'\', '/');
    // 根目录写错时（本仓病灶：规则指向不存在的树 → 扫描面静默为 0）不能让
    // substring 抛 RangeError 把人引去删断言——保留原路径，由哨兵断言报清楚。
    const marker = 'lib/';
    final at = rel.indexOf(marker);
    final relToRoot = at < 0 ? rel : rel.substring(at);
    scanned.add(relToRoot);
    final n = _scanDartSource(
      entity.readAsStringSync(),
      label: relToRoot,
    ).length;
    if (n > 0) measured[relToRoot] = n;
  }
  return (scanned: scanned, measured: measured);
}

// ── 反向锁样本（内联字符串，不落盘）────────────────────────────────
const String _sampleShouldCatch = r'''
class W {
  Widget a() => const Padding(
    padding: EdgeInsets.all(8),
    child: SizedBox(height: 12),
  );
  Widget b() => const EdgeInsets.symmetric(horizontal: 16, vertical: 4);
  Widget c() => const EdgeInsets.only(top: 24);
  Widget d() => const EdgeInsets.fromLTRB(0, 0, 32, 0);
  Widget e() => const SizedBox(width: 48, height: 1);
}
''';

const String _sampleShouldPass = r'''
class W {
  Widget a() => Padding(
    padding: EdgeInsets.all(AppleSpacing.md),
    child: SizedBox(height: kRowHeight),
  );
  Widget b() => const EdgeInsets.symmetric(
    horizontal: AppleSpacing.xs,
    vertical: AppleSpacing.xs,
  );
  Widget c() => const EdgeInsets.only(bottom: 0);
  Widget d() => const EdgeInsets.fromLTRB(0, 0, kWidth, 0);
  Widget e() => EdgeInsets.zero;
  Widget f() => SizedBox(height: MediaQuery.sizeOf(ctx).height * 0.6, width: gap * 2);
  Widget g() => Padding(padding: Theme.of(context).padding);
}
''';

const String _sampleCommentsOnly = r'''
class W {
  /// 用法示例：`EdgeInsets.all(8)`、`SizedBox(height: 12)` 都要令牌化。
  // 旧写法 EdgeInsets.symmetric(horizontal: 16, vertical: 12) 已废弃。
  String note = 'SizedBox(width: 24) 与 EdgeInsets.only(top: 4) 是违规写法';
  Widget ok() => const SizedBox.shrink();
}
''';

/// 逐行 grep 看不见的那一类：实参换行书写（本口径必须抓到，否则基线口径本身
/// 就漏掉 29+70 个调用点，等于门禁空转）。
const String _sampleMultiLineCalls = r'''
class W {
  Widget a() => const Padding(
    padding: EdgeInsets.only(
      left: 16,
      top: 8,
    ),
    child: SizedBox(
      height: 12,
    ),
  );
}
''';

void main() {
  test('D-14 棘轮：每文件裸间距调用点不得超过具名基线（未登记文件上限 0）', () {
    expect(
      Directory('lib').existsSync(),
      isTrue,
      reason: '找不到 lib/ 目录：测试的工作目录必须是仓库根（见 AGENTS.md 的 shell 目录铁律）。',
    );

    final scan = _measureRepo();
    final measured = scan.measured;
    final scannedFiles = scan.scanned.length;

    // 分母下限先于结论：扫描面塌掉时「零违规」是失明而非合规。
    expect(
      scannedFiles,
      greaterThanOrEqualTo(_minScannedFiles),
      reason:
          'D-14 扫描面异常：只扫到 $scannedFiles 个 .dart 文件（下限 $_minScannedFiles，'
          '立卡实测 320）。说明扫描根/后缀判定/遮蔽器出了问题，'
          '此时下面的 isEmpty 断言毫无裁决力。必须修口径，绝不能放宽下限变绿。',
    );
    // 哨兵：确认扫到的是本仓源码树而不是别的目录（判定为「被扫到」，
    // 与它有没有违规无关——否则将来把该文件令牌化干净后本断言会假红）。
    expect(
      scan.scanned,
      containsAll(['lib/core/theme/apple_design.dart', 'lib/main.dart']),
      reason: '哨兵文件未进入扫描面：扫描根目录或后缀判定已失配（工作目录必须是仓库根）。',
    );

    final violations = <String>[];
    for (final e in measured.entries) {
      final allowed = _baseline[e.key];
      if (allowed == null) {
        violations.add(
          '${e.key}：${e.value} 处裸间距，**该文件未登记基线（上限 0）**——'
          '新增裸 EdgeInsets/SizedBox 一律拦住，请改用 AppleSpacing.*',
        );
      } else if (e.value > allowed) {
        violations.add(
          '${e.key}：实测 ${e.value} 处 > 基线 $allowed 处（棘轮只紧不松；'
          '确需重构请先评审再改表）',
        );
      }
    }
    // 表腐化防护：清零的文件必须从表里删掉，否则「最终清空这张表」永远不会发生。
    for (final e in _baseline.entries) {
      if (!measured.containsKey(e.key) && File(e.key).existsSync()) {
        violations.add(
          '${e.key}：基线登记了 ${e.value} 处，实测已为 0——请把该行从 _baseline 删掉',
        );
      } else if (!File(e.key).existsSync()) {
        violations.add('${e.key}：基线里的文件已不存在，请删掉该行（路径改名会让表腐化）');
      }
    }

    final sortedMeasures = measured.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    expect(
      violations,
      isEmpty,
      reason:
          'D-14 裸间距棘轮被突破：\n${violations.join('\n')}\n\n'
          '当前实测全表（用于重取基线时对照，只许往下改）：\n'
          '${sortedMeasures.map((e) => "'${e.key}': ${e.value},").join('\n')}',
    );
  });

  test('D-14 反向锁 A：六类违规形态全部被抓到', () {
    final sites = _scanDartSource(_sampleShouldCatch, label: '<inline>');
    expect(
      sites,
      hasLength(6),
      reason:
          '期望 6 个调用点（all/height/symmetric/only/fromLTRB/width），实测 '
          '${sites.length}：$sites。少了说明判定链路失明，门禁会恒绿；'
          '多了说明口径漂了（例如把一次调用的两个参数计成两点）。',
    );
  });

  test('D-14 反向锁 B：令牌 / 变量 / 0 / 比例因子一律不算违规', () {
    final sites = _scanDartSource(_sampleShouldPass, label: '<inline>');
    expect(
      sites,
      isEmpty,
      reason:
          '合法样本被判违规：$sites。若命中 height: MediaQuery.*0.6 那行，'
          '说明比例因子豁免失效——该口径会在真实代码上永久假红，'
          '最终结局是断言被人删掉而非修扫描器。',
    );
  });

  test('D-14 反向锁 C：注释与字符串里的字样不计入', () {
    final sites = _scanDartSource(_sampleCommentsOnly, label: '<inline>');
    expect(
      sites,
      isEmpty,
      reason:
          '注释/文档/字符串里的 `EdgeInsets.all(8)`、`SizedBox(height: 12)` 被当成'
          '真实代码：等长遮蔽已失效，任何人写一句用法注释都会假红。',
    );
  });

  test('D-14 反向锁 D：实参换行书写的调用也必须计数', () {
    final sites = _scanDartSource(_sampleMultiLineCalls, label: '<inline>');
    expect(
      sites,
      hasLength(2),
      reason:
          '多行 EdgeInsets/SizedBox 漏计（实测 $sites）——这正是逐行 grep 口径的'
          '盲区，立卡时全库此类调用点有 29+70 处；漏掉它们等于基线虚低、'
          '门禁对一半存量不可见。',
    );
    expect(
      sites.toSet(),
      equals({'<inline>:3', '<inline>:7'}),
      reason:
          '等长遮蔽的行号必须与原文对齐，否则 reason 里的定位会指错地方。'
          '（三引号后紧跟的首个换行不计入内容，故 `class W {` 是第 1 行，'
          '`EdgeInsets.only(` 是第 3 行、`SizedBox(` 是第 7 行。）',
    );
  });
}
