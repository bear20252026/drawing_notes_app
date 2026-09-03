import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:drawing_notes_app/shared/widgets/liquid_glass_rim.dart';
import 'package:drawing_notes_app/shared/widgets/liquid_glass_shader.dart';

/// 面向导航与工具层的局部玻璃表面。
///
/// 本组件始终用 shape 一致的裁剪限制 BackdropFilter 的影响区域，避免全屏模糊。
/// 当平台要求简化动效时自动退化为半透明表面；画布、长列表和每张内容
/// 卡片不应无差别使用该组件，以避免阅读对比下降和滚动负担增加。
///
/// 液态玻璃分档（DESIGN_SYSTEM.md §5）：
/// - [LiquidGlassLevel.l1]：配方视觉——80% 底色 + blur 12 + 1px 亮边；
/// - [LiquidGlassLevel.l2]（默认）：+ 超椭圆 shape（曲率连续）；
/// - [LiquidGlassLevel.l3]：+ 着色器边缘罩（折射环 + RGB 色散 + 镜面高光，
///   经 [LiquidGlassGate] 性能闸门，不通过自动回落 L2）。
///
/// 平台诚实边界：Flutter 的 BackdropFilter 不支持自定义片元采样，
/// backdrop 真位移不可做——位移感由 blur 12 近似，saturate(180%) 的
/// 饱和提升由 L3 罩的高光染色近似；两者都不伪造不存在的采样。
/// 禁止玻璃叠玻璃（legibility collapses——总纲红线）。
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius = const BorderRadius.all(Radius.circular(18)),
    this.sigma = 12,
    this.enabled = true,
    this.color,
    this.level = LiquidGlassLevel.l2,
    this.rimIntensity = 1.0,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadius borderRadius;
  final double sigma;
  final bool enabled;
  final Color? color;

  /// 液态玻璃档位（默认 L2；L3 受闸门约束，失败自动回落 L2 视觉）。
  final LiquidGlassLevel level;

  /// L3 边缘罩强度（0~1；≤0 关闭罩层）。
  final double rimIntensity;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final reduceEffects = MediaQuery.disableAnimationsOf(context);
    // L1 配方底色：80%（DESIGN.md:396-398；此前浅色 0.76 → 0.80 对齐）。
    final surfaceColor =
        color ?? scheme.surface.withValues(alpha: isDark ? 0.80 : 0.80);

    // L1 亮边：顶边镜面高光 + 其余边 outlineVariant（1px 纯色环——
    // 总纲允许的唯一描边例外，且此处为纯色非渐变）。
    final topColor = isDark
        ? const Color(0xFFFFFFFF).withValues(alpha: 0.22)
        : const Color(0xFFFFFFFF).withValues(alpha: 0.65);
    final sideColor =
        scheme.outlineVariant.withValues(alpha: isDark ? 0.62 : 0.72);
    const shadows = [
      BoxShadow(
        color: Color(0x14000000),
        blurRadius: 20,
        offset: Offset(0, 8),
      ),
    ];

    final resolved = LiquidGlassGate.resolve(context, level);
    final useSuperellipse =
        resolved != LiquidGlassLevel.l1 && !reduceEffects;

    final padded =
        padding == null ? child : Padding(padding: padding!, child: child);

    // 主体装饰（L2 超椭圆 / L1 圆角矩形，共用同一 borderRadius 输入）。
    final ShapeBorder shapeBorder = useSuperellipse
        ? RoundedSuperellipseBorder(
            borderRadius: borderRadius,
            side: BorderSide(color: sideColor, width: 1),
          )
        : RoundedRectangleBorder(
            borderRadius: borderRadius,
            side: BorderSide(color: sideColor, width: 1),
          );
    Widget content = DecoratedBox(
      decoration: ShapeDecoration(
        color: surfaceColor,
        shape: shapeBorder,
        shadows: isDark
            ? const [
                BoxShadow(
                  color: Color(0x29000000),
                  blurRadius: 20,
                  offset: Offset(0, 8),
                ),
              ]
            : shadows,
      ),
      child: padded,
    );

    // 顶边 1px 高光环（纯色描边；超椭圆顶部弧线与 RRect 近似，1px 误差可忽略）。
    content = CustomPaint(
      foregroundPainter: _TopEdgePainter(
        color: topColor,
        radius: borderRadius,
      ),
      child: content,
    );

    // L3 边缘罩（闸门已裁决；罩层不拦截手势）。
    if (resolved == LiquidGlassLevel.l3 && rimIntensity > 0) {
      content = Stack(
        fit: StackFit.passthrough,
        children: [
          content,
          Positioned.fill(
            child: IgnorePointer(
              child: LiquidGlassRim(
                radius: borderRadius.topLeft.x,
                intensity: rimIntensity,
                animated: !reduceEffects,
              ),
            ),
          ),
        ],
      );
    }

    // Shape 一致的内外双裁剪（内层约束罩层/高光，外层约束模糊 bleed）。
    // ShapeBorderClipper 构造为具名 shape 参数（无位置参数）。
    Widget clip(Widget w) => useSuperellipse
        ? ClipPath(clipper: ShapeBorderClipper(shape: shapeBorder), child: w)
        : ClipRRect(borderRadius: borderRadius, child: w);

    if (!enabled || reduceEffects) return clip(content);
    return clip(
      BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: clip(content),
      ),
    );
  }
}

/// 顶边 1px 高光环（纯色描边，不引入装饰性渐变）。
class _TopEdgePainter extends CustomPainter {
  _TopEdgePainter({required this.color, required this.radius});

  final Color color;
  final BorderRadius radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rrect = RRect.fromRectAndCorners(
      Offset.zero & size,
      topLeft: radius.topLeft,
      topRight: radius.topRight,
    );
    // 只描上半弧：裁出顶部 2px 带，避免整圈复描盖掉侧边描边。
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, 2));
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TopEdgePainter old) =>
      old.color != color || old.radius != radius;
}
