import 'dart:async';

import 'package:drawing_notes_app/features/drawing/domain/stroke.dart';

// ---------------------------------------------------------------------------
// 临时标记域（part 真解耦 2026-08-15）：原 drawing_controller_temporary.dart
// （part of drawing_controller）转独立文件——TemporaryInk/TemporaryLaserInk
// 为纯数据 + 纯计算类（仅依赖公共常量与 Stroke，无 controller 实例私有
// 依赖），转独立编译单元实现真解耦（官方不推荐 part：库即隐私单元）。
// 常量随迁避免循环依赖（drawing_controller import 本文件单向依赖）。
// 本文件同时承载其运行时会话 [TemporaryInkSession]，二者同属"临时未持久化
// 墨迹"职责，聚合为一个编译单元。
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

/// 临时高亮与激光尾迹的运行时会话。
///
/// 该协作者只管理未持久化墨迹的生命周期：创建、按时间投影显示快照、
/// 16ms 刷新节拍、过期清理与计时器释放。它不触碰文档、历史栈或 UI 状态，
/// 控制器仅通过 [onFrameTick] 请求画布重绘。
class TemporaryInkSession {
  TemporaryInkSession({required this._onFrameTick, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final void Function() _onFrameTick;
  final DateTime Function() _clock;
  final List<TemporaryInk> _markers = <TemporaryInk>[];
  final List<TemporaryLaserInk> _lasers = <TemporaryLaserInk>[];

  Timer? _ticker;
  bool _disposed = false;
  bool temporaryMarkerEnabled = false;

  /// 尚在淡出期的临时高亮笔，供画布在矢量图层之上直接绘制。
  List<({Stroke stroke, double opacity})> get markerStrokes {
    final now = _clock();
    _prune(now);
    return _markers
        .map((entry) => (stroke: entry.stroke, opacity: entry.opacityAt(now)))
        .where((entry) => entry.opacity > 0)
        .toList(growable: false);
  }

  /// 激光尾迹的可见片段。首点索引随时间前移，实现从起笔端逐段消退。
  List<({Stroke stroke, int firstPointIndex, double opacity})>
  get laserStrokes {
    final now = _clock();
    _prune(now);
    return _lasers
        .map(
          (entry) => (
            stroke: entry.stroke,
            firstPointIndex: entry.firstVisiblePointAt(now),
            opacity: entry.opacityAt(now),
          ),
        )
        .where((entry) => entry.opacity > 0)
        .toList(growable: false);
  }

  void addMarker(Stroke stroke) {
    if (_disposed) return;
    _markers.add(TemporaryInk(stroke, _clock()));
    _ensureTicker();
  }

  void addLaser(Stroke stroke, DateTime startedAt) {
    if (_disposed) return;
    _lasers.add(TemporaryLaserInk(stroke, startedAt));
    _ensureTicker();
  }

  void _ensureTicker() {
    _ticker ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (_disposed) return;
      final now = _clock();
      _prune(now);
      if (_markers.isEmpty && _lasers.isEmpty) {
        _ticker?.cancel();
        _ticker = null;
      }
      _onFrameTick();
    });
  }

  void _prune(DateTime now) {
    _markers.removeWhere(
      (entry) => now.difference(entry.startedAt) >= temporaryMarkerLifetime,
    );
    _lasers.removeWhere((entry) => entry.isExpiredAt(now));
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _ticker?.cancel();
    _ticker = null;
    _markers.clear();
    _lasers.clear();
  }
}
