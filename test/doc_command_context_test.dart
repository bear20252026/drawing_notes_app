import 'dart:ui' show Color;

import 'package:drawing_notes_app/features/drawing/application/doc_command_context.dart';
import 'package:drawing_notes_app/features/drawing/application/document_commands.dart';
import 'package:drawing_notes_app/features/drawing/domain/document.dart';
import 'package:drawing_notes_app/features/drawing/domain/layer.dart';
import 'package:drawing_notes_app/features/drawing/domain/shape_item.dart';
import 'package:drawing_notes_app/features/drawing/domain/stroke.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingCommandContext implements DocCommandContext {
  _RecordingCommandContext(this.document);

  @override
  final DrawingDocument document;

  int touchCount = 0;
  final List<int> refreshedLayers = [];
  List<Layer>? restoredLayers;
  String? recognizedShapeAction;

  @override
  Future<void> afterStrokeUndoRedo(int layerIndex) async {
    refreshedLayers.add(layerIndex);
  }

  @override
  void redoRecognizedShape(int layerIndex, Stroke stroke, PageShapeItem shape) {
    recognizedShapeAction =
        'redo:$layerIndex:${stroke.points.length}:${shape.id}';
  }

  @override
  void restoreLayersSnapshot(List<Layer> snapshot) {
    restoredLayers = snapshot;
  }

  @override
  void touchDocument() {
    touchCount++;
  }

  @override
  void undoRecognizedShape(int layerIndex, Stroke stroke, PageShapeItem shape) {
    recognizedShapeAction =
        'undo:$layerIndex:${stroke.points.length}:${shape.id}';
  }
}

Stroke _stroke() => Stroke(
  points: [StrokePoint(4, 8, 1), StrokePoint(12, 16, 0.8)],
  color: const Color(0xFF112233),
  width: 5,
  type: BrushType.pen,
);

void main() {
  test('新增笔画命令仅依赖中立上下文即可撤销与重做', () {
    final document = DrawingDocument(id: 'doc', title: '命令测试');
    final context = _RecordingCommandContext(document);
    final stroke = _stroke();
    document.layers.first.strokes.add(stroke);
    final command = AddStrokeCommand(context, 0, stroke);

    command.undo();
    expect(document.layers.first.strokes, isEmpty);
    expect(context.touchCount, 1);
    expect(context.refreshedLayers, [0]);

    command.redo();
    expect(document.layers.first.strokes, [stroke]);
    expect(context.touchCount, 2);
    expect(context.refreshedLayers, [0, 0]);
  });

  test('快照命令将恢复委托给中立上下文', () {
    final context = _RecordingCommandContext(
      DrawingDocument(id: 'doc', title: '快照测试'),
    );
    final before = [Layer(id: 'before', name: '之前')];
    final after = [Layer(id: 'after', name: '之后')];
    final command = SnapshotCommand(context, before, after);

    command.undo();
    expect(context.restoredLayers, same(before));

    command.redo();
    expect(context.restoredLayers, same(after));
  });

  test('识别形状命令将具体恢复逻辑留给上下文实现', () {
    final context = _RecordingCommandContext(
      DrawingDocument(id: 'doc', title: '形状测试'),
    );
    final stroke = _stroke();
    final shape = PageShapeItem(
      id: 'shape',
      shapeType: ShapeType.rect,
      x: 0,
      y: 0,
      width: 30,
      height: 20,
    );
    final command = ReplaceStrokeWithShapeCommand(context, 0, stroke, shape);

    command.undo();
    expect(context.recognizedShapeAction, 'undo:0:2:shape');

    command.redo();
    expect(context.recognizedShapeAction, 'redo:0:2:shape');
  });
}
