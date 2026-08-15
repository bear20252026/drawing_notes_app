import 'dart:math' as math;
import 'dart:ui';

import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/core/rendering/shape_recognizer.dart';
import 'package:drawing_notes_app/features/drawing/domain/document.dart';
import 'package:drawing_notes_app/features/drawing/domain/shape_item.dart';
import 'package:drawing_notes_app/features/drawing/domain/stroke.dart';
import 'package:flutter_test/flutter_test.dart';

Stroke _stroke(List<Offset> points, {BrushType type = BrushType.pen}) => Stroke(
  type: type,
  color: const Color(0xFF2457A5),
  width: 5,
  points: [for (final point in points) StrokePoint(point.dx, point.dy, 1)],
);

void main() {
  test('闭合并沿边行进的手绘轮廓识别为矩形', () {
    final recognized = ShapeRecognizer.recognize(
      _stroke(const [
        Offset(10, 10),
        Offset(60, 10),
        Offset(110, 10),
        Offset(110, 45),
        Offset(110, 80),
        Offset(60, 80),
        Offset(10, 80),
        Offset(10, 45),
        Offset(10, 10),
      ]),
    );

    expect(recognized, isNotNull);
    expect(recognized!.type, ShapeType.rect);
    expect(recognized.bounds, const Rect.fromLTWH(10, 10, 100, 70));
  });

  test('多采样的高直线度笔画识别为方向正确的直线', () {
    final recognized = ShapeRecognizer.recognize(
      _stroke(const [
        Offset(120, 40),
        Offset(90, 40.5),
        Offset(60, 39.5),
        Offset(30, 40),
      ]),
    );

    expect(recognized, isNotNull);
    expect(recognized!.type, ShapeType.line);
    // 真实端点保存了鼠标轨迹方向（从右往左），
    // 取代旧的 flipX/flipY 表达（修复方向不一致问题）。
    expect(recognized.lineStart, isNotNull);
    expect(recognized.lineEnd, isNotNull);
    expect(recognized.lineStart!.dx, greaterThan(recognized.lineEnd!.dx));
  });

  test('闭合菱形轮廓识别为菱形而非椭圆', () {
    final recognized = ShapeRecognizer.recognize(
      _stroke(const [
        Offset(60, 10),
        Offset(110, 45),
        Offset(60, 80),
        Offset(10, 45),
        Offset(60, 10),
      ]),
    );

    expect(recognized, isNotNull);
    expect(recognized!.type, ShapeType.diamond);
  });

  test('闭合且径向误差小的手绘轮廓识别为椭圆', () {
    final points = <Offset>[];
    for (var index = 0; index <= 16; index++) {
      final radians = math.pi * 2 * index / 16;
      points.add(
        Offset(100 + 50 * math.cos(radians), 80 + 35 * math.sin(radians)),
      );
    }

    final recognized = ShapeRecognizer.recognize(_stroke(points));

    expect(recognized, isNotNull);
    expect(recognized!.type, ShapeType.ellipse);
    expect(recognized.bounds.width, closeTo(100, 0.001));
    expect(recognized.bounds.height, closeTo(70, 0.001));
  });

  test('开放路径、高亮笔和低置信度涂鸦均保持原笔画', () {
    expect(
      ShapeRecognizer.recognize(
        _stroke(const [Offset(10, 10), Offset(80, 40), Offset(160, 10)]),
      ),
      isNull,
    );
    expect(
      ShapeRecognizer.recognize(
        _stroke(const [Offset(10, 10), Offset(160, 10)]),
      ),
      isNull,
      reason: '一次快速单段书写仍应作为普通墨迹保留',
    );
    expect(
      ShapeRecognizer.recognize(
        _stroke(const [
          Offset(10, 10),
          Offset(110, 10),
          Offset(110, 80),
          Offset(10, 80),
          Offset(10, 10),
          Offset(70, 45),
        ], type: BrushType.marker),
      ),
      isNull,
    );
  });

  test('控制器把已识别笔画原子替换为形状且可撤销重做', () async {
    final controller = DrawingController(
      DrawingDocument(id: 'recognition_controller', title: '形状识别'),
    );
    addTearDown(controller.dispose);

    for (final point in const [
      Offset(20, 20),
      Offset(120, 20),
      Offset(120, 90),
      Offset(20, 90),
      Offset(20, 20),
    ]) {
      if (controller.activeStroke == null) {
        controller.startStroke(point);
      } else {
        controller.extendStroke(point);
      }
    }
    await controller.endStroke();

    expect(controller.document.layers.single.strokes, isEmpty);
    expect(controller.document.shapes, hasLength(1));
    expect(controller.document.shapes.single.shapeType, ShapeType.rect);

    controller.undo();
    expect(controller.document.shapes, isEmpty);
    expect(controller.document.layers.single.strokes, hasLength(1));

    controller.redo();
    expect(controller.document.layers.single.strokes, isEmpty);
    expect(controller.document.shapes, hasLength(1));
  });
}
