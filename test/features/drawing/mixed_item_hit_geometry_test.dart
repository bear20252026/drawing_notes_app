// R3（审查 2026-11-17）：MixedItemHitGeometry 纯函数单测。
//
// 此前框选/套索命中口径散在 _onPointerUp 手势巨方法里不可单测——收敛进
// infrastructure 纯函数后，边界口径（文字宽 = fontSize*2、套索取中心点、
// 文字→图片→形状顺序）成为可直接验证的机器事实。
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/canvas_model/page_image_item.dart';
import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';
import 'package:drawing_notes_app/core/canvas_model/text_item.dart';
import 'package:drawing_notes_app/features/drawing/infrastructure/mixed_item_hit_geometry.dart';

void main() {
  PageTextItem text(String id, double x, double y, {double fontSize = 16}) =>
      PageTextItem(id: id, x: x, y: y, text: 'T', fontSize: fontSize);
  PageImageItem image(String id, double x, double y,
          {double w = 40, double h = 30}) =>
      PageImageItem(id: id, x: x, y: y, filePath: 'p.png', width: w, height: h);
  PageShapeItem shape(String id, double x, double y,
          {double w = 50, double h = 50}) =>
      PageShapeItem(
        id: id,
        x: x,
        y: y,
        width: w,
        height: h,
        shapeType: ShapeType.rect,
        color: 0xFF000000,
        strokeWidth: 2,
      );

  group('idsInRect（框选）', () {
    test('三类对象各自的外接矩形口径：文字宽=fontSize*2', () {
      final t = text('t1', 100, 100, fontSize: 20); // 矩形 100,100,40,20
      final i = image('i1', 200, 100); // 200,100,40,30
      final s = shape('s1', 300, 100); // 300,100,50,50
      // 只罩住文字矩形右半（x 120-139）：文字命中，图片/形状不命中。
      final ids = MixedItemHitGeometry.idsInRect(
        rect: const Rect.fromLTWH(120, 105, 19, 10),
        textItems: [t],
        imageItems: [i],
        shapes: [s],
      );
      expect(ids, ['t1']);
    });

    test('顺序契约：文字→图片→形状（多选锚定语义依赖）', () {
      final ids = MixedItemHitGeometry.idsInRect(
        rect: const Rect.fromLTWH(0, 0, 1000, 1000),
        textItems: [text('t1', 10, 10), text('t2', 20, 20)],
        imageItems: [image('i1', 30, 30)],
        shapes: [shape('s1', 40, 40)],
      );
      expect(ids, ['t1', 't2', 'i1', 's1']);
    });

    test('不相交不命中；空集合返回空', () {
      expect(
        MixedItemHitGeometry.idsInRect(
          rect: const Rect.fromLTWH(500, 500, 10, 10),
          textItems: [text('t1', 0, 0)],
          imageItems: const [],
          shapes: const [],
        ),
        isEmpty,
      );
      expect(
        MixedItemHitGeometry.idsInRect(
          rect: const Rect.fromLTWH(0, 0, 100, 100),
          textItems: const [],
          imageItems: const [],
          shapes: const [],
        ),
        isEmpty,
      );
    });
  });

  group('idsInPolygon（套索）', () {
    test('中心点口径：文字中心=(x+fontSize, y+fontSize/2)', () {
      // 文字 t1 在 (100,100) fontSize 20 → 中心 (120,110)。
      final t = text('t1', 100, 100, fontSize: 20);
      // 多边形只罩中心点附近，不罩文字左上角。
      final ids = MixedItemHitGeometry.idsInPolygon(
        polygon: const [
          Offset(115, 105),
          Offset(125, 105),
          Offset(125, 115),
          Offset(115, 115),
        ],
        textItems: [t],
        imageItems: const [],
        shapes: const [],
      );
      expect(ids, ['t1']);
      // 反过来：罩左上角但不罩中心 → 不命中。
      final miss = MixedItemHitGeometry.idsInPolygon(
        polygon: const [
          Offset(100, 100),
          Offset(108, 100),
          Offset(108, 104),
          Offset(100, 104),
        ],
        textItems: [t],
        imageItems: const [],
        shapes: const [],
      );
      expect(miss, isEmpty);
    });

    test('图片/形状中心口径 + 顺序契约', () {
      final ids = MixedItemHitGeometry.idsInPolygon(
        polygon: const [
          Offset(0, 0),
          Offset(1000, 0),
          Offset(1000, 1000),
          Offset(0, 1000),
        ],
        textItems: [text('t1', 10, 10)],
        imageItems: [image('i1', 30, 30)],
        shapes: [shape('s1', 40, 40)],
      );
      expect(ids, ['t1', 'i1', 's1']);
    });

    test('少于 3 个顶点 → 空（退化多边形不构成套索）', () {
      expect(
        MixedItemHitGeometry.idsInPolygon(
          polygon: const [Offset(0, 0), Offset(100, 100)],
          textItems: [text('t1', 10, 10)],
          imageItems: const [],
          shapes: const [],
        ),
        isEmpty,
      );
    });
  });
}