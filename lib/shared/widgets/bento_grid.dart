import 'package:flutter/material.dart';

/// Bento Grid 布局组件。
///
/// 灵感来源：Inspira UI bento-grid
/// 适配：Material 3 风格，支持不规则网格排列。
///
/// 用于首页画作展示、仪表盘等场景。
class BentoGrid extends StatelessWidget {
  /// 网格项列表。
  final List<BentoGridItem> items;

  /// 列数。
  final int columns;

  /// 间距。
  final double spacing;

  /// 圆角半径。
  final double borderRadius;

  /// 内边距。
  final EdgeInsetsGeometry padding;

  const BentoGrid({
    super.key,
    required this.items,
    this.columns = 3,
    this.spacing = 8.0,
    this.borderRadius = 16.0,
    this.padding = const EdgeInsets.all(16.0),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final itemWidth =
              (constraints.maxWidth - spacing * (columns - 1)) / columns;
          return SingleChildScrollView(
            child: _buildGrid(context, itemWidth),
          );
        },
      ),
    );
  }

  Widget _buildGrid(BuildContext context, double itemWidth) {
    final rows = <Widget>[];
    var i = 0;

    while (i < items.length) {
      final rowItems = <Widget>[];
      var rowSpan = 0;

      // 计算当前行的列跨度。
      while (rowSpan < columns && i < items.length) {
        final item = items[i];
        final colSpan = item.columnSpan.clamp(1, columns - rowSpan);

        rowItems.add(
          SizedBox(
            width: itemWidth * colSpan + spacing * (colSpan - 1),
            height: item.rowSpan * itemWidth + (item.rowSpan - 1) * spacing,
            child: _BentoGridTile(
              item: item,
              borderRadius: borderRadius,
            ),
          ),
        );

        rowSpan += colSpan;
        i++;

        if (rowSpan < columns && i < items.length) {
          rowItems.add(SizedBox(width: spacing));
        }
      }

      rows.add(Row(children: rowItems));

      if (i < items.length) {
        rows.add(SizedBox(height: spacing));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rows,
    );
  }
}

/// Bento Grid 单个网格项。
class BentoGridItem {
  /// 列跨度（占多少列）。
  final int columnSpan;

  /// 行跨度（占多少行）。
  final int rowSpan;

  /// 背景色。
  final Color? backgroundColor;

  /// 背景渐变。
  final Gradient? gradient;

  /// 子组件。
  final Widget child;

  /// 点击回调。
  final VoidCallback? onTap;

  const BentoGridItem({
    this.columnSpan = 1,
    this.rowSpan = 1,
    this.backgroundColor,
    this.gradient,
    required this.child,
    this.onTap,
  });
}

/// Bento Grid 单个瓦片。
class _BentoGridTile extends StatelessWidget {
  final BentoGridItem item;
  final double borderRadius;

  const _BentoGridTile({
    required this.item,
    required this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget content = Container(
      decoration: BoxDecoration(
        color: item.backgroundColor ?? theme.colorScheme.surfaceContainerHighest,
        gradient: item.gradient,
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: item.child,
    );

    if (item.onTap != null) {
      content = InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(borderRadius),
        child: content,
      );
    }

    return content;
  }
}
