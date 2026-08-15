import 'package:drawing_notes_app/features/drawing/domain/stroke.dart';

// ---------------------------------------------------------------------------
// 临时标记域（part 真解耦 2026-08-15）：原 drawing_controller_temporary.dart
// （part of drawing_controller）转独立文件——TemporaryInk/TemporaryLaserInk
// 为纯数据 + 纯计算类（仅依赖公共常量与 Stroke，无 controller 实例私有
// 依赖），转独立编译单元实现真解耦（官方不推荐 part：库即隐私单元）。
// 常量随迁避免循环依赖（drawing_controller import 本文件单向依赖）。
// ---------------------------------------------------------------------------

/// 临时荧光笔墨迹生命周期常量。
const Duration temporaryMarkerLifetime = Duration(seconds: 4);

/// 激光尾迹保持时长。
const Duration laserHoldDuration = Duration(milliseconds: 700);

/// 激光尾迹扫过时长。
const Duration laserSweepDuration = Duration(milliseconds: 1800);

/// 激光尾迹最终淡出时长。
const Duration laserFinalFadeDuration = Duration(milliseconds: 260);

/// 一条尚未持久化的临时荧光笔墨迹（纯数据 + 纯计算）。
class TemporaryInk {
  const TemporaryInk(this.stroke, this.startedAt);

  final Stroke stroke;
  final DateTime startedAt;

  double opacityAt(DateTime now) {
    final elapsed = now.difference(startedAt).inMicroseconds;
    final total = temporaryMarkerLifetime.inMicroseconds;
    final progress = (elapsed / total).clamp(0.0, 1.0);
    // ease-out：起初稳定便于指示，末段柔和消失，避免突兀闪断。
    return (1 - progress) * (1 - progress);
  }
}

/// 一条仅在运行时存在的激光尾迹（纯数据 + 纯计算）。
class TemporaryLaserInk {
  const TemporaryLaserInk(this.stroke, this.startedAt);

  final Stroke stroke;
  final DateTime startedAt;

  Duration get _sweepEnd => laserHoldDuration + laserSweepDuration;
  Duration get _lifetime => _sweepEnd + laserFinalFadeDuration;

  int firstVisiblePointAt(DateTime now) {
    final count = stroke.points.length;
    if (count <= 1) return 0;
    final elapsed = now.difference(startedAt);
    if (elapsed <= laserHoldDuration) return 0;
    final sweepElapsed = elapsed - laserHoldDuration;
    final progress =
        (sweepElapsed.inMicroseconds / laserSweepDuration.inMicroseconds)
            .clamp(0.0, 1.0);
    return ((count - 1) * progress).floor().clamp(0, count - 1);
  }

  double opacityAt(DateTime now) {
    final elapsed = now.difference(startedAt);
    if (elapsed <= _sweepEnd) return 1;
    final fadeProgress =
        ((elapsed - _sweepEnd).inMicroseconds / laserFinalFadeDuration.inMicroseconds)
            .clamp(0.0, 1.0);
    final remaining = 1 - fadeProgress;
    // 末段采用平方 ease-out，保留视觉连续性而不是闪断。
    return remaining * remaining;
  }

  bool isExpiredAt(DateTime now) => now.difference(startedAt) >= _lifetime;
}
