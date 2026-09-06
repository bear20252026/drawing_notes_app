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

/// 当前基线（2026-09-06 快照）：方向 → 允许的最大 import 条数。
const Map<String, int> _baseline = {
  'notes->doc': 30,
  'notes->security': 6,
  'notes->drawing': 6,
  'doc->notes': 3,
  'notes->all_docs': 2,
  'security->notes': 1,
  'security->doc': 1,
  'drawing->notes': 1,
  'doc->security': 1,
  'all_docs->notes': 1,
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
