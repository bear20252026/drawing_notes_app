import 'dart:async';

import 'package:drawing_notes_app/features/drawing/application/temporary_markers.dart';
import 'package:drawing_notes_app/features/drawing/domain/stroke.dart';

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
