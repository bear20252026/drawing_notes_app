// 跨 feature 依赖棘轮门禁（2026-09-06 整体架构审计）。
//
// 背景：`architecture_test.dart` 只强制 drawing↔notes 两个方向，而实际存在
// 52 处跨 feature import（审计 P0-1/P0-3：文档宣称"feature 之间零 import"，
// 门禁却未覆盖）。一次性迁完是大工程；本测试先把**当前基线**钉死：
// - 任何方向出现**新的**跨 feature import（数量超过基线）→ 红灯；
// - 修复迁移使数量下降后，应同步下调此处的基线数字（棘轮只紧不松）。
//
// 组合根（app/app_shell.dart、app.dart）是唯一允许全量装配的位置，不在
// lib/features 扫描范围内。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 当前基线（**2026-10-01 重立快照**，C-16 审计要求）：方向 → 允许的最大
/// import 条数。
///
/// 口径（C-16：原「29/6」与实测「9/5」对不上，即因口径未注明）：
/// - **计数单位 = 代码上下文里的 `import` / `export` 语句行数**（同一文件
///   重复 import 同一方向计多条），非「涉及文件数」、也非「符号引用数」；
///   再导出 `export` 与 `import` 同计——`notes->doc` 的 9 条里含 1 条
///   （`features/notes/domain/notebook.dart` 再导出 `doc/domain/clone_ref.dart`）；
/// - 语句行须行首即关键字（排除注释/字符串里的同形文本，与
///   `test/architecture/forbidden_import_test.dart` 同一取法）；
/// - 目标 feature 由 URI 归一化得出：`package:drawing_notes_app/features/<f>/`
///   与相对路径（`../<f>/`、`<f>/`、`../../drawing/rendering/` 等，按导入方
///   所在目录解析）同等对待。
///   ⚠️ **本条注释在 2026-10-01 写下时，实现并没有做相对路径归一化，也没有
///   锚定行首关键字**——只有 `_packageFeatureRe` 一条正则、且对整行做
///   `firstMatch`（审计 2026-10-04 记为「注释声称已修正、代码从未实现」，
///   台账 P2-3）。P2-3 于 2026-10-06（批次 AW10）真正补齐：`_statementRe`
///   锚定 `import`/`export` 行首，`_targetFeature` 把相对 URI 按导入方目录
///   解析后再归位。补齐后实测计数与下方快照**逐条相等**（印证「当前
///   lib/features 内尚无此类 import」）。当时的「突变自证：临时塞一条
///   `import '../../doc/domain/clone_ref.dart'` → 门禁当场报
///   `notes->doc：10 条 > 基线 9 条`（旧实现对此零反应）」是**手工做的、写在注释里**
///   ——2026-10-16 起它是 `判据自证` 那条会跑的用例了（TE-TST-04 补的正是这一格：
///   **注释里的自证不是自证**，它不会在下次改动时再响一次）。
///   ⇒ 教训：**注释里的口径必须与代码一致**，否则一条写了三年的"已修正"
///   比没写更危险——它让后来人以为盲区已经闭上，不再去查。
///
/// ── TE-TST-04 / R10（2026-10-16）：这条棘轮原本是「空集即通过」最别扭的一格 ──
/// 扫描面塌掉 ⇒ `counts` 是空映射 ⇒ `actual > allowed` **永不成立** ⇒ 棘轮不但判合格，
/// 还比平时更容易绿（别的门禁至少要有人写违规代码才红，这条连都不用）。
/// 补两件事：① `棘轮自证` 钉两条与依赖治理进度**无关**的下限（读到的文件数、认出的
/// import/export 行数——注意**不能**把下限钉在跨 feature 条数上，那是会被清干净的，
/// 钉上去等于在有人修好依赖时把门禁打红、奖励绕过它）；② 判据抽成纯函数
/// （`countCrossFeature` / `ratchetViolations`），喂人造图逐格验证承重面。
/// 突变自证：M-R1 `_targetFeature` 不再解析相对 URI ⇒ `判据自证` 红（notes->doc 少计）；
/// M-R2 `_statementRe` 去掉行首锚定 ⇒ `判据自证` 红（注释/字符串里的同形文本被计入）；
/// M-R3 `ratchetViolations` 的 `actual > allowed` 改成恒 false ⇒ `判据自证` 红而真实库绿
/// ⇒ 与 R8/R9 同格：只做下限抓不到「判据本身恒空」。
/// - 扫描范围 = `lib/features/**` 全部 `.dart`，**组合根
///   （`app/`、`app.dart`）不在内**（见文件头）；
/// - 源 feature = 路径首段 `lib/features/<src>/`，目标 = import URI 里的
///   `features/<dst>/`，`src == dst`（同 feature 内分层 import）不计。
///
/// 本次实测（与本测试同口径）：notes->doc 9、notes->security 5、
/// notes->drawing 6、doc->notes 0、notes->all_docs 0、doc->security 0、
/// all_docs->notes 0、security->notes 0、security->doc 0、drawing->notes 0。
/// R49（审计 2026-10-17）doc->notes 1→0：`migrateNotebookPage` 那份合一实现从
/// doc/domain 搬到 notes/domain（它的唯一 feature 依赖是 NotebookPage），
/// 于是 doc→notes 归零；R48 合一当初新增的那条 notes→doc 也随之消失（回 9）。
/// C-09（审计 2026-09-27，v1.17.54）：doc->notes 2→1（PdfAttachmentPreview
/// 随唯一消费方迁 doc）、doc->security 1→0（DocPage 重置流改组合根注入）、
/// notes->all_docs 2→0 与 all_docs->notes 1→0（AllDoc 契约+查询纯函数
/// 下沉 core，Notebook 经 core 只读接口满足查询输入，环解体）。
/// 基线全部收紧至实测值（棘轮只紧不松）；原值 29/6/7/3 系 2026-09-06 快照，
/// 其后 v1.17.26「home_page 直连 infra 收口」等迁移已实际下降但基线未回跟。
///
/// notes->drawing 现值 6（v1.17.51 重立快照实测）：无限画布整图 PDF 导出复用
/// 全仓唯一 PDF 引擎 `pdf_hybrid_exporter`——与 notebook_pdf_exporter 同源的
/// 「单一事实来源」先例，非新横向耦合面。历史注释曾记「6→7（v1.17.17）」，
/// 属 v1.17.51 重立快照前的中间态，已随基线回跟作废（以本行现值为准）。
const Map<String, int> _baseline = {
  // notes->doc 29→9（2026-10-01，C-16 重立快照）：home_page 对
  // doc/infrastructure 的 BlockDocSearchAccessorImpl 直连已改 core 契约 +
  // 组合根注入（v1.17.26，审计 #17），基线回跟实测。
  'notes->doc': 9,
  'notes->security': 5,
  'notes->drawing': 6,
  'doc->notes': 0,
  'notes->all_docs': 0,
  'security->notes': 0,
  'security->doc': 0,
  'drawing->notes': 0,
  'doc->security': 0,
  'all_docs->notes': 0,
};

/// 语句行锚定：去前导空白后必须以 `import` / `export` 开头并紧跟一个
/// 引号包裹的 URI。注释、字符串内部、文档示例里的同形文本因此不计
/// （口径注释从 2026-10-01 就承诺了这条，实现漏了——P2-3 本轮补上）。
final RegExp _statementRe = RegExp(
  r'''^(?:import|export)\s+(['"])([^'"]+)\1''',
);

/// `package:drawing_notes_app/features/<f>/…` → `<f>`。
final RegExp _packageFeatureRe = RegExp(
  r'''^package:drawing_notes_app/features/([a-z_]+)/''',
);

/// 相对 URI 按导入方目录解析后，落在 `lib/features/<f>/` 下 → `<f>`。
final RegExp _resolvedFeatureRe = RegExp(r'''^lib/features/([a-z_]+)/''');

/// 把相对 URI 按导入方所在目录解析成仓库根视角的路径（就地折叠 `.` / `..`）。
/// 不这么做，`import '../../drawing/rendering/x.dart'` 这类跨 feature 相对
/// 引用就完全绕过棘轮——而 Dart 的相对 import **不要求文件真实存在**，
/// 分析器与 `check_boundaries.sh`（规则 2 对 notes→drawing 仅 informational）
/// 都不拦，等于一条静默通道（P2-3 的原始发现）。
String _resolveRelative(String fromDir, String uri) {
  final segments = <String>[];
  for (final part in <String>[...fromDir.split('/'), ...uri.split('/')]) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (segments.isNotEmpty) segments.removeLast();
      continue;
    }
    segments.add(part);
  }
  return segments.join('/');
}

/// 目标 feature：`package:` 直接取段；其它 `package:`/`dart:` 一律不算；
/// 相对路径解析后按目录归位。
String? _targetFeature({required String uri, required String fromDir}) {
  final pkg = _packageFeatureRe.firstMatch(uri);
  if (pkg != null) return pkg.group(1);
  if (uri.startsWith('dart:') || uri.startsWith('package:')) return null;
  return _resolvedFeatureRe.firstMatch(_resolveRelative(fromDir, uri))?.group(1);
}

/// 读盘：`lib/features/**` 全部 .dart，返回「仓库根视角路径 → 逐行文本」。
Map<String, List<String>> readFeatureSources() {
  final result = <String, List<String>>{};
  for (final entity in Directory('lib/features').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final normalized = entity.path.replaceAll('\\', '/');
    if (!_srcFeatureRe.hasMatch(normalized)) continue;
    result[normalized] = entity.readAsLinesSync();
  }
  return result;
}

final RegExp _srcFeatureRe = RegExp(r'lib/features/([a-z_]+)/');

/// 判据一：方向计数。输入「路径 → 逐行文本」，输出「`src->dst` → 条数」。
///
/// 从 `main()` 里抽出来不是为了好看（审计 TE-TST-04 / R8 同一口径）：抽出来之后，
/// 文件头那句**只存在于注释里**的「突变自证：临时塞一条
/// `import '../../doc/domain/clone_ref.dart'` → 当场报超限」才第一次变成一条会跑的
/// 用例（见 `判据自证`）。注释写着的自证不是自证。
Map<String, int> countCrossFeature(Map<String, List<String>> linesByFile) {
  final counts = <String, int>{};
  for (final entry in linesByFile.entries) {
    final srcMatch = _srcFeatureRe.firstMatch(entry.key);
    if (srcMatch == null) continue;
    final src = srcMatch.group(1)!;
    final fromDir = entry.key.substring(0, entry.key.lastIndexOf('/') + 1);
    for (final line in entry.value) {
      final stmt = _statementRe.firstMatch(line.trimLeft());
      if (stmt == null) continue;
      final dst = _targetFeature(uri: stmt.group(2)!, fromDir: fromDir);
      if (dst == null || dst == src) continue;
      final key = '$src->$dst';
      counts[key] = (counts[key] ?? 0) + 1;
    }
  }
  return counts;
}

/// 判据二：把计数对到基线上。新方向（基线里没有）与超线都算违规。
List<String> ratchetViolations(Map<String, int> counts, Map<String, int> baseline) {
  final violations = <String>[];
  for (final key in {...counts.keys, ...baseline.keys}) {
    final actual = counts[key] ?? 0;
    final allowed = baseline[key];
    if (allowed == null) {
      violations.add(
        '$key：新增越界方向（$actual 条，基线为 0）——'
        '跨 feature 依赖必须经组合根或 application 契约',
      );
    } else if (actual > allowed) {
      violations.add(
        '$key：$actual 条 > 基线 $allowed 条。新增 import 违反棘轮基线；'
        '如属必要重构，请先评审并在本测试下调基线',
      );
    }
  }
  return violations;
}

/// 判据一的明细（只为把违规打印到人能看懂的位置，不参与裁决）。
Map<String, List<String>> collectCrossFeatureDetail(
  Map<String, List<String>> linesByFile,
) {
  final detail = <String, List<String>>{};
  for (final entry in linesByFile.entries) {
    final srcMatch = _srcFeatureRe.firstMatch(entry.key);
    if (srcMatch == null) continue;
    final src = srcMatch.group(1)!;
    final fromDir = entry.key.substring(0, entry.key.lastIndexOf('/') + 1);
    for (final line in entry.value) {
      final stmt = _statementRe.firstMatch(line.trimLeft());
      if (stmt == null) continue;
      final dst = _targetFeature(uri: stmt.group(2)!, fromDir: fromDir);
      if (dst == null || dst == src) continue;
      detail.putIfAbsent('$src->$dst', () => []).add(
        '${entry.key}: ${line.trim()}',
      );
    }
  }
  return detail;
}

void main() {
  final sources = readFeatureSources();

  test('跨 feature 依赖棘轮：不允许新增越界 import（只许逐步清零）', () {
    final violations = ratchetViolations(countCrossFeature(sources), _baseline);
    expect(
      violations,
      isEmpty,
      reason:
          '跨 feature 依赖棘轮被突破：\n'
          '${violations.join('\n')}\n\n'
          '现有 offenders：\n'
          '${collectCrossFeatureDetail(sources).entries.expand((e) => e.value).take(20).join('\n')}',
    );
  });

  test('棘轮自证：扫描面塌掉 ⇒ 红（TE-TST-04；下限**不**钉在依赖计数上）', () {
    // 为什么下限钉在「读到的文件数 / import 语句行数」而不是「跨 feature 条数」：
    // 后者是**会被清干净的**——迁移做完就是 0，那正是这条棘轮想要的结果。
    // 把下限设成 21（今天的实测跨 feature 总数）会在有人把依赖修好之后把门禁打红，
    // 等于奖励绕过它。前者与依赖治理进度无关，塌掉只可能是扫描本身坏了。
    expect(
      sources.length,
      greaterThanOrEqualTo(180),
      reason:
          'lib/features 下只读到 ${sources.length} 个 .dart（实测基线 210）⇒ 扫描根/后缀/'
          'feature 名判定塌了。此时 `counts` 是空映射，`actual > allowed` 永远不成立，'
          '上面那条 `isEmpty` 断言就变成「没人违规因为我没在看」。',
    );
    final stmtLines = sources.values.fold<int>(
      0,
      (sum, lines) => sum + lines.where((l) => _statementRe.hasMatch(l.trimLeft())).length,
    );
    expect(
      stmtLines,
      greaterThanOrEqualTo(900),
      reason:
          '读到 ${sources.length} 个文件却只认出 $stmtLines 行 import/export 语句'
          '（实测基线 1074）⇒ `_statementRe` 的行首锚定被改坏了（P2-3 修的就是这条），'
          '跨 feature 计数会静默归零。',
    );
  });

  test('判据自证：相对路径 / 同 feature / 注释 / 字符串四种形状各判对（P2-3 的落点）', () {
    // 文件头那句「临时塞一条相对 import 门禁当场报超限」的自证，从这一版起是真用例。
    final synthetic = <String, List<String>>{
      'lib/features/notes/presentation/x.dart': [
        "import '../../doc/domain/clone_ref.dart';",
        "import 'package:drawing_notes_app/features/security/vault.dart';",
        "import 'home_page.dart';",
        "import 'dart:async';",
        "// import '../../drawing/rendering/ink.dart';",
        "final s = 'import \\'../../drawing/rendering/hidden.dart\\';';",
      ],
      'lib/features/doc/presentation/y.dart': [
        "import '../../notes/domain/note.dart';",
      ],
    };
    expect(
      countCrossFeature(synthetic),
      const <String, int>{'notes->doc': 1, 'notes->security': 1, 'doc->notes': 1},
      reason: '逐条都是判据的承重面：相对 URI 不解析 ⇒ notes→doc 这条静默绕过（P2-3 原案）；'
          '同 feature、`dart:`、注释行、字符串里的同形文本都必须**不**计数——'
          '任何一格判错，这张表就对不上。',
    );

    // 棘轮判据本身也要能红：超线一位、恰好到线、新方向各一格。
    expect(
      ratchetViolations(const {'notes->doc': 10}, _baseline),
      hasLength(1),
      reason: '10 > 基线 9 ⇒ 必须报（突变：把 `actual > allowed` 改成恒 false，这里就零报了）',
    );
    expect(
      ratchetViolations(const {'notes->doc': 9}, _baseline),
      isEmpty,
      reason: '恰好等于基线不算违规——棘轮只紧不松，不能把已达标的迁移判红',
    );
    expect(
      ratchetViolations(const {'drawing->security': 1}, _baseline),
      hasLength(1),
      reason: '基线里没有的新方向（含只有一条的）必须报',
    );
    expect(
      ratchetViolations(const <String, int>{}, _baseline),
      isEmpty,
      reason: '依赖被迁干净 ⇒ 全零是**合格**，不是失明（失明由上面那条下限抓）',
    );
  });
}
