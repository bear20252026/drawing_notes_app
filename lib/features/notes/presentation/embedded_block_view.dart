/// 内嵌块渲染部件（EmbeddedBlockView）。
///
/// 当 [NoteBlock] 类型为 canvas / chart / image / link / table / database 时，
/// 不渲染可编辑 TextField，而是渲染对应的富内嵌部件。
///
/// 架构约束：
/// - notes 展示层**不得** import drawing/chart 实现。
/// - 通过构造参数 [embeddedBuilder] 由组合根（app_shell）注入自定义渲染。
/// - 当 [embeddedBuilder] 为 null 或返回 null 时，走默认降级渲染。
library;

import 'package:flutter/material.dart';

import 'package:drawing_notes_app/features/notes/domain/note_block.dart';

/// 内嵌块视图：按块类型分发到对应的富渲染。
///
/// 渲染优先级：
/// 1. 若 [embeddedBuilder] 非 null 且返回非 null → 使用自定义部件。
/// 2. 否则 → 使用内置默认降级渲染。
class EmbeddedBlockView extends StatelessWidget {
  const EmbeddedBlockView({
    super.key,
    required this.block,
    this.embeddedBuilder,
  });

  /// 要渲染的内嵌块。
  final NoteBlock block;

  /// 由组合根注入的自定义块渲染回调（可为 null）。
  /// 返回 null 时走默认降级渲染。
  final Widget? Function(NoteBlock block)? embeddedBuilder;

  /// 判断是否为内嵌块类型（非文本编辑块）。
  static bool isEmbeddedType(NoteBlockType type) {
    return type == NoteBlockType.canvas ||
        type == NoteBlockType.chart ||
        type == NoteBlockType.image ||
        type == NoteBlockType.link ||
        type == NoteBlockType.table ||
        type == NoteBlockType.database;
  }

  @override
  Widget build(BuildContext context) {
    // 优先使用注入的自定义 builder
    final customWidget = embeddedBuilder?.call(block);
    if (customWidget != null) return customWidget;

    // 默认降级渲染
    switch (block.type) {
      case NoteBlockType.image:
        return _buildImage(context);
      case NoteBlockType.link:
        return _buildLink(context);
      case NoteBlockType.table:
        return _buildTable(context);
      case NoteBlockType.database:
        return _buildDatabase(context);
      case NoteBlockType.canvas:
      case NoteBlockType.chart:
        return _buildPlaceholder(context);
      default:
        return const SizedBox.shrink();
    }
  }

  // ── 图片 ───────────────────────────────────────────────────

  Widget _buildImage(BuildContext context) {
    final src = block.props['src'] as String? ?? '';
    final caption = block.props['alt'] as String? ?? '';

    if (src.isEmpty) {
      return _buildPlaceholderCard(
        context,
        icon: Icons.broken_image_outlined,
        label: '图片（无来源）',
        caption: caption,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              src,
              fit: BoxFit.cover,
              height: 200,
              width: double.infinity,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  height: 160,
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.broken_image_outlined,
                        size: 48,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '图片加载失败',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          if (caption.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              caption,
              style: TextStyle(
                fontSize: 13,
                fontStyle: FontStyle.italic,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── 链接 ───────────────────────────────────────────────────

  Widget _buildLink(BuildContext context) {
    final href = block.props['href'] as String? ?? '';
    final caption = block.props['title'] as String? ?? '';

    if (href.isEmpty) {
      return _buildPlaceholderCard(
        context,
        icon: Icons.link_off,
        label: '链接（无地址）',
        caption: caption,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () {
          // 实际项目中应使用 url_launcher；此处仅展示链接样式
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('打开链接: $href'),
              duration: const Duration(seconds: 2),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .primaryContainer
                .withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.link,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      caption.isNotEmpty ? caption : href,
                      style: TextStyle(
                        fontSize: 15,
                        color: Theme.of(context).colorScheme.primary,
                        decoration: TextDecoration.underline,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (caption.isNotEmpty && caption != href) ...[
                      const SizedBox(height: 2),
                      Text(
                        href,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.open_in_new,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 表格 ───────────────────────────────────────────────────

  Widget _buildTable(BuildContext context) {
    final rows = (block.props['rows'] as int? ?? 1).clamp(1, 50);
    final cols = (block.props['cols'] as int? ?? 1).clamp(1, 10);

    // 从 children 中提取单元格文本（每个 child 是一个 text 块）
    final cellTexts = <String>[];
    for (final child in block.children) {
      cellTexts.add(child.text);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          border: TableBorder.all(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 1,
          ),
          defaultColumnWidth: const FixedColumnWidth(100),
          children: List.generate(rows, (rowIndex) {
            return TableRow(
              children: List.generate(cols, (colIndex) {
                final cellIndex = rowIndex * cols + colIndex;
                final text =
                    cellIndex < cellTexts.length ? cellTexts[cellIndex] : '';
                return Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    text,
                    style: const TextStyle(fontSize: 14),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }),
            );
          }),
        ),
      ),
    );
  }

  // ── 数据库 ─────────────────────────────────────────────────

  Widget _buildDatabase(BuildContext context) {
    final records = block.props['records'];
    final List<dynamic> recordList;
    if (records is List) {
      recordList = records;
    } else {
      recordList = const [];
    }

    // 紧凑 JSON 面片（截断显示）
    final jsonStr = recordList.toString();
    final displayJson = jsonStr.length > 200
        ? '${jsonStr.substring(0, 200)}...'
        : jsonStr;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.table_chart_outlined,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '数据库',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${recordList.length} 条记录',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              displayJson,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
              ),
              maxLines: 8,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // ── 通用占位卡片（canvas / chart） ──────────────────────────

  Widget _buildPlaceholder(BuildContext context) {
    final isCanvas = block.type == NoteBlockType.canvas;
    return _buildPlaceholderCard(
      context,
      icon: isCanvas ? Icons.dashboard_customize_outlined : Icons.bar_chart,
      label: isCanvas ? '内嵌画布' : '内嵌图表',
      caption: '由宿主提供 builder 以渲染完整内容',
    );
  }

  // ── 通用占位卡片 ───────────────────────────────────────────

  Widget _buildPlaceholderCard(
    BuildContext context, {
    required IconData icon,
    required String label,
    String? caption,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 40,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            if (caption != null && caption.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                caption,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.7),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
