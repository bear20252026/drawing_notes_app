import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

/// 面向导航与工具层的局部玻璃表面。
///
/// 本组件始终用圆角裁剪限制 BackdropFilter 的影响区域，避免全屏模糊。
/// 当平台要求简化动效时自动退化为半透明表面；画布、长列表和每张内容
/// 卡片不应无差别使用该组件，以避免阅读对比下降和滚动负担增加。
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.sigma = 10,
    this.enabled = true,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadius borderRadius;
  final double sigma;
  final bool enabled;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final reduceEffects = MediaQuery.disableAnimationsOf(context);
    final surfaceColor =
        color ?? scheme.surface.withValues(alpha: isDark ? 0.78 : 0.76);

    final Widget content = DecoratedBox(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: borderRadius,
        // DESIGN.md: UI chrome 无阴影
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: isDark ? 0.62 : 0.72),
        ),
      ),
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );

    return ClipRRect(
      borderRadius: borderRadius,
      child: enabled && !reduceEffects
          ? BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
              child: content,
            )
          : content,
    );
  }
}
