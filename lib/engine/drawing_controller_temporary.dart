part of 'drawing_controller.dart';

/// 一条尚未持久化的临时荧光笔墨迹。
class _TemporaryInk {
  const _TemporaryInk(this.stroke, this.startedAt);

  final Stroke stroke;
  final DateTime startedAt;

  double opacityAt(DateTime now) {
    final elapsed = now.difference(startedAt).inMicroseconds;
    final total = DrawingController.temporaryMarkerLifetime.inMicroseconds;
    final progress = (elapsed / total).clamp(0.0, 1.0);
    // ease-out：起初稳定便于指示，末段柔和消失，避免突兀闪断。
    return (1 - progress) * (1 - progress);
  }
}

/// 一条仅在运行时存在的激光尾迹。
class _TemporaryLaserInk {
  const _TemporaryLaserInk(this.stroke, this.startedAt);

  final Stroke stroke;
  final DateTime startedAt;

  Duration get _sweepEnd =>
      DrawingController.laserHoldDuration +
      DrawingController.laserSweepDuration;
  Duration get _lifetime =>
      _sweepEnd + DrawingController.laserFinalFadeDuration;

  int firstVisiblePointAt(DateTime now) {
    final count = stroke.points.length;
    if (count <= 1) return 0;
    final elapsed = now.difference(startedAt);
    if (elapsed <= DrawingController.laserHoldDuration) return 0;
    final sweepElapsed = elapsed - DrawingController.laserHoldDuration;
    final progress =
        (sweepElapsed.inMicroseconds /
                DrawingController.laserSweepDuration.inMicroseconds)
            .clamp(0.0, 1.0);
    return ((count - 1) * progress).floor().clamp(0, count - 1);
  }

  double opacityAt(DateTime now) {
    final elapsed = now.difference(startedAt);
    if (elapsed <= _sweepEnd) return 1;
    final fadeProgress =
        ((elapsed - _sweepEnd).inMicroseconds /
                DrawingController.laserFinalFadeDuration.inMicroseconds)
            .clamp(0.0, 1.0);
    final remaining = 1 - fadeProgress;
    // 末段采用平方 ease-out，保留视觉连续性而不是闪断。
    return remaining * remaining;
  }

  bool isExpiredAt(DateTime now) => now.difference(startedAt) >= _lifetime;
}
