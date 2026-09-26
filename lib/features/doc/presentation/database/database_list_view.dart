/// 数据库块 — 列表视图（P3-2 拆分的展示型子组件）。
///
/// 纵向卡片列表，每项展示主字段 + 其余非空字段摘要。
/// 纯展示，把「删除」通过 [onRemoveRecord] 抛给协调者。
library;

import 'package:flutter/material.dart';
import 'package:drawing_notes_app/l10n/app_localizations.dart';

import 'package:drawing_notes_app/features/doc/domain/note_database.dart';
import '../../../../core/theme/apple_design.dart';

/// 列表视图。
class DatabaseListView extends StatelessWidget {
  const DatabaseListView({
    super.key,
    required this.fields,
    required this.records,
    required this.titleField,
    required this.displayValue,
    required this.onRemoveRecord,
  });

  /// 审计 2026-09-26 #16：超过该记录数才切换「限高内部滚动 + 行级虚拟
  /// 化」——常见量级（几十条内）保持自然高度、随文档页面滚动的既有交互
  /// 零变化。与 [databaseTableLargeRecordThreshold] 同值（语义耦合）。
  static const int largeRecordThreshold = 50;

  /// 大数据集的视口上限（约一屏高，内部滚动）。
  static const double maxViewportHeight = 480;

  final List<NoteFieldDef> fields;
  final List<NoteRecord> records;
  final NoteFieldDef? titleField;
  final String Function(NoteRecord record, NoteFieldDef field) displayValue;
  final ValueChanged<NoteRecord> onRemoveRecord;

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        alignment: Alignment.center,
        child: Text(
          '还没有记录，点击“添加记录”',
          style: AppleType.controlStyle(
            Theme.of(context).colorScheme.outline,
          ).copyWith(fontWeight: FontWeight.w400),
        ),
      );
    }
    // 大数据集：行级虚拟化（不可见行不 build/layout/paint）。
    if (records.length > largeRecordThreshold) {
      return SizedBox(
        height: maxViewportHeight,
        child: ListView.builder(
          itemCount: records.length,
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemBuilder: (context, i) => _tile(context, records[i]),
        ),
      );
    }
    return Column(children: [for (final r in records) _tile(context, r)]);
  }

  Widget _tile(BuildContext context, NoteRecord record) {
    final scheme = Theme.of(context).colorScheme;
    final t = titleField;
    final title = t != null ? displayValue(record, t) : '';
    final summary = fields
        .where((f) => f.id != t?.id && displayValue(record, f).isNotEmpty)
        .map((f) => '${f.name}: ${displayValue(record, f)}')
        .join(' · ');
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 0,
      child: ListTile(
        leading: Icon(Icons.article_outlined, color: scheme.primary),
        title: Text(
          title.isEmpty
              ? AppLocalizations.of(context)?.dbNoTitleRecord ?? '无标题记录'
              : title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(summary, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: IconButton(
          tooltip: AppLocalizations.of(context)?.dbDeleteRecord ?? '删除记录',
          icon: const Icon(Icons.close, size: 18),
          onPressed: () => onRemoveRecord(record),
        ),
      ),
    );
  }
}
