import 'package:flutter/widgets.dart';

import 'package:drawing_notes_app/shared/widgets/liquid_glass_shader.dart';

/// 液态玻璃边缘折射罩（L3 前台部分）。
///
/// 着色器只画边缘环 + 色散 + 镜面高光（面板 bounds 内叠加，不拦截手势——
/// `IgnorePointer` 由调用方保证，本组件本身无手势）。微光闪烁由内部
/// [AnimationController] 驱动（4s 循环，振幅 ±15%）；减弱动效时传
/// [animated] = false，时间恒 0（STANDARDS.md:176——保留颜色过渡，
/// 去掉位移/闪烁类动效）。
class LiquidGlassRim extends StatefulWidget {
  const LiquidGlassRim({
    super.key,
    required this.radius,
    this.intensity = 1.0,
    this.tint = const Color(0xFFFFFFFF),
    this.aberration = 2.0,
    this.animated = true,
  });

  /// 圆角半径（与面板 shape 一致，逻辑像素）。
  final double radius;

  /// 整体强度（0~1）。
  final double intensity;

  /// 高光染色。
  final Color tint;

  /// 色散分离量（像素，配方默认档 2）。
  final double aberration;

  /// 是否播放微光闪烁；false 时时间恒 0。
  final bool animated;

  @override
  State<LiquidGlassRim> createState() => _LiquidGlassRimState();
}

class _LiquidGlassRimState extends State<LiquidGlassRim>
    with SingleTickerProviderStateMixin {
  late final AnimationController _time = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  );

  /// 微光闪烁的 60FPS fragment shader 动画只应在**确实需要**时开启。
  ///
  /// [animated] 为 false（GlassSurface 默认静态）时**绝不启动**——否则一个
  /// `repeat()` 的 AnimationController 即便不挂 AnimatedBuilder 也会持续
  /// 逐帧向引擎申请帧（ticker 常驻调度），玻璃表面遍布全 App + IndexedStack
  /// 常驻，会变成几十个永续 60FPS 着色循环 → CPU/GPU 双打满、内存堆积。
  @override
  void initState() {
    super.initState();
    if (widget.animated) _time.repeat();
  }

  @override
  void didUpdateWidget(covariant LiquidGlassRim oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animated && !_time.isAnimating) {
      _time.repeat();
    } else if (!widget.animated && _time.isAnimating) {
      _time.stop();
    }
  }

  @override
  void dispose() {
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!LiquidGlassShader.isReady) return const SizedBox.shrink();
    if (!widget.animated) {
      return CustomPaint(
        painter: _RimPainter(
          radius: widget.radius,
          intensity: widget.intensity,
          tint: widget.tint,
          aberration: widget.aberration,
          timeSeconds: 0,
        ),
      );
    }
    return AnimatedBuilder(
      animation: _time,
      builder: (context, _) => CustomPaint(
        painter: _RimPainter(
          radius: widget.radius,
          intensity: widget.intensity,
          tint: widget.tint,
          aberration: widget.aberration,
          timeSeconds: _time.value * 4.0,
        ),
      ),
    );
  }
}

class _RimPainter extends CustomPainter {
  _RimPainter({
    required this.radius,
    required this.intensity,
    required this.tint,
    required this.aberration,
    required this.timeSeconds,
  });

  final double radius;
  final double intensity;
  final Color tint;
  final double aberration;
  final double timeSeconds;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final shader = LiquidGlassShader.bind(
      size: size,
      radius: radius,
      timeSeconds: timeSeconds,
      intensity: intensity,
      tint: tint,
      aberration: aberration,
    );
    if (shader == null) return;
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
    shader.dispose();
  }

  @override
  bool shouldRepaint(covariant _RimPainter old) =>
      old.timeSeconds != timeSeconds ||
      old.radius != radius ||
      old.intensity != intensity ||
      old.tint != tint ||
      old.aberration != aberration;
}
