import 'dart:ui';

import 'package:drawing_notes_app/engine/drawing_controller.dart';
import 'package:drawing_notes_app/models/document.dart';
import 'package:drawing_notes_app/models/shape_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('无限画布提交超出默认页面边界的笔画时不重建固定尺寸缓存', () async {
    final controller = DrawingController(
      DrawingDocument(id: 'infinite', title: '无限画布', infinite: true),
    );

    controller.startStroke(const Offset(-800, -400));
    controller.extendStroke(const Offset(4200, 2600));
    await controller.endStroke();

    expect(controller.document.layers.single.strokes, hasLength(1));
    expect(
      controller.document.layers.single.strokes.single.points.first.x,
      -800,
    );
    expect(controller.paintViews.single.image, isNull);
    controller.dispose();
  });

  test('无限画布内容边界同时包含笔画和独立形状', () async {
    final controller = DrawingController(
      DrawingDocument(
        id: 'infinite-bounds',
        title: '无限画布',
        infinite: true,
        shapes: [
          PageShapeItem(
            id: 'remote-shape',
            shapeType: ShapeType.rect,
            x: 5000,
            y: -600,
            width: 300,
            height: 200,
            strokeWidth: 8,
          ),
        ],
      ),
    );
    controller.startStroke(const Offset(-900, 300));
    controller.extendStroke(const Offset(-700, 340));
    await controller.endStroke();

    final bounds = controller.contentBounds();

    expect(bounds.left, lessThan(-900));
    expect(bounds.right, greaterThan(5300));
    expect(bounds.top, lessThan(-600));
    controller.dispose();
  });

  test('无限画布图层可直接绘制到当前可视区的记录器', () async {
    final controller = DrawingController(
      DrawingDocument(id: 'infinite', title: '无限画布', infinite: true),
    );
    controller.startStroke(const Offset(-50, 40));
    controller.extendStroke(const Offset(150, 60));
    await controller.endStroke();

    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    expect(
      () => controller.paintVectorLayers(
        canvas,
        const Rect.fromLTWH(-100, -100, 400, 400),
      ),
      returnsNormally,
    );
    recorder.endRecording().dispose();
    controller.dispose();
  });
}
