import 'dart:ui' show Color, Offset;

import 'package:drawing_notes_app/core/canvas_model/selection.dart';
import 'package:drawing_notes_app/features/drawing/application/drawing_selection_session.dart';

import 'drawing_service.dart';

/// Owns selection state and routes interaction and editing through one boundary.
/// Existing sessions retain their gesture settlement and notification rules.
final class SelectionService implements DrawingService {
  SelectionService({
    required StrokeSelectionInteractionHost interactionHost,
    required StrokeSelectionEditingHost editingHost,
    required this.onChanged,
    required this.onClearDocumentSelection,
  }) : _interaction = StrokeSelectionInteractionSession(interactionHost),
       _editing = StrokeSelectionEditingSession(editingHost),
       _editingHost = editingHost {
    session.pendingTransformSettler = endTransform;
  }

  final DrawingSelectionSession session = DrawingSelectionSession();
  final StrokeSelectionInteractionSession _interaction;
  final StrokeSelectionEditingSession _editing;
  final StrokeSelectionEditingHost _editingHost;
  final void Function() onChanged;
  final void Function() onClearDocumentSelection;
  bool _disposed = false;

  bool get isDisposed => _disposed;
  SelectionTool get tool => session.tool;
  Selection get selection => session.selection;
  List<Offset> get draft => session.draft;
  bool get hasSelection => session.hasSelection;
  bool get hasSelectedStrokes => session.hasSelectedStrokes;

  /// Weights selected colors by stroke length, preserving editor semantics.
  Color? get dominantStrokeColor {
    final distribution = <int, double>{};
    final strokes = _editingHost.currentLayer.strokes;
    for (final index in selection.selectedStrokeIndices) {
      if (index < 0 || index >= strokes.length) continue;
      final stroke = strokes[index];
      distribution.update(
        stroke.color.toARGB32(),
        (weight) => weight + stroke.points.length,
        ifAbsent: () => stroke.points.length.toDouble(),
      );
    }
    if (distribution.isEmpty) return null;
    final entry = distribution.entries.reduce(
      (a, b) => a.value >= b.value ? a : b,
    );
    return Color(entry.key);
  }

  void setTool(SelectionTool value) {
    if (_disposed) return;
    session.setTool(value);
    onChanged();
  }

  void replaceSelection(Selection value) {
    if (_disposed) return;
    session.selection = value;
    session.invalidateCenter();
  }

  void clearSelection() {
    if (!_disposed) onClearDocumentSelection();
  }

  void clearStrokeSelection() {
    if (!_disposed) session.clearSelection();
  }

  void beginSelection(Offset point) {
    if (!_disposed) _interaction.beginSelection(point);
  }

  void extendSelection(Offset point) {
    if (!_disposed) _interaction.extendSelection(point);
  }

  List<int> hitTestStrokes(List<Offset> polygon) =>
      _disposed ? <int>[] : _interaction.hitTestStrokes(polygon);

  void endSelection() {
    if (!_disposed) _interaction.endSelection();
  }

  void moveSelectedStrokes(Offset delta) {
    if (!_disposed) _editing.moveSelectedStrokes(delta);
  }

  void scaleSelectedStrokes(double factor) {
    if (!_disposed) _editing.scaleSelectedStrokes(factor);
  }

  void rotateSelectedStrokes(double radians) {
    if (!_disposed) _editing.rotateSelectedStrokes(radians);
  }

  void endTransform() {
    if (!_disposed) _editing.endTransform();
  }

  void deleteSelectedStrokes() {
    if (!_disposed) _editing.deleteSelectedStrokes();
  }

  void copySelectedStrokes() {
    if (!_disposed) _editing.copySelectedStrokes();
  }

  void pasteClipboard() {
    if (!_disposed) _editing.pasteClipboard();
  }

  void notifySelectionChanged() {
    if (!_disposed) onChanged();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    session.pendingTransformSettler = null;
    session.clearTransformBefore();
    session.clipboard = null;
  }
}
