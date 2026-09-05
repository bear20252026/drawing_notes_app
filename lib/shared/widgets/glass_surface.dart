import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
// RenderProxyBox（尺寸测量层）在 rendering 库，material 不导出。
import 'package:flutter/rendering.dart';

import 'package:drawing_notes_app/shared/widgets/liquid_glass_rim.dart';
import 'package:drawing_notes_app/shared/widgets/liquid_glass_shader.dart';

/// 面向导航与工具层的局部玻璃表面。
///
/// 本组件始终用 shape 一致的裁剪限制 BackdropFilter 的影响区域，避免全屏模糊。
/// 当平台要求简化动效时自动退化为半透明表面；画布、长列表和每张内容
/// 卡片不应无差别使用该组件，以避免阅读对比下降和滚动负担增加。
///
/// 液态玻璃分档（DESIGN_SYSTEM.md §5）：
/// - [LiquidGlassLevel.l1]：配方视觉——基底 62% + blur 12 + saturate 1.4 + 1px 亮边；
/// - [LiquidGlassLevel.l2]（默认）：+ 超椭圆 shape（曲率连续）；
/// - [LiquidGlassLevel.l3]：+ 着色器边缘罩（折射环 + RGB 色散 + 镜面高光，
///   经 [LiquidGlassGate] 性能闸门，不通过自动回落 L2）+ G3 backdrop
///   真折射位移（`ImageFilter.shader`，仅 Impeller，不支持回落 G1 管线）。
///
/// 平台诚实边界（2026-09-05 更正，见 docs/LIQUID_GLASS_TECHNICAL_PLAN）：
/// 旧注「BackdropFilter 不支持自定义片元采样，真位移/真饱和不可做」已过时——
/// Flutter 3.47 提供 `ImageFilter.compose`（本类已用于 blur+saturate）与
/// `ImageFilter.shader`（G3 真位移已落地：`shaders/liquid_glass_backdrop.frag`，
/// `isShaderFilterSupported` 兜底回落）。禁止玻璃叠玻璃（总纲红线）。
class GlassSurface extends StatefulWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius = const BorderRadius.all(Radius.circular(18)),
    this.sigma = LiquidGlassRecipe.kDefaultSigma,
    this.enabled = true,
    this.color,
    this.level = LiquidGlassLevel.l3,
    this.rimIntensity = 1.0,
    this.saturation = LiquidGlassRecipe.kDefaultSaturation,
    this.surfaceOpacity = LiquidGlassRecipe.kRegularOpacity,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadius borderRadius;
  final double sigma;
  final bool enabled;
  final Color? color;

  /// 液态玻璃档位（默认 L3；受 [LiquidGlassGate] 约束，失败自动回落 L2 视觉）。
  ///
  /// 2026-09-05：默认档由 L2 提升为 L3，因为此前全仓库无一处请求 L3，
  /// 折射/色散/镜面高光从未渲染过（见 docs/LIQUID_GLASS_TECHNICAL_PLAN）。
  final LiquidGlassLevel level;

  /// L3 边缘罩强度（0~1；≤0 关闭罩层）。
  final double rimIntensity;

  /// backdrop 饱和度倍率（1.0 = 不处理）。
  ///
  /// 三来源取值：Apple HIG 1.2–1.5×；`liquid-glass-react` 默认 140%；
  /// `prototype/PICKER.md:39` 实测 `saturate(1.4)`。默认取 1.4（PICKER 实测值，
  /// 与 HIG 区间中位一致）。由 `ImageFilter.compose` + `ColorFilter.matrix`
  /// 实现，非 Impeller 或构造失败时静默退化为纯模糊。
  final double saturation;

  /// 玻璃基底不透明度（0~1），默认 0.62。
  ///
  /// Apple HIG 两个变体：regular 0.6–0.8，clear 0.3–0.5。
  /// 默认取 0.62（regular 下限偏通透）——此前 0.80 让基底几乎不透明，
  /// 背后的内容透不出来，观感退化成「灰白板」而不是玻璃。
  /// 可读性由 blur + saturate + 语义色文字共同保证，不靠堆底色不透明度。
  ///
  /// 需要极致通透（浮在媒体/画布之上）可传 0.30–0.50（clear 变体），
  /// 但必须自行验证前景文字对比，参考实现在此情形会给文字加
  /// `0 2px 12px rgba(0,0,0,0.4)` 阴影兜底。
  final double surfaceOpacity;

  /// G1 滤镜缓存键 = (sigma, saturation)。条目数受限于实际用到的离散取值。
  static final Map<String, ui.ImageFilter> _filterCache =
      <String, ui.ImageFilter>{};

  /// 空测试注入用：清空缓存（仅供测试，勿在业务调用）。
  @visibleForTesting
  static void resetFilterCacheForTest() => _filterCache.clear();

  static ui.ImageFilter _g1Filter(double sigma, double saturation) {
    final key = '${sigma.toStringAsFixed(2)}|${saturation.toStringAsFixed(2)}';
    return _filterCache.putIfAbsent(
      key,
      () => _buildG1Filter(sigma, saturation),
    );
  }

  static ui.ImageFilter _buildG1Filter(double sigma, double saturation) {
    final blur = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma);
    if (saturation <= 1.0001) return blur;
    try {
      // result = outer(inner(source)) → 先模糊再饱和，与 CSS
      // `backdrop-filter: blur(Npx) saturate(K%)` 从左到右的应用顺序一致。
      return ui.ImageFilter.compose(
        outer: ui.ColorFilter.matrix(liquidGlassSaturationMatrix(saturation)),
        inner: blur,
      );
    } catch (_) {
      // 后端不支持合成滤镜（如非 Impeller）时静默退化为纯模糊。
      return blur;
    }
  }

  @override
  State<GlassSurface> createState() => _GlassSurfaceState();
}

class _GlassSurfaceState extends State<GlassSurface> {
  /// 首帧布局后测得的实际渲染尺寸（G3 滤镜需真实尺寸采样 backdrop）。
  ///
  /// 首帧为 null 时用 G1 管线（blur+saturate），次帧起切 G3——切换差异
  /// 细微（同为模糊背景），弹窗进场动画期间不可感。
  Size? _measured;

  void _onMeasured(Size size) {
    if (_measured == size) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _measured != size) {
        setState(() => _measured = size);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final reduceEffects = MediaQuery.disableAnimationsOf(context);
    // L1 配方底色：默认 80%（DESIGN.md:396-398），可由 [surfaceOpacity]
    // 降到 Apple HIG 的 clear 变体区间（0.3–0.5）换取通透观感。
    final surfaceColor =
        widget.color ?? scheme.surface.withValues(alpha: widget.surfaceOpacity);

    // L1 亮边：顶边镜面高光 + 其余边 outlineVariant（1px 纯色环——
    // 总纲允许的唯一描边例外，且此处为纯色非渐变）。
    final topColor = isDark
        ? const Color(0xFFFFFFFF).withValues(alpha: 0.22)
        : const Color(0xFFFFFFFF).withValues(alpha: 0.65);
    final sideColor = scheme.outlineVariant.withValues(
      alpha: isDark ? 0.62 : 0.72,
    );
    const shadows = [
      BoxShadow(color: Color(0x14000000), blurRadius: 20, offset: Offset(0, 8)),
    ];

    final resolved = LiquidGlassGate.resolve(context, widget.level);
    final useSuperellipse = resolved != LiquidGlassLevel.l1 && !reduceEffects;

    final padded = widget.padding == null
        ? widget.child
        : Padding(padding: widget.padding!, child: widget.child);

    // 主体装饰（L2 超椭圆 / L1 圆角矩形，共用同一 borderRadius 输入）。
    final borderRadius = widget.borderRadius;
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
      foregroundPainter: _TopEdgePainter(color: topColor, radius: borderRadius),
      child: content,
    );

    // L3 边缘罩（闸门已裁决；罩层不拦截手势）。
    if (resolved == LiquidGlassLevel.l3 && widget.rimIntensity > 0) {
      content = Stack(
        fit: StackFit.passthrough,
        children: [
          content,
          Positioned.fill(
            child: IgnorePointer(
              child: LiquidGlassRim(
                radius: borderRadius.topLeft.x,
                intensity: widget.rimIntensity,
                animated: !reduceEffects,
              ),
            ),
          ),
        ],
      );
    }

    // 实际渲染尺寸测量（G3 滤镜需要真实尺寸；零开销：RenderProxyBox 一层）。
    content = _MeasureSize(onSize: _onMeasured, child: content);

    // Shape 一致的内外双裁剪（内层约束罩层/高光，外层约束模糊 bleed）。
    // ShapeBorderClipper 构造为具名 shape 参数（无位置参数）。
    Widget clip(Widget w) => useSuperellipse
        ? ClipPath(
            clipper: ShapeBorderClipper(shape: shapeBorder),
            child: w,
          )
        : ClipRRect(borderRadius: borderRadius, child: w);

    if (!widget.enabled || reduceEffects) return clip(content);
    return clip(
      BackdropFilter(
        filter: _backdropFilterFor(
          resolved: resolved,
          reduceEffects: reduceEffects,
        ),
        child: clip(content),
      ),
    );
  }

  /// backdrop 滤镜管线（G3 → G1 回落，单一事实来源）。
  ///
  /// - **G1**（默认）：`saturate(blur(source))`——blur 与 saturate 合成带
  ///   轻量缓存（key = sigma|saturation，缓存与构建见 [GlassSurface._g1Filter]）；
  /// - **G3**（L3 + Impeller + 着色器就绪 + 已测得实际尺寸）：
  ///   `saturate(blur(displace(source)))`——`shaders/liquid_glass_backdrop.frag`
  ///   对 backdrop 做真折射位移 + RGB 色散，再经 blur 柔化、saturate 提饱和。
  ///   位移滤镜依赖实际尺寸，每次 build 新建 FragmentShader（program 共享，
  ///   rebuild 频率低：L3 罩微光动画由独立 CustomPaint 重绘，不经本 build）。
  ui.ImageFilter _backdropFilterFor({
    required LiquidGlassLevel resolved,
    required bool reduceEffects,
  }) {
    final g1 = GlassSurface._g1Filter(widget.sigma, widget.saturation);
    if (resolved != LiquidGlassLevel.l3) return g1;
    final size = _measured;
    if (size == null || size.isEmpty) return g1;
    if (!ui.ImageFilter.isShaderFilterSupported) return g1;
    if (!LiquidGlassShader.isBackdropReady) return g1;
    try {
      final displacement = LiquidGlassShader.bindBackdrop(
        size: size,
        radius: widget.borderRadius.topLeft.x,
      );
      if (displacement == null) return g1;
      return ui.ImageFilter.compose(
        outer: ui.ColorFilter.matrix(
          liquidGlassSaturationMatrix(widget.saturation),
        ),
        inner: ui.ImageFilter.compose(
          outer: ui.ImageFilter.blur(
            sigmaX: widget.sigma,
            sigmaY: widget.sigma,
          ),
          inner: ui.ImageFilter.shader(displacement),
        ),
      );
    } catch (_) {
      // 后端不支持 shader 滤镜（检测误报等边界）时静默回落 G1。
      return g1;
    }
  }
}

/// 实际渲染尺寸测量（RenderProxyBox 零开销层；仅尺寸变化时经 postFrame
/// 通知，避免 layout 期间 setState 与每帧重标 dirty）。
class _MeasureSize extends SingleChildRenderObjectWidget {
  const _MeasureSize({required this.onSize, super.child});

  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasureSize(onSize);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderMeasureSize renderObject,
  ) {
    renderObject.onSize = onSize;
  }
}

class _RenderMeasureSize extends RenderProxyBox {
  _RenderMeasureSize(this.onSize);

  ValueChanged<Size> onSize;
  Size? _last;

  @override
  void performLayout() {
    super.performLayout();
    final child = this.child;
    if (child == null) return;
    final size = child.size;
    if (_last != size) {
      _last = size;
      // layout 期间禁止 setState——经 postFrame 在帧尾通知。
      scheduleMicrotask(() => onSize(size));
    }
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
