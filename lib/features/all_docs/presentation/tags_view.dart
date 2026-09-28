// 由 Claude 团队生成 | Drawing Notes App
// 标签视图（M12.6，AFFiNE Tags 对齐）：标签列表 + 点选过滤。
// 独立库（不依赖 all_docs_page 私有成员），由 all_docs_page_widgets 装配。

import 'package:flutter/material.dart';

import 'package:drawing_notes_app/core/theme/apple_design.dart';

import 'package:drawing_notes_app/features/all_docs/domain/all_doc.dart';
import 'package:drawing_notes_app/core/storage/tag_store.dart';
import 'package:drawing_notes_app/shared/widgets/apple_empty_state.dart';
import 'package:drawing_notes_app/core/theme/apple_elevation.dart';
import 'package:drawing_notes_app/l10n/app_localizations.dart';
import 'package:drawing_notes_app/features/all_docs/presentation/all_doc_row.dart';
import 'package:drawing_notes_app/shared/widgets/skeleton.dart';

/// 标签视图：先列标签（带计数），点选后展示该标签下的打字笔记。
class TagsView extends StatefulWidget {
  const TagsView({
    super.key,
    required this.docs,
    required this.onOpenDoc,
    this.loadTags,
  });

  /// 全量文档（过滤用）。
  final List<AllDoc> docs;

  /// 打开文档回调（V-13 审计 2026-09-27：标签下钻文档行此前传空回调
  /// `onOpenDoc: () {}`——可点但毫无反应的死入口）。
  final void Function(AllDoc doc) onOpenDoc;

  /// 标签注册表读取。
  final Future<List<DocTag>> Function()? loadTags;

  @override
  State<TagsView> createState() => _TagsViewState();
}

class _TagsViewState extends State<TagsView> {
  List<DocTag>? _tags;
  String? _selectedTagId;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final tags = await widget.loadTags?.call() ?? const <DocTag>[];
    if (!mounted) return;
    setState(() => _tags = tags);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tags = _tags;
    if (tags == null) {
      // 审计二-6：列表加载用骨架屏（形态先行），与全部文档页同语言。
      return const Center(child: SkeletonList(rows: 4));
    }
    if (tags.isEmpty) {
      // 空态统一（审计二-4）：收编到共享 AppleEmptyState。
      final l10n = AppLocalizations.of(context);
      return AppleEmptyState(
        icon: Icons.label_outline_rounded,
        title: l10n?.tagsEmpty ?? '暂无标签',
        tip: l10n?.tagsEmptyTip ?? '打开笔记 → 文档信息 → 添加标签',
      );
    }
    if (_selectedTagId != null) {
      final docs = widget.docs
          .where(
            (d) =>
                d.kind == AllDocKind.blockdoc &&
                d.tags.contains(_selectedTagId),
          )
          .toList();
      final tagName = tags
          .where((t) => t.id == _selectedTagId)
          .map((t) => t.name)
          .firstOrNull;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                // 热区补足 44（审计二-1）：18px 图标 + 垂直 13px 内边距。
                InkWell(
                  onTap: () => setState(() => _selectedTagId = null),
                  borderRadius: BorderRadius.circular(AppleRadius.sm),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 13,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.arrow_back_rounded, size: 18),
                        SizedBox(width: 4),
                        Text(AppLocalizations.of(context)?.tagsAll ?? '全部标签'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '# ${tagName ?? ''}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: docs.isEmpty
                ? Center(
                    child: Text(
                      AppLocalizations.of(context)?.tagsNoDocs ?? '该标签下暂无笔记',
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: docs.length,
                    separatorBuilder: (context, _) => AppleHairline.listDivider(
                      context,
                      indent: AllDocRow.textIndent,
                    ),
                    itemBuilder: (context, i) => AllDocRow(
                      doc: docs[i],
                      onOpenDoc: () => widget.onOpenDoc(docs[i]),
                      onToggleFavorite: () {},
                    ),
                  ),
          ),
        ],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: tags.length,
      itemBuilder: (context, i) {
        final tag = tags[i];
        final count = widget.docs
            .where(
              (d) => d.kind == AllDocKind.blockdoc && d.tags.contains(tag.id),
            )
            .length;
        return ListTile(
          leading: Icon(
            Icons.label_rounded,
            // R-06（审计 2026-09-27）：标签颜色来自盘上明文 JSON，可能损坏/
            // 手工编辑——int.parse 抛 FormatException 会灰屏整页（无
            // ErrorWidget 兜底面）。tryParse + 主题色兜底。
            color: _tagColorOrNull(tag.color) ?? theme.colorScheme.primary,
          ),
          title: Text(tag.name),
          trailing: Text(
            '$count',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
          onTap: () => setState(() => _selectedTagId = tag.id),
        );
      },
    );
  }
}

/// R-06（审计 2026-09-27）：解析标签 ARGB 颜色——损坏/手工编辑的 JSON 返回
/// null（调用方落主题色兜底），不再在构建期抛 FormatException 灰屏整页。
Color? _tagColorOrNull(String raw) {
  final argb = int.tryParse(raw);
  return argb == null ? null : Color(argb);
}
