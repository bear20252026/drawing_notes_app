import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/features/drawing/domain/document.dart';
import 'package:drawing_notes_app/features/drawing/domain/stroke.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('自动消失高亮笔仅保留在临时渲染层，不写入文档或撤销历史', () async {
    final controller = DrawingController(
      DrawingDocument(id: 'temporary_marker', title: '临时高亮笔'),
    );
    addTearDown(controller.dispose);

    controller.tool = BrushType.marker;
    controller.temporaryMarkerEnabled = true;
    controller.startStroke(const Offset(16, 24));
    controller.extendStroke(const Offset(120, 24));
    await controller.endStroke();

    expect(controller.document.layers.single.strokes, isEmpty);
    expect(controller.canUndo, isFalse);
    expect(controller.temporaryMarkerStrokes, hasLength(1));
    expect(
      controller.temporaryMarkerStrokes.single.stroke.type,
      BrushType.marker,
    );
    expect(controller.temporaryMarkerStrokes.single.opacity, greaterThan(0));
  });

  test('关闭自动消失后，高亮笔恢复普通保存、撤销行为', () async {
    final controller = DrawingController(
      DrawingDocument(id: 'persistent_marker', title: '普通高亮笔'),
    );
    addTearDown(controller.dispose);

    controller.tool = BrushType.marker;
    controller.temporaryMarkerEnabled = false;
    controller.startStroke(const Offset(16, 24));
    controller.extendStroke(const Offset(120, 24));
    await controller.endStroke();

    expect(controller.document.layers.single.strokes, hasLength(1));
    expect(
      controller.document.layers.single.strokes.single.type,
      BrushType.marker,
    );
    expect(controller.canUndo, isTrue);
    expect(controller.temporaryMarkerStrokes, isEmpty);
  });
}
