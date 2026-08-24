// Inspira UI · Dock —— macOS 风格快捷工具栏（悬停邻近放大）。
//
// 灵感来自 Inspira UI / Aceternity 的 Dock 组件（MIT），本项目以纯 Flutter
// 重写并按 drawing_notes_app 的设计体系适配（复用 GlassSurface 玻璃底）。
//
// 设计要点：
// - 悬停时按「指针 ↔ 图标中心」距离做高斯衰减放大，接近 macOS Dock 手感；
// - 触屏 / 无鼠标环境没有 hover 事件，自动退化为等宽静态栏；
// - 尊重系统「减弱动态效果」（MediaQuery.disableAnimationsOf）：不放大不动画；
// - 四个停靠边（bottom/top/left/right）；放大沿停靠边生长，不挤压相邻内容。

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../glass_surface.dart';

/// Dock 停靠边：决定生长方向与主轴。
enum InspiraDockEdge { bottom, top, left, right }

/// Dock 单个条目。
class InspiraDockItem {
  const InspiraDockItem({
    required this.child,
    required this.label,
    this.onTap,
    this.tooltip,
    this.accentColor,
  });

  /// 条目内容（通常是 Icon，尺寸建议 ≤ baseSize * 0.55）。
  final Widget child;

  /// 无障碍标签（同时作为默认 tooltip 文案）。
  final String label;

  final VoidCallback? onTap;

  /// 自定义 tooltip 文案；缺省用 [label]。
  final String? tooltip;

  /// 可选强调色（作为图标容器的浅色底）。
  final Color? accentColor;
}

/// macOS 风格 Dock 工具栏。
///
/// ```dart
/// InspiraDock(
///   items: [
///     InspiraDockItem(child: Icon(Icons.brush), label: '画笔', onTap: ...),
///     InspiraDockItem(child: Icon(Icons.cleaning_services), label: '橡皮'),
///   ],
/// )
/// ```
class InspiraDock extends StatefulWidget {
  const InspiraDock({
    super.key,
    required this.items,
    this.edge = InspiraDockEdge.bottom,
    this.baseSize = 46,
    this.maxMagnification = 1.55,
    this.influenceRadius = 110,
    this.itemGap = 8,
    this.glass = true,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  }) : assert(maxMagnification >= 1),
       assert(influenceRadius > 0);

  final List<InspiraDockItem> items;

  /// 停靠边。bottom/top 为主轴水平的工具栏，left/right 为垂直。
  final InspiraDockEdge edge;

  bool get _isHorizontal => edge == InspiraDockEdge.bottom ||
      edge == InspiraDockEdge.top;

  /// 静止态图标容器边长。
  final double baseSize;

  /// 指针正下方图标的最大放大倍数。
  final double maxMagnification;

  /// 放大影响半径（逻辑像素）；距离超过它的图标不再放大。
  final double influenceRadius;

  final double itemGap;

  /// 是否使用玻璃表面背景（复用应用内 GlassSurface）。
  final bool glass;

  final EdgeInsetsGeometry padding;

  @override
  State<InspiraDock> createState() => _InspiraDockState();
}

class _InspiraDockState extends State<InspiraDock> {
  /// 指针在 Dock 主轴上的位置；null 表示不在 Dock 内。
  double? _pointerMainAxis;

  // 高斯衰减的 σ：让影响半径边缘处增益平滑趋近 0（约 2.5σ 截断）。
  double get _sigma => widget.influenceRadius / 2.5;

  /// 距离衰减系数 ∈ [0, 1]：0=无增益，1=正下方。
  double _falloff(double itemCenter, double pointer) {
    final d = (itemCenter - pointer).abs();
    if (d >= widget.influenceRadius) return 0;
    return math.exp(-(d * d) / (2 * _sigma * _sigma));
  }

  double _scaleFor(int index) {
    if (_pointerMainAxis == null) return 1;
    final slot = widget.baseSize + widget.itemGap;
    final center =
        widget.baseSize / 2 + index * slot;
    final gain =
        (widget.maxMagnification - 1) * _falloff(center, _pointerMainAxis!);
    return 1 + gain;
  }

  Alignment get _growAlign => switch (widget.edge) {
        InspiraDockEdge.bottom => Alignment.bottomCenter,
        InspiraDockEdge.top => Alignment.topCenter,
        InspiraDockEdge.left => Alignment.centerLeft,
        InspiraDockEdge.right => Alignment.centerRight,
      };

  @override
  Widget build(BuildContext context) {
    final reduceEffects = MediaQuery.disableAnimationsOf(context);
    final magnifyEnabled = !reduceEffects;

    // MouseRegion 包在内容区（Padding 内）而非整个玻璃容器上，
    // 保证 onHover 的局部坐标与条目中心的静态公式同一坐标系。
    Widget content = Padding(
      padding: widget.padding,
      child: Builder(
        builder: (innerContext) => MouseRegion(
          cursor: SystemMouseCursors.click,
          onHover: magnifyEnabled
              ? (event) {
                  final box = innerContext.findRenderObject()! as RenderBox;
                  final local = box.globalToLocal(event.position);
                  setState(() {
                    _pointerMainAxis =
                        widget._isHorizontal ? local.dx : local.dy;
                  });
                }
              : null,
          onExit: magnifyEnabled
              ? (_) => setState(() => _pointerMainAxis = null)
              : null,
          child: widget._isHorizontal
              ? Row(mainAxisSize: MainAxisSize.min, children: _buildItems(magnifyEnabled))
              : Column(mainAxisSize: MainAxisSize.min, children: _buildItems(magnifyEnabled)),
        ),
      ),
    );

    if (widget.glass) {
      content = GlassSurface(
        borderRadius: BorderRadius.circular(20),
        padding: EdgeInsets.zero,
        child: content,
      );
    } else {
      content = Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        child: content,
      );
    }

    return content;
  }

  List<Widget> _buildItems(bool magnifyEnabled) {
    final crossExtent = widget.baseSize * widget.maxMagnification;
    return List.generate(widget.items.length, (i) {
      final item = widget.items[i];
      final scale = magnifyEnabled ? _scaleFor(i) : 1.0;

      final iconBox = Container(
        width: widget.baseSize,
        height: widget.baseSize,
        decoration: BoxDecoration(
          color: item.accentColor?.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(13),
        ),
        alignment: Alignment.center,
        child: IconTheme.merge(
          data: const IconThemeData(size: 24),
          child: item.child,
        ),
      );

      Widget slot = SizedBox(
        width: widget._isHorizontal ? widget.baseSize * scale : crossExtent,
        height: widget._isHorizontal ? crossExtent : widget.baseSize * scale,
        child: Align(
          alignment: _growAlign,
          child: Transform.scale(
            scale: scale,
            alignment: _growAlign,
            child: iconBox,
          ),
        ),
      );

      slot = Tooltip(
        message: item.tooltip ?? item.label,
        triggerMode: TooltipTriggerMode.longPress,
        child: Semantics(
          button: true,
          label: item.label,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: item.onTap,
            child: MouseRegion(cursor: SystemMouseCursors.click, child: slot),
          ),
        ),
      );

      if (i != widget.items.length - 1) {
        slot = Padding(padding: EdgeInsetsDirectional.only(end: widget.itemGap), child: slot);
      }
      return slot;
    });
  }
}
