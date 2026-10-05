import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/selection.dart';
import 'package:drawing_notes_app/features/drawing/application/document_commands.dart';
import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/features/drawing/application/services/history_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'history boundary preserves branch trimming and stops after disposal',
    () {
      final events = <String>[];
      final history = HistoryService(maxEntries: 2);
      history.push(_Command('first', events));
      history.push(_Command('second', events));
      expect(history.undo(), isTrue);
      history.push(_Command('replacement', events));
      expect(history.canRedo, isFalse);
      expect(history.entryCount, 2);
      expect(history.undo(), isTrue);
      expect(history.undo(), isTrue);
      expect(events, ['undo:second', 'undo:replacement', 'undo:first']);
      history.dispose();
      history.push(_Command('ignored', events));
      expect(history.redo(), isFalse);
      expect(history.canUndo, isFalse);
      expect(history.canRedo, isFalse);
      expect(history.entryCount, 2);
    },
  );

  test('direct service selection edits share controller history and save state', () async {
    final controller = DrawingController(
      DrawingDocument(id: 'services', title: 'test', width: 200, height: 200),
    );
    addTearDown(controller.dispose);
    controller.startStroke(const Offset(30, 30));
    controller.extendStroke(const Offset(70, 30));
    await controller.endStroke();
    controller.markSaved();
    expect(controller.historyService.isDirty, isFalse);

    final service = controller.selectionService;
    service.setTool(SelectionTool.rect);
    service.beginSelection(Offset.zero);
    service.extendSelection(const Offset(100, 100));
    service.endSelection();
    expect(controller.selection.selectedStrokeIndices, [0]);
    expect(identical(controller.selectionSession, service.session), isTrue);
    final before = controller.currentLayer.strokes.first.points.first.offset;
    service.moveSelectedStrokes(const Offset(10, 20));
    // Switching tools must settle the pending gesture into exactly one command.
    service.setTool(SelectionTool.lasso);
    expect(controller.historyService.entryCount, 2);
    expect(controller.isDirty, isTrue);
    expect(controller.historyService.undo(), isTrue);
    expect(controller.currentLayer.strokes.first.points.first.offset, before);
    controller.redo();
    expect(
      controller.currentLayer.strokes.first.points.first.offset,
      before + const Offset(10, 20),
    );
    controller.markSaved();
    expect(controller.historyService.isDirty, isFalse);
  });

  test(
    'selection service refuses mutations and notifications after disposal',
    () {
      final controller = DrawingController(
        DrawingDocument(id: 'disposed-services', title: 'test'),
      );
      var notifications = 0;
      controller.addListener(() => notifications++);
      final service = controller.selectionService;
      controller.dispose();
      service.setTool(SelectionTool.rect);
      service.beginSelection(const Offset(10, 10));
      service.notifySelectionChanged();
      expect(service.draft, isEmpty);
      expect(notifications, 0);
      expect(service.session.pendingTransformSettler, isNull);
    },
  );
}

class _Command extends DocCommand {
  _Command(this.name, this.events);
  final String name;
  final List<String> events;
  @override
  void undo() => events.add('undo:$name');
  @override
  void redo() => events.add('redo:$name');
}
