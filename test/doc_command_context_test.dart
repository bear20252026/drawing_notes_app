import 'dart:ui' show Color;

import 'package:drawing_notes_app/features/drawing/application/doc_command_context.dart';
import 'package:drawing_notes_app/features/drawing/application/document_commands.dart';
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/layer.dart';
import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';
import 'package:drawing_notes_app/core/canvas_model/stroke.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingCommandContext implements DocCommandContext {
  _RecordingCommandContext(this.document);

  @override
  final DrawingDocument document;

  int touchCount = 0;
  int layerUndoRedoCount = 0;
  final List<int> refreshedLayers = [];
  List<Layer>? restoredLayers;
  String? recognizedShapeAction;

  @override
  void afterLayerUndoRedo() {
    layerUndoRedoCount++;
  }

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

  // 2026-10-03 复核：layerUndoRedoCount 此前只累加、从无 expect——删掉
  // 命令里的 afterLayerUndoRedo() 调用测试仍全绿，而真实后果是当前图层
  // 索引不再钳制、面板不再刷新（对应 DrawingController.afterLayerUndoRedo）。
  test('图层显隐窄命令撤销与重做都必须走图层级收尾', () {
    final document = DrawingDocument(id: 'doc', title: '图层显隐');
    document.layers.add(Layer(id: 'layer-2', name: '图层 2'));
    final context = _RecordingCommandContext(document);
    final command = LayerVisibilityCommand(context, 1, true, false);

    command.undo();
    expect(document.layers[1].visible, isTrue);
    expect(context.layerUndoRedoCount, 1, reason: '撤销必须收尾刷新图层 UI');
    expect(context.touchCount, 1);

    command.redo();
    expect(document.layers[1].visible, isFalse);
    expect(context.layerUndoRedoCount, 2, reason: '重做同样必须收尾');
    expect(context.touchCount, 2);
  });

  test('图层换位窄命令撤销与重做都必须走图层级收尾', () {
    final document = DrawingDocument(id: 'doc', title: '图层换位');
    // 命令记录「已发生的一次换位」：构造时文档处于换位后的状态。
    document.layers
      ..clear()
      ..addAll(<Layer>[
        Layer(id: 'layer-2', name: '图层 2'),
        Layer(id: 'layer-3', name: '图层 3'),
        Layer(id: 'layer-1', name: '图层 1'),
      ]);
    final context = _RecordingCommandContext(document);
    final command = LayerReorderCommand(context, 0, 2);

    command.undo();
    expect(document.layers.map((layer) => layer.id), <String>[
      'layer-1',
      'layer-2',
      'layer-3',
    ]);
    expect(context.layerUndoRedoCount, 1);

    command.redo();
    expect(document.layers.map((layer) => layer.id), <String>[
      'layer-2',
      'layer-3',
      'layer-1',
    ]);
    expect(context.layerUndoRedoCount, 2);
  });

  // 擦除命令的形状恢复：必须放回**原实例**且落回**原序号**，否则
  // redo 按 identity 移不掉（重做无效）、再次 undo 追加同 id 副本。
  test('擦除形状按原实例与原序号插回，重做按 identity 移除', () {
    final document = DrawingDocument(id: 'doc', title: '擦除形状');
    final erased = PageShapeItem(
      id: 'erased',
      shapeType: ShapeType.rect,
      x: 0,
      y: 0,
      width: 10,
      height: 10,
    );
    final kept = PageShapeItem(
      id: 'kept',
      shapeType: ShapeType.rect,
      x: 40,
      y: 0,
      width: 10,
      height: 10,
    );
    // 擦除后只剩 kept，erased 的原序号是 0（在 kept 之下）。
    document.layers
      ..clear()
      ..add(Layer(id: 'layer-1', name: '图层 1'));
    document.shapes
      ..clear()
      ..add(kept);
    final context = _RecordingCommandContext(document);
    final command = EraseStrokesCommand(
      context,
      const <({int layerIndex, int index, Stroke stroke})>[],
      removedShapeEntries: <({int index, PageShapeItem shape})>[
        (index: 0, shape: erased),
      ],
    );

    command.undo();
    expect(document.shapes, <PageShapeItem>[erased, kept], reason: '插回原序号');
    expect(identical(document.shapes.first, erased), isTrue, reason: '放回原实例');

    command.redo();
    expect(document.shapes, <PageShapeItem>[kept]);

    command.undo();
    expect(document.shapes, <PageShapeItem>[erased, kept]);
    expect(
      document.shapes.map((shape) => shape.id).toSet().length,
      document.shapes.length,
      reason: '反复 undo/redo 不产生同 id 副本',
    );
    expect(context.touchCount, 3);
  });
}
