import 'dart:ui' show Offset;

import 'drawing_service.dart';

/// Stroke operation boundary.
///
/// The service owns the future stroke-related orchestration boundary.
/// Migration is intentionally incremental: the current input session remains
/// the source of truth while new stroke workflows can move here safely.
final class StrokeService implements DrawingService {
  StrokeService({this.onStart, this.onUpdate, this.onFinish});

  final void Function(Offset point, {double pressure})? onStart;
  final void Function(Offset point, {double pressure})? onUpdate;
  final Future<void> Function()? onFinish;

  bool _disposed = false;

  bool get isDisposed => _disposed;

  /// Entry point reserved for stroke lifecycle migration.
  ///
  /// The service forwards to the existing input session during migration. The
  /// session remains the source of truth while callers move to this boundary.
  void prepareStroke(Offset point) {
    if (_disposed) return;
  }

  void startStroke(Offset point, {double pressure = 1.0}) {
    if (_disposed) return;
    prepareStroke(point);
    onStart?.call(point, pressure: pressure);
  }

  void updateStroke(Offset point, {double pressure = 1.0}) {
    if (_disposed) return;
    onUpdate?.call(point, pressure: pressure);
  }

  Future<void> finishStroke() async {
    if (_disposed) return;
    await onFinish?.call();
  }

  @override
  void dispose() {
    _disposed = true;
  }
}
