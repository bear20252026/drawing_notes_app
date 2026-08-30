// 由 Claude 团队生成 | Drawing Notes App
// 标签视图（M12.6，AFFiNE Tags 对齐）：标签列表 + 点选过滤。
// 独立库（不依赖 all_docs_page 私有成员），由 all_docs_page_widgets 装配。

import 'package:flutter/material.dart';

import 'package:drawing_notes_app/features/all_docs/domain/all_doc.dart';
import 'package:drawing_notes_app/features/all_docs/infrastructure/tag_store.dart';
import 'package:drawing_notes_app/features/all_docs/presentation/all_doc_row.dart';

/// 标签视图：先列标签（带计数），点选后展示该标签下的打字笔记。
class TagsView extends StatefulWidget {
  const TagsView({super.key, required this.docs, this.loadTags});

  /// 全量文档（过滤用）。
  final List<AllDoc> docs;

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
      return const Center(child: CircularProgressIndicator());
    }
    if (tags.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.label_outline_rounded,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            const Text('暂无标签'),
            const SizedBox(height: 4),
            Text(
              '打开笔记 → 文档信息 → 添加标签',
              style: TextStyle(
                fontSize: 12.5,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
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
                InkWell(
                  onTap: () => setState(() => _selectedTagId = null),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.arrow_back_rounded, size: 18),
                      SizedBox(width: 4),
                      Text('全部标签'),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '# ${tagName ?? ''}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: docs.isEmpty
                ? const Center(child: Text('该标签下暂无笔记'))
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: docs.length,
                    separatorBuilder: (_, _) => Divider(
                      height: 1,
                      color: theme.dividerColor.withValues(alpha: 0.08),
                    ),
                    itemBuilder: (context, i) => AllDocRow(
                      doc: docs[i],
                      onOpenDoc: () {},
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
            color: Color(int.parse(tag.color)),
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
