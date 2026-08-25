// Inspira UI——Morphing Tabs（借鉴 MagicUI morphing tabs）。
//
// 用途：编辑器模式切换（画笔/橡皮/文字/形状）。
// - 选中胶囊在标签间滑动 + 宽度自适应"变形"（AnimatedContainer）
// - 图标缩放过渡 + 选中项标签展开
// - 可自定义颜色、形状（borderRadius/selectedBorderRadius 实现圆形↔方形↔圆角形变）、时长与曲线
// - 无障碍：每项 Semantics(button+selected+label)，≥48dp 触摸目标
import 'package:flutter/material.dart';

/// 单个 tab 定义。
class MorphTab<T> {
  const MorphTab({
    required this.value,
    required this.icon,
    required this.label,
    this.tooltip,
  });

  final T value;
  final IconData icon;
  final String label;
  final String? tooltip;
}

/// 横向 morphing 标签栏。
///
/// [onChanged] 在用户点击某项时回调；受控组件由 [selected] 决定高亮。
class MorphingTabs<T> extends StatelessWidget {
  const MorphingTabs({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onChanged,
    this.height = 48,
    this.animate = true,
    this.duration = const Duration(milliseconds: 280),
    this.curve = Curves.easeOutCubic,
    this.selectedColor,
    this.unselectedIconColor,
    this.borderRadius,
    this.selectedBorderRadius,
  });

  final List<MorphTab<T>> tabs;
  final T selected;
  final ValueChanged<T> onChanged;

  /// false 时跳过动画（尊重系统减少动态效果）。
  final bool animate;
  final double height;

  /// 过渡时长与曲线。
  final Duration duration;
  final Curve curve;

  /// 自定义选中胶囊底色（默认取主题 primaryContainer）。
  final Color? selectedColor;

  /// 自定义未选中图标色（默认取主题 onSurfaceVariant）。
  final Color? unselectedIconColor;

  /// 未选中项形状（圆角）；默认 [height]/2 胶囊。
  final BorderRadius? borderRadius;

  /// 选中项形状（圆角）；默认与 [borderRadius] 相同。
  /// 与 [borderRadius] 不同时，切换瞬间产生 圆形↔方形↔圆角 的形状变形过渡。
  final BorderRadius? selectedBorderRadius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final effectiveRadius = borderRadius ?? BorderRadius.circular(height / 2);
    return Semantics(
      // 读屏语义：一组单选按钮。
      container: true,
      child: FocusTraversalGroup(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final tab in tabs)
              _MorphItem(
                key: ValueKey('morph-${tab.value}'),
                tab: tab,
                selected: tab.value == selected,
                animate: animate,
                duration: duration,
                curve: curve,
                height: height,
                selectedColor: selectedColor,
                unselectedIconColor: unselectedIconColor,
                borderRadius: effectiveRadius,
                selectedBorderRadius:
                    selectedBorderRadius ?? effectiveRadius,
                scheme: scheme,
                onTap: () => onChanged(tab.value),
              ),
          ],
        ),
      ),
    );
  }
}

class _MorphItem extends StatelessWidget {
  const _MorphItem({
    super.key,
    required this.tab,
    required this.selected,
    required this.animate,
    required this.duration,
    required this.curve,
    required this.height,
    required this.selectedColor,
    required this.unselectedIconColor,
    required this.borderRadius,
    required this.selectedBorderRadius,
    required this.scheme,
    required this.onTap,
  });

  final MorphTab<dynamic> tab;
  final bool selected;
  final bool animate;
  final Duration duration;
  final Curve curve;
  final double height;
  final Color? selectedColor;
  final Color? unselectedIconColor;

  /// 未选中 / 选中的形状；二者不同时切换产生形变过渡。
  final BorderRadius borderRadius;
  final BorderRadius selectedBorderRadius;
  final ColorScheme scheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Widget content = AnimatedContainer(
      duration: animate ? duration : Duration.zero,
      curve: curve,
      // 选中时宽度"变形"以容纳标签文字——morph 的核心观感。
      height: height,
      padding: EdgeInsets.symmetric(horizontal: selected ? 14 : 12),
      decoration: BoxDecoration(
        color: selected
            ? (selectedColor ?? scheme.primaryContainer)
            : Colors.transparent,
        // 圆形↔方形↔圆角：选中态可配置为不同圆角，AnimatedContainer 自动补间。
        borderRadius: selected ? selectedBorderRadius : borderRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedScale(
            scale: selected ? 1.15 : 1.0,
            duration: animate ? duration : Duration.zero,
            curve: curve,
            child: Icon(
              tab.icon,
              size: 22,
              color: selected
                  ? scheme.onPrimaryContainer
                  : (unselectedIconColor ?? scheme.onSurfaceVariant),
            ),
          ),
          // 选中项标签展开（宽度动画由 ClipRect+Align 收敛布局跳动）。
          ClipRect(
            child: Align(
              alignment: Alignment.centerLeft,
              widthFactor: selected ? 1 : 0,
              child: Opacity(
                opacity: selected ? 1 : 0,
                child: Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text(
                    tab.label,
                    style: TextStyle(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    return Semantics(
      label: tab.tooltip ?? tab.label,
      button: true,
      selected: selected,
      child: Tooltip(
        message: tab.tooltip ?? tab.label,
        child: InkWell(
          borderRadius: BorderRadius.circular(height / 2),
          onTap: onTap,
          child: Container(
            // 无障碍：触摸目标 ≥48dp。
            constraints: BoxConstraints(minWidth: 48, minHeight: height),
            alignment: Alignment.center,
            child: content,
          ),
        ),
      ),
    );
  }
}
