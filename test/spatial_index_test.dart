// 渲染引擎单元测试——空间索引（SpatialIndex）。
//
// 验证网格分区空间索引的查询精度：
// - insert/query 往返正确性
// - queryPoint 点命中
// - remove/clear 生命周期
// - 负坐标（Cantor pairing 键映射）
// - 大元素跨多网格单元
// - ElementBounds 批量重建（updateAll）
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/features/drawing/application/spatial_index.dart';
import 'package:drawing_notes_app/features/drawing/domain/shape_item.dart';
import 'package:drawing_notes_app/features/drawing/domain/stroke.dart';

void main() {
  group('SpatialIndex 基本操作', () {
    test('insert 后 query 能命中相交元素', () {
      final index = SpatialIndex();
      index.insert('a', const Rect.fromLTWH(0, 0, 50, 50));

      final hits = index.query(const Rect.fromLTWH(10, 10, 20, 20));
      expect(hits, contains('a'));
    });

    test('query 不命中不相交元素（查询精度）', () {
      final index = SpatialIndex();
      index.insert('far', const Rect.fromLTWH(500, 500, 50, 50));
      index.insert('near', const Rect.fromLTWH(100, 100, 30, 30));

      // 与两者都不相交
      final hits = index.query(const Rect.fromLTWH(0, 0, 10, 10));
      expect(hits, isEmpty);
    });

    test('边界恰好相接不视为相交（Rect.overlaps 开区间语义）', () {
      final index = SpatialIndex();
      index.insert('a', const Rect.fromLTWH(0, 0, 64, 64));

      // Rect.overlaps 要求严格大于：right > other.left，
      // 仅共享边线（right == other.left）不算相交。
      final edgeHits = index.query(const Rect.fromLTWH(64, 0, 10, 10));
      expect(edgeHits, isNot(contains('a')));

      // 有实际重叠时命中
      final overlapping =
          index.query(const Rect.fromLTWH(63.5, 0, 10, 10));
      expect(overlapping, contains('a'));
    });

    test('remove 之后不再命中', () {
      final index = SpatialIndex();
      index.insert('a', const Rect.fromLTWH(0, 0, 50, 50));
      index.remove('a');

      final hits = index.query(const Rect.fromLTWH(0, 0, 64, 64));
      expect(hits, isEmpty);
    });

    test('remove 不存在的 id 是安全空操作', () {
      final index = SpatialIndex();
      expect(() => index.remove('ghost'), returnsNormally);
    });

    test('clear 清空全部索引', () {
      final index = SpatialIndex();
      index.insert('a', const Rect.fromLTWH(0, 0, 10, 10));
      index.insert('b', const Rect.fromLTWH(200, 200, 10, 10));
      index.clear();

      expect(index.query(const Rect.fromLTWH(0, 0, 1000, 1000)), isEmpty);
      expect(index.debugGrid, isEmpty);
      expect(index.boundsFor('a'), isNull);
    });
  });

  group('SpatialIndex 点查询', () {
    test('queryPoint 命中包含该点的元素', () {
      final index = SpatialIndex();
      index.insert('box', const Rect.fromLTWH(10, 10, 40, 40));

      expect(index.queryPoint(const Offset(30, 30)), contains('box'));
      // 元素外一点不命中
      expect(index.queryPoint(const Offset(100, 100)), isEmpty);
    });

    test('同点重叠的多个元素全部返回', () {
      final index = SpatialIndex();
      index.insert('a', const Rect.fromLTWH(0, 0, 20, 20));
      index.insert('b', const Rect.fromLTWH(5, 5, 20, 20));

      final hits = index.queryPoint(const Offset(10, 10));
      expect(hits, containsAll(['a', 'b']));
    });
  });

  group('SpatialIndex 网格划分', () {
    test('跨多个网格单元的大元素可被任一覆盖区域的查询命中', () {
      final index = SpatialIndex(cellSize: 64);
      // 300x300 的元素跨越约 5x5 个 64px 网格
      index.insert('big', const Rect.fromLTWH(0, 0, 300, 300));

      expect(
        index.query(const Rect.fromLTWH(250, 250, 20, 20)),
        contains('big'),
      );
      expect(
        index.query(const Rect.fromLTWH(10, 10, 5, 5)),
        contains('big'),
      );
    });

    test('负坐标元素正常工作（Cantor pairing 键无冲突）', () {
      final index = SpatialIndex();
      index.insert('neg', const Rect.fromLTWH(-100, -100, 50, 50));
      index.insert('pos', const Rect.fromLTWH(100, 100, 50, 50));

      expect(
        index.query(const Rect.fromLTWH(-90, -90, 10, 10)),
        contains('neg'),
      );
      expect(
        index.query(const Rect.fromLTWH(-90, -90, 10, 10)),
        isNot(contains('pos')),
      );
      expect(
        index.query(const Rect.fromLTWH(110, 110, 10, 10)),
        contains('pos'),
      );
    });

    test('同一元素重复插入以最后一次 bounds 为准且不产生重复命中', () {
      final index = SpatialIndex();
      index.insert('a', const Rect.fromLTWH(0, 0, 10, 10));
      index.insert('a', const Rect.fromLTWH(200, 200, 10, 10));

      // 旧位置的网格残留不应造成误报：query 会用最新 bounds 过滤
      final oldHits = index.query(const Rect.fromLTWH(0, 0, 10, 10));
      expect(oldHits, isNot(contains('a')));

      final newHits = index.query(const Rect.fromLTWH(200, 200, 10, 10));
      expect(newHits, contains('a'));
      // boundsFor 反映最新值
      expect(index.boundsFor('a'), const Rect.fromLTWH(200, 200, 10, 10));
    });
  });

  group('ElementBounds 辅助类', () {
    Stroke makeStroke(List<Offset> pts) => Stroke(
          points: pts
              .map((o) => StrokePoint(o.dx, o.dy, 1.0))
              .toList(growable: false),
          color: const Color(0xFF000000),
          width: 4,
          type: BrushType.pen,
        );

    test('strokeBounds 覆盖笔画所有采样点并留出笔宽余量', () {
      final stroke = makeStroke([
        const Offset(10, 10),
        const Offset(50, 60),
        const Offset(90, 30),
      ]);
      final bounds = ElementBounds.strokeBounds(stroke);

      expect(bounds, isNotNull);
      expect(bounds!.left, lessThanOrEqualTo(10));
      expect(bounds.top, lessThanOrEqualTo(10));
      expect(bounds.right, greaterThanOrEqualTo(90));
      expect(bounds.bottom, greaterThanOrEqualTo(60));
    });

    test('shapeBounds 返回形状外接框（含笔触宽度膨胀）', () {
      // ShapeRenderer.bounds 使用 Rect.inflate(strokeWidth + 20)
      // 默认 strokeWidth=3 → inflate(23) → 每边向外扩展 23
      final shape = PageShapeItem(
        id: 's1',
        shapeType: ShapeType.rect,
        x: 40,
        y: 50,
        width: 120,
        height: 80,
      );
      final bounds = ElementBounds.shapeBounds(shape);

      expect(bounds.left, 17); // 40 - 23
      expect(bounds.top, 27); // 50 - 23
      expect(bounds.width, 166); // 120 + 2*23
      expect(bounds.height, 126); // 80 + 2*23
    });

    test('updateAll 批量重建索引：strokes 与 shapes 全部可查', () {
      final index = SpatialIndex();
      final strokes = [
        makeStroke([const Offset(0, 0), const Offset(30, 30)]),
        makeStroke([const Offset(400, 400), const Offset(430, 430)]),
      ];
      final shapes = [
        PageShapeItem(
          id: 'rect1',
          shapeType: ShapeType.rect,
          x: 100,
          y: 100,
        ),
      ];

      ElementBounds.updateAll(index, strokes: strokes, shapes: shapes);

      expect(index.query(const Rect.fromLTWH(0, 0, 32, 32)), contains('stroke_0'));
      expect(
        index.query(const Rect.fromLTWH(400, 400, 32, 32)),
        contains('stroke_1'),
      );
      expect(
        index.query(const Rect.fromLTWH(100, 100, 20, 20)),
        contains('shape_rect1'),
      );

      // layerPrefix 生效
      ElementBounds.updateAll(
        index,
        strokes: strokes,
        shapes: shapes,
        layerPrefix: 'L1/',
      );
      expect(
        index.query(const Rect.fromLTWH(0, 0, 32, 32)),
        contains('L1/stroke_0'),
      );
    });
  });
}
