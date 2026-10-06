import 'dart:ui' show Rect;

import 'drawing_service.dart';

/// Layer operation boundary.
///
/// This service is intentionally host-agnostic. Existing LayerEditingSession
/// remains the implementation during migration; this boundary allows future
/// layer features (plugins, AI operations, batch editing) to avoid coupling to
/// DrawingController.
final class LayerService implements DrawingService {
  LayerService();

  bool _disposed = false;

  bool get isDisposed => _disposed;

  void Function({String? name})? _createLayer;
  void Function(int index)? _deleteLayer;
  void Function(int index)? _toggleVisibility;
  void Function(int index, double value)? _setOpacity;
  void Function(int index)? _moveUp;
  void Function(int index)? _moveDown;
  void Function(int index)? _mergeDown;
  Future<void> Function(String layerId, {Rect? region})? _invalidate;
  void Function(String layerId, int targetIndex)? _reorder;

  /// Connects the migration boundary to the existing LayerEditingSession.
  /// The session remains the implementation owner until the next migration step.
  void bindLegacyOperations({
    required void Function({String? name}) createLayer,
    required void Function(int index) deleteLayer,
    void Function(int index)? toggleVisibility,
    void Function(int index, double value)? setOpacity,
    void Function(int index)? moveUp,
    void Function(int index)? moveDown,
    void Function(int index)? mergeDown,
    Future<void> Function(String layerId, {Rect? region})? invalidate,
    void Function(String layerId, int targetIndex)? reorder,
  }) {
    _createLayer = createLayer;
    _deleteLayer = deleteLayer;
    _toggleVisibility = toggleVisibility;
    _setOpacity = setOpacity;
    _moveUp = moveUp;
    _moveDown = moveDown;
    _mergeDown = mergeDown;
    _invalidate = invalidate;
    _reorder = reorder;
  }

  /// Future migration entry point for layer invalidation-aware operations.
  Future<void> invalidate(String layerId, {Rect? region}) async {
    if (_disposed) return;
    final operation = _invalidate;
    if (operation == null) throw StateError('Layer invalidation is not bound');
    await operation(layerId, region: region);
  }

  /// Stable entry point for structural layer operations.
  ///
  /// Actual document mutation remains in LayerEditingSession until the next
  /// migration stage. Keeping these names here creates a single API surface for
  /// UI, plugins and future AI operations.
  void createLayer({String? name}) {
    if (_disposed) return;
    _createLayer?.call(name: name);
  }

  void deleteLayer(int index) {
    if (_disposed) return;
    _deleteLayer?.call(index);
  }

  void toggleVisibility(int index) {
    if (_disposed) return;
    _toggleVisibility?.call(index);
  }

  void setOpacity(int index, double value) {
    if (_disposed) return;
    _setOpacity?.call(index, value);
  }

  void moveLayerUp(int index) {
    if (_disposed) return;
    _moveUp?.call(index);
  }

  void moveLayerDown(int index) {
    if (_disposed) return;
    _moveDown?.call(index);
  }

  void mergeLayerDown(int index) {
    if (_disposed) return;
    _mergeDown?.call(index);
  }

  void reorderLayer(String layerId, int targetIndex) {
    if (_disposed) return;
    final operation = _reorder;
    if (operation == null) throw StateError('Layer reordering is not bound');
    operation(layerId, targetIndex);
  }

  void beginLayerTransaction() {
    if (_disposed) return;
  }

  @override
  void dispose() {
    _disposed = true;
  }
}
