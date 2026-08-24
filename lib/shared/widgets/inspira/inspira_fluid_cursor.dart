// Inspira UI · Fluid Cursor —— 绘图时流体跟随光标（粘性拖尾粒子）。
//
// 灵感来自 Inspira UI 的 Fluid Cursor（MIT），纯 Flutter 重写：
// - 指针移动时在轨迹上生成发光粒子，粒子带随机初速、阻尼衰减与生命周期；
// - Ticker 驱动物理更新，RepaintBoundary + 前景层隔离重绘，
//   不侵入现有笔画采集管线（不影响 60fps 采点）；
// - 尊重系统「减弱动态效果」：完全禁用粒子；
// - 粒子上限保护，超限时丢弃新粒子而非卡顿。
//
// 用法（包裹需要流体光标的区域）：
//   InspiraFluidCursor(
//     color: Colors.cyanAccent,
//     child: CanvasArea(),
//   )

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// 单个拖尾粒子（物理模拟对象，字段可变）。
// ignore: must_be_immutable
class _Particle {
  _Particle({
    required this.position,
    required this.velocity,
    required this.life,
    required this.maxLife,
    required this.radius,
  });

  Offset position;
  Offset velocity;
  double life; // 剩余寿命（秒）
  final double maxLife;
  final double radius;
}

class InspiraFluidCursor extends StatefulWidget {
  const InspiraFluidCursor({
    super.key,
    required this.child,
    this.color = const Color(0xFF7DE2FF),
    this.particleLife = 0.55,
    this.maxParticles = 260,
    this.minRadius = 2,
    this.maxRadius = 6.5,
    this.spawnPerEvent = 2,
  });

  final Widget child;

  /// 粒子主色（自动生成同色系透明渐变）。
  final Color color;

  /// 单个粒子寿命（秒）。
  final double particleLife;

  /// 粒子上限。
  final int maxParticles;

  final double minRadius;
  final double maxRadius;

  /// 每次指针移动事件生成的粒子数。
  final int spawnPerEvent;

  @override
  InspiraFluidCursorState createState() => InspiraFluidCursorState();
}

/// 公开 State 以便测试读取 [debugParticleCount]。
class InspiraFluidCursorState extends State<InspiraFluidCursor>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final math.Random _random = math.Random();
  final List<_Particle> _particles = <_Particle>[];
  Duration _lastTick = Duration.zero;

  /// 当前存活粒子数（测试用）。
  int get debugParticleCount => _particles.length;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  bool get _effectsAllowed => !MediaQuery.disableAnimationsOf(context);

  void _ensureTicker() {
    if (_particles.isEmpty) {
      if (_ticker.isActive) {
        _ticker.stop();
      }
    } else if (!_ticker.isActive && _effectsAllowed) {
      _lastTick = Duration.zero;
      _ticker.start();
    }
  }

  void _onTick(Duration elapsed) {
    if (_lastTick == Duration.zero) {
      _lastTick = elapsed;
      return;
    }
    final dt = ((elapsed - _lastTick).inMicroseconds / 1e6)
        .clamp(0.0, 0.05); // 卡帧时物理步长封顶，防穿透
    _lastTick = elapsed;

    for (final p in _particles) {
      p.position += p.velocity * dt;
      p.velocity = p.velocity * 0.90; // 粘性阻尼
      p.life -= dt;
    }
    _particles.removeWhere((p) => p.life <= 0);

    if (_particles.isEmpty) {
      _ticker.stop();
    }
    setState(() {});
  }

  void _spawnAt(Offset localPos) {
    for (var i = 0; i < widget.spawnPerEvent; i++) {
      if (_particles.length >= widget.maxParticles) return;
      final angle = _random.nextDouble() * math.pi * 2;
      final speed = 20 + _random.nextDouble() * 70;
      _particles.add(_Particle(
        position: localPos +
            Offset(
              (_random.nextDouble() - 0.5) * 8,
              (_random.nextDouble() - 0.5) * 8,
            ),
        velocity: Offset(math.cos(angle), math.sin(angle)) * speed,
        life: widget.particleLife,
        maxLife: widget.particleLife,
        radius: widget.minRadius +
            _random.nextDouble() *
                (widget.maxRadius - widget.minRadius),
      ));
    }
    _ensureTicker();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allowed = !MediaQuery.disableAnimationsOf(context);
    _ensureTicker();

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerHover: allowed
          ? (event) {
              final box = context.findRenderObject()! as RenderBox;
              _spawnAt(box.globalToLocal(event.position));
            }
          : null,
      onPointerDown: allowed
          ? (event) {
              final box = context.findRenderObject()! as RenderBox;
              _spawnAt(box.globalToLocal(event.position));
            }
          : null,
      onPointerMove: allowed
          ? (event) {
              final box = context.findRenderObject()! as RenderBox;
              _spawnAt(box.globalToLocal(event.position));
            }
          : null,
      child: RepaintBoundary(
        child: Stack(
          fit: StackFit.expand,
          children: [
            widget.child,
            // 前景粒子层：IgnorePointer 保证不干扰画布手势采集。
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _FluidTrailPainter(
                    particles: _particles,
                    baseColor: widget.color,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FluidTrailPainter extends CustomPainter {
  _FluidTrailPainter({required this.particles, required this.baseColor});

  final List<_Particle> particles;
  final Color baseColor;

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final t = (p.life / p.maxLife).clamp(0.0, 1.0);
      final radius = p.radius * (0.35 + 0.65 * t);
      final paint = Paint()
        ..color = baseColor.withValues(alpha: 0.55 * t)
        ..maskFilter =
            MaskFilter.blur(BlurStyle.solid, radius * 0.9);
      canvas.drawCircle(p.position, radius, paint);
      // 内芯更亮，形成流体质感。
      canvas.drawCircle(
        p.position,
        radius * 0.45,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.5 * t),
      );
    }
  }

  @override
  bool shouldRepaint(_FluidTrailPainter old) => true;
}
