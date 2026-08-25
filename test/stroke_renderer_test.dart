import 'dart:ui';

import 'package:drawing_notes_app/features/drawing/domain/stroke.dart';
import 'package:drawing_notes_app/core/rendering/stroke_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  StrokePoint makePoint(double x, {double pressure = 0.5}) {
    return StrokePoint(x, 0, pressure);
  }

  Stroke makeStroke(List<StrokePoint> points,
      {BrushType type = BrushType.pen, Color color = const Color(0xFF000000)}) {
    return Stroke(points: points, color: color, width: 8, type: type);
  }

  // ---------------------------------------------------------------------------
  // strokeOutline
  // ---------------------------------------------------------------------------
  group('strokeOutline', () {
    test('空点列返回 null', () {
      final stroke = makeStroke([]);
      expect(StrokeRenderer.strokeOutline(stroke), isNull);
    });

    test('单点笔画返回圆形 Path', () {
      final stroke = makeStroke([makePoint(50, pressure: 0.8)]);
      final outline = StrokeRenderer.strokeOutline(stroke);
      expect(outline, isNotNull);
      final bounds = outline!.getBounds();
      expect(bounds.width, greaterThan(0));
      expect(bounds.height, greaterThan(0));
      expect(bounds.center.dx, closeTo(50, 2));
      expect(bounds.center.dy, closeTo(0, 2));
    });

    test('多点笔画返回非空闭合 Path', () {
      final stroke = makeStroke([
        makePoint(0, pressure: 0.3),
        makePoint(10),
        makePoint(20, pressure: 0.7),
        makePoint(30),
        makePoint(40, pressure: 0.3),
      ]);
      final outline = StrokeRenderer.strokeOutline(stroke);
      expect(outline, isNotNull);
      expect(outline!.getBounds().width, greaterThan(0));
    });

    test('usePressure=false 时仍可生成轮廓', () {
      final stroke = makeStroke([
        makePoint(0),
        makePoint(10),
        makePoint(20),
        makePoint(30),
        makePoint(40),
      ]);
      final outline = StrokeRenderer.strokeOutline(stroke, usePressure: false);
      expect(outline, isNotNull);
    });

    test('显式传入 speed 参数', () {
      final stroke = makeStroke([
        makePoint(0),
        makePoint(50),
        makePoint(100),
      ]);
      final outline = StrokeRenderer.strokeOutline(stroke, speed: 500);
      expect(outline, isNotNull);
    });
  });

  // ---------------------------------------------------------------------------
  // strokeBounds
  // ---------------------------------------------------------------------------
  group('strokeBounds', () {
    test('空点列返回 null', () {
      final stroke = makeStroke([]);
      expect(StrokeRenderer.strokeBounds(stroke), isNull);
    });

    test('单点笔画的包围盒包含点位 + 半径', () {
      final stroke = makeStroke([makePoint(100)]);
      final bounds = StrokeRenderer.strokeBounds(stroke);
      expect(bounds, isNotNull);
      expect(bounds!.left, lessThan(100));
      expect(bounds.right, greaterThan(100));
      expect(bounds.width, greaterThanOrEqualTo(stroke.width));
    });

    test('多点笔画包围盒覆盖所有点', () {
      final stroke = makeStroke([
        makePoint(0),
        makePoint(100),
        makePoint(50),
      ]);
      final bounds = StrokeRenderer.strokeBounds(stroke);
      expect(bounds, isNotNull);
      expect(bounds!.left, lessThan(0));
      expect(bounds.right, greaterThan(100));
    });
  });

  // ---------------------------------------------------------------------------
  // strokeToSvgPath
  // ---------------------------------------------------------------------------
  group('strokeToSvgPath', () {
    test('空点列返回 null', () {
      final stroke = makeStroke([]);
      expect(StrokeRenderer.strokeToSvgPath(stroke), isNull);
    });

    test('单点笔画返回包含 M 和 Z 的 SVG 路径', () {
      final stroke = makeStroke([makePoint(50)]);
      final svg = StrokeRenderer.strokeToSvgPath(stroke);
      expect(svg, isNotNull);
      expect(svg!.startsWith('M '), isTrue);
      expect(svg.endsWith(' Z'), isTrue);
    });

    test('多点笔画返回 M...L...Z 路径', () {
      final stroke = makeStroke([
        makePoint(0),
        makePoint(10),
        makePoint(20),
        makePoint(30),
      ]);
      final svg = StrokeRenderer.strokeToSvgPath(stroke);
      expect(svg, isNotNull);
      expect(svg!.contains('L '), isTrue);
    });

    test('offset 参数平移输出坐标', () {
      final stroke = makeStroke([makePoint(10)]);
      final svg1 = StrokeRenderer.strokeToSvgPath(stroke);
      final svg2 =
          StrokeRenderer.strokeToSvgPath(stroke, offset: const Offset(100, 0));
      expect(svg1, isNot(equals(svg2)));
    });
  });

  // ---------------------------------------------------------------------------
  // drawStroke
  // ---------------------------------------------------------------------------
  group('drawStroke', () {
    test('空点列不抛异常', () {
      final stroke = makeStroke([]);
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      expect(
        () => StrokeRenderer.drawStroke(canvas, stroke),
        returnsNormally,
      );
    });

    test('单点笔画在 Canvas 上绘制不抛异常', () {
      final stroke = makeStroke([makePoint(50, pressure: 0.8)]);
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      expect(
        () => StrokeRenderer.drawStroke(canvas, stroke),
        returnsNormally,
      );
    });

    test('colorOverride 生效', () {
      final stroke = makeStroke([makePoint(50, pressure: 0.8)]);
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      expect(
        () => StrokeRenderer.drawStroke(
          canvas,
          stroke,
          colorOverride: const Color(0xFFFF0000),
        ),
        returnsNormally,
      );
    });

    test('opacityOverride 生效', () {
      final stroke = makeStroke([makePoint(50, pressure: 0.8)]);
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      expect(
        () => StrokeRenderer.drawStroke(
          canvas,
          stroke,
          opacityOverride: 0.5,
        ),
        returnsNormally,
      );
    });

    test('不同画笔类型均可绘制（pen/pencil/marker/eraser）', () {
      for (final type in BrushType.values) {
        if (type == BrushType.laser) continue;
        final stroke = makeStroke([
          makePoint(0),
          makePoint(10),
          makePoint(20),
        ], type: type);
        final recorder = PictureRecorder();
        final canvas = Canvas(recorder);
        expect(
          () => StrokeRenderer.drawStroke(canvas, stroke),
          returnsNormally,
          reason: '$type should draw without error',
        );
      }
    });
  });
}
