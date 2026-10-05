import 'dart:ui';

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/document_image_item.dart';
import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';
import 'package:drawing_notes_app/core/canvas_model/selection.dart';
import 'package:drawing_notes_app/core/canvas_model/stroke.dart';
import 'package:drawing_notes_app/features/drawing/application/document_commands.dart';
import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/features/drawing/application/services/history_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _Command extends DocCommand {
  int undoCalls = 0;
  int redoCalls = 0;
  @override
  void undo() => undoCalls++;
  @override
  void redo() => redoCalls++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  DrawingController controller(String id) {
    final result = DrawingController(
      DrawingDocument(id: id, title: id, width: 400, height: 400),
    );
    addTearDown(result.dispose);
    return result;
  }

  test(
    'history service records applied commands and trims the redo branch',
    () {
      final history = HistoryService(maxEntries: 2);
      addTearDown(history.dispose);
      final first = _Command();
      final second = _Command();
      final replacement = _Command();
      history.push(first);
      history.push(second);
      expect(first.redoCalls, 0);
      expect(history.undo(), isTrue);
      expect(second.undoCalls, 1);
      history.push(replacement);
      expect(history.canRedo, isFalse);
      expect(history.entryCount, 2);
      expect(history.undo(), isTrue);
      expect(replacement.undoCalls, 1);
      expect(history.redo(), isTrue);
      expect(replacement.redoCalls, 1);
    },
  );

  test('history service capacity, saved state and disposal are respected', () {
    final history = HistoryService(maxEntries: 2);
    final commands = List.generate(3, (_) => _Command());
    for (final command in commands) {
      history.push(command);
    }
    expect(history.entryCount, 2);
    expect(history.isDirty, isTrue);
    history.markSaved();
    expect(history.isDirty, isFalse);
    history.undo();
    history.undo();
    expect(history.undo(), isFalse);
    expect(commands.first.undoCalls, 0);
    history.dispose();
    history.push(_Command());
    history.markDirty();
    expect(history.entryCount, 2);
    expect(history.isDirty, isFalse);
    expect(history.undo(), isFalse);
    expect(history.redo(), isFalse);
  });

  test('controller and service share exactly one command stack', () {
    final c = controller('shared');
    final command = _Command();
    c.pushCommand(command);
    expect(c.historyService.entryCount, 1);
    expect(c.canUndo, isTrue);
    c.historyService.undo();
    expect(command.undoCalls, 1);
    expect(c.canUndo, isFalse);
    expect(c.canRedo, isTrue);
    c.redo();
    expect(command.redoCalls, 1);
    c.markSaved();
    expect(c.historyService.isDirty, isFalse);
  });

  test(
    'service selection transforms settle before a controller tool change',
    () {
      final c = controller('selection');
      c.currentLayer.strokes.add(
        Stroke(
          points: [StrokePoint(50, 50, 1), StrokePoint(100, 50, 1)],
          color: const Color(0xFF112233),
          width: 3,
          type: BrushType.pen,
        ),
      );
      c.selectionTool = SelectionTool.rect;
      c.selectionService.beginSelection(Offset.zero);
      c.extendSelection(const Offset(150, 150));
      c.selectionService.endSelection();
      expect(c.selection.selectedStrokeIndices, [0]);
      expect(c.selectionService.hasSelectedStrokes, isTrue);
      c.selectionService.moveSelectedStrokes(const Offset(20, 10));
      expect(c.currentLayer.strokes.single.points.first.x, 70);
      c.selectionTool = SelectionTool.none;
      expect(c.historyService.entryCount, 1);
      c.undo();
      expect(c.currentLayer.strokes.single.points.first.x, 50);
      c.redo();
      expect(c.currentLayer.strokes.single.points.first.x, 70);
    },
  );

  test('public clearSelection clears images and shapes as well as strokes', () {
    final c = controller('mixed-clear');
    c.document.shapes.add(
      PageShapeItem(
        id: 'shape',
        shapeType: ShapeType.rect,
        x: 10,
        y: 10,
        width: 20,
        height: 20,
      ),
    );
    c.document.imageItems.add(
      DocumentImageItem(
        id: 'image',
        x: 40,
        y: 10,
        width: 20,
        height: 20,
        filePath: '/assets/not-loaded.png',
      ),
    );
    c.selectDocumentObjectsInPolygon(const [
      Offset.zero,
      Offset(100, 0),
      Offset(100, 100),
      Offset(0, 100),
    ]);
    expect(c.selectedDocumentObjectCount, 2);
    c.clearStrokeSelection();
    expect(c.selectedDocumentObjectCount, 2);
    c.clearSelection();
    expect(c.selectedDocumentShapeIds, isEmpty);
    expect(c.selectedDocumentImageIds, isEmpty);
    expect(c.selectedDocumentObjectCount, 0);
    expect(c.hasSelection, isFalse);
  });

  test('two open documents keep service history and selection independent', () {
    final a = controller('a');
    final b = controller('b');
    a.pushCommand(_Command());
    a.selectionTool = SelectionTool.rect;
    a.beginSelection(Offset.zero);
    a.extendSelection(const Offset(100, 100));
    a.endSelection();
    expect(b.historyService.entryCount, 0);
    expect(b.hasSelection, isFalse);
    expect(a.hasSelection, isTrue);
    a.dispose();
    a.selectionService.beginSelection(Offset.zero);
    a.historyService.push(_Command());
    expect(a.historyService.entryCount, 1);
    expect(a.historyService.undo(), isFalse);
    expect(b.selectionService.isDisposed, isFalse);
  });
}
