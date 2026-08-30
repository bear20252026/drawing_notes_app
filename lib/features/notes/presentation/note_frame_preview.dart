// 由 Claude 团队生成 | Drawing Notes App
// NoteFramePreview：Edgeless 模式下 note 帧的「只读块内容预览」。
//
// 1:1 AFFiNE edgeless：每个 note 帧（affine:note）是一张可拖拽/缩放的卡片，
// 内部按块模型渲染内容。本 widget 负责以只读方式渲染一帧内的 NoteBlockDoc
// 块序列，作为帧内容预览（帧内点按由宿主打开完整编辑器编辑）。
//
// 只依赖 notes/domain 的块模型（note_block.dart / note_block_doc.dart），
// 不 import 任何 drawing/chart 实现层（架构规则 3）。

import 'package:flutter/material.dart';

import 'package:drawing_notes_app/core/theme/apple_design.dart';
import 'package:drawing_notes_app/features/notes/domain/note_block.dart';
import 'package:drawing_notes_app/features/notes/domain/note_block_doc.dart';

/// 帧内只读块内容预览。
///
/// [doc]：要预览的块文档；[showTitle]：是否在顶部显示文档标题；
/// [padding]：帧内边距。块按 [NoteBlock] 类型做差异渲染（标题字级、列表前缀、
/// 待办勾选、引用左杠、代码等宽、分割线、内嵌占位等）。
class NoteFramePreview extends StatelessWidget {
  const NoteFramePreview({
    super.key,
    required this.doc,
    this.showTitle = false,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 12),
    this.inkColor,
  });

  /// 要预览的块文档。
  final NoteBlockDoc doc;

  /// 是否渲染文档标题（非空时显示为一级标题）。
  final bool showTitle;

  /// 帧内边距。
  final EdgeInsets padding;

  /// 纸面墨色。传入时覆盖默认的 `colorScheme.onSurface`，使深色模式下
  /// 白纸帧内容仍为深字可读；为 null 时用主题 onSurface（默认）。
  final Color? inkColor;

  @override
  Widget build(BuildContext context) {
    final title = doc.title;
    final blocks = doc.body;
    if (!showTitle && title.isEmpty && blocks.isEmpty) {
      return const SizedBox.shrink();
    }
    final counter = _orderedCounter();
    final ink = inkColor ?? Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showTitle && title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                  color: ink,
                ),
              ),
            ),
          ...blocks.map(
            (block) => _NoteBlockPreviewRow(
              block: block,
              orderedCounter: counter,
              inkColor: ink,
            ),
          ),
        ],
      ),
    );
  }
}

/// 有序列表编号：每次遇到 ordered 顶层块自增（共享闭包）。
int Function(NoteBlock block) _orderedCounter() {
  var index = 0;
  return (NoteBlock block) {
    if (block.type == NoteBlockType.ordered) {
      index += 1;
    }
    return index;
  };
}

/// 单块只读渲染（含递归 children）。
class _NoteBlockPreviewRow extends StatelessWidget {
  const _NoteBlockPreviewRow({
    required this.block,
    required this.orderedCounter,
    this.indent = 0,
    this.inkColor,
  });

  final NoteBlock block;
  final int Function(NoteBlock block) orderedCounter;
  final double indent;

  /// 纸面墨色（透传自宿主）；为 null 时用主题 onSurface。
  final Color? inkColor;

  @override
  Widget build(BuildContext context) {
    final ink = inkColor ?? Theme.of(context).colorScheme.onSurface;
    final baseStyle = _blockStyle(context, block, ink);
    final children = block.children;
    final content = _buildContent(context, baseStyle);
    final row = Padding(
      padding: EdgeInsets.only(left: indent, bottom: 4),
      child: content,
    );
    if (children.isEmpty) {
      return row;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        row,
        for (final child in children)
          _NoteBlockPreviewRow(
            block: child,
            orderedCounter: orderedCounter,
            indent: indent + 20,
            inkColor: ink,
          ),
      ],
    );
  }

  Widget _buildContent(BuildContext context, TextStyle baseStyle) {
    switch (block.type) {
      case NoteBlockType.heading:
        final level = (block.props['level'] as num?)?.toInt() ?? 1;
        return Text(
          block.text,
          style: baseStyle.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: _headingSize(level),
          ),
        );
      case NoteBlockType.bullet:
        return Text('•  ${block.text}', style: baseStyle);
      case NoteBlockType.ordered:
        final n = orderedCounter(block);
        return Text('$n.  ${block.text}', style: baseStyle);
      case NoteBlockType.todo:
        final checked = (block.props['checked'] as bool?) ?? false;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              checked ? Icons.check_box : Icons.check_box_outline_blank,
              size: 16,
              color: checked
                  ? AppleColor.noteGreen
                  : baseStyle.color!.withValues(alpha: 0.6),
            ),
            const SizedBox(width: AppleSpacing.xs),
            Expanded(
              child: Text(
                block.text,
                style: baseStyle.copyWith(
                  decoration: checked
                      ? TextDecoration.lineThrough
                      : TextDecoration.none,
                ),
                softWrap: true,
              ),
            ),
          ],
        );
      case NoteBlockType.code:
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: AppleSpacing.sm,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppleRadius.sm),
          ),
          child: Text(
            block.text.isNotEmpty ? block.text : '代码块',
            style: baseStyle.copyWith(
              fontFamily: 'monospace',
              fontSize: 13,
              height: 1.4,
            ),
          ),
        );
      case NoteBlockType.quote:
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.only(left: 10),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
                width: 3,
              ),
            ),
          ),
          child: Text(
            block.text,
            style: baseStyle.copyWith(fontStyle: FontStyle.italic),
          ),
        );
      case NoteBlockType.callout:
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppleSpacing.sm),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.secondaryContainer.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(AppleRadius.sm),
          ),
          child: Text(block.text, style: baseStyle),
        );
      case NoteBlockType.divider:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: AppleSpacing.xs),
          child: Divider(height: 1),
        );
      case NoteBlockType.image:
        final src = block.props['src'] as String? ?? '';
        return Row(
          children: [
            Icon(
              Icons.image_outlined,
              color: baseStyle.color!.withValues(alpha: 0.6),
              size: 16,
            ),
            const SizedBox(width: AppleSpacing.xs),
            Expanded(
              child: Text(
                src.isNotEmpty ? src : '图片',
                style: baseStyle.copyWith(
                  color: baseStyle.color!.withValues(alpha: 0.6),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
      case NoteBlockType.link:
        final href = block.props['href'] as String? ?? '';
        return Text(
          block.text.isEmpty ? (href.isEmpty ? '链接' : href) : block.text,
          style: baseStyle.copyWith(
            color: AppleColor.actionBlue,
            decoration: TextDecoration.underline,
          ),
        );
      case NoteBlockType.canvas:
        return _embeddedPlaceholder(
          context,
          '画布',
          Icons.polyline_outlined,
          baseStyle,
        );
      case NoteBlockType.chart:
        return _embeddedPlaceholder(
          context,
          '图表',
          Icons.bar_chart_outlined,
          baseStyle,
        );
      case NoteBlockType.table:
        return _embeddedPlaceholder(
          context,
          '表格',
          Icons.table_chart_outlined,
          baseStyle,
        );
      case NoteBlockType.database:
        return _embeddedPlaceholder(
          context,
          '数据库',
          Icons.dataset_outlined,
          baseStyle,
        );
      case NoteBlockType.attachment:
        return _embeddedPlaceholder(
          context,
          '附件',
          Icons.attachment_outlined,
          baseStyle,
        );
      case NoteBlockType.text:
        return Text(block.text, style: baseStyle, softWrap: true);
    }
  }

  Widget _embeddedPlaceholder(
    BuildContext context,
    String label,
    IconData icon,
    TextStyle baseStyle,
  ) {
    return Row(
      children: [
        Icon(icon, color: baseStyle.color!.withValues(alpha: 0.6), size: 16),
        const SizedBox(width: AppleSpacing.xs),
        Text(
          label,
          style: baseStyle.copyWith(
            color: baseStyle.color!.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  TextStyle _blockStyle(BuildContext context, NoteBlock block, Color ink) {
    final subtle = (block.props['checked'] as bool?) ?? false;
    return TextStyle(
      fontSize: 14,
      height: 1.5,
      color: ink,
      decoration: subtle ? TextDecoration.lineThrough : TextDecoration.none,
    );
  }

  double _headingSize(int level) => switch (level) {
    1 => 24,
    2 => 21,
    3 => 19,
    4 => 17,
    5 => 16,
    _ => 15,
  };
}
