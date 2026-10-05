import 'package:drawing_notes_app/features/drawing/application/document_commands.dart';
import 'package:drawing_notes_app/features/drawing/application/document_edit_history.dart';

import 'drawing_service.dart';

/// Owns command history and saved state for one drawing document.
/// Commands passed to [push] have already been applied by the editing session.
final class HistoryService implements DrawingService {
  HistoryService({int maxEntries = 60})
    : _history = DocumentEditHistory(maxEntries: maxEntries);

  final DocumentEditHistory _history;
  bool _disposed = false;

  bool get isDisposed => _disposed;
  bool get canUndo => !_disposed && _history.canUndo;
  bool get canRedo => !_disposed && _history.canRedo;
  bool get isDirty => _history.isDirty;
  int get entryCount => _history.entryCount;

  void push(DocCommand command) {
    if (!_disposed) _history.push(command);
  }

  bool undo() => !_disposed && _history.undo();
  bool redo() => !_disposed && _history.redo();

  void markDirty() {
    if (!_disposed) _history.markDirty();
  }

  void markSaved() {
    if (!_disposed) _history.markSaved();
  }

  @override
  void dispose() => _disposed = true;
}
