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
///   所在目录解析）同等对待（P1 修正，审计 2026-10-04：原正则只认 `package:`
///   URI，跨 feature 的相对路径 import 是盲区。归一化后实测与下方快照逐条
///   相等，说明当前 lib/features 内尚无此类 import，属潜伏盲区而非既有违规）；
/// - 扫描范围 = `lib/features/**` 全部 `.dart`，**组合根
///   （`app/`、`app.dart`）不在内**（见文件头）；
/// - 源 feature = 路径首段 `lib/features/<src>/`，目标 = import URI 里的
///   `features/<dst>/`，`src == dst`（同 feature 内分层 import）不计。
///
/// 本次实测（与本测试同口径）：notes->doc 9、notes->security 5、
/// notes->drawing 6、doc->notes 1、notes->all_docs 0、doc->security 0、
/// all_docs->notes 0、security->notes 0、security->doc 0、drawing->notes 0。
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
  'doc->notes': 1,
  'notes->all_docs': 0,
  'security->notes': 0,
  'security->doc': 0,
  'drawing->notes': 0,
  'doc->security': 0,
  'all_docs->notes': 0,
};

final RegExp _importRe = RegExp(
  r'''package:drawing_notes_app/features/([a-z_]+)/''',
);

void main() {
  test('跨 feature 依赖棘轮：不允许新增越界 import（只许逐步清零）', () {
    final counts = <String, int>{};
    final offenders = <String, List<String>>{};

    for (final entity in Directory('lib/features').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final normalized = entity.path.replaceAll('\\', '/');
      final srcMatch = RegExp(
        r'lib/features/([a-z_]+)/',
      ).firstMatch(normalized);
      if (srcMatch == null) continue;
      final src = srcMatch.group(1)!;
      for (final line in entity.readAsLinesSync()) {
        final m = _importRe.firstMatch(line);
        if (m == null) continue;
        final dst = m.group(1)!;
        if (dst == src) continue;
        final key = '$src->$dst';
        counts[key] = (counts[key] ?? 0) + 1;
        offenders.putIfAbsent(key, () => []).add('$normalized: ${line.trim()}');
      }
    }

    final violations = <String>[];
    for (final key in {...counts.keys, ..._baseline.keys}) {
      final actual = counts[key] ?? 0;
      final allowed = _baseline[key];
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

    expect(
      violations,
      isEmpty,
      reason:
          '跨 feature 依赖棘轮被突破：\n'
          '${violations.join('\n')}\n\n'
          '现有 offenders：\n'
          '${offenders.entries.expand((e) => e.value).take(20).join('\n')}',
    );
  });
}
