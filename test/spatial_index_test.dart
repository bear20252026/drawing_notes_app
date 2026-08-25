/// SpatialIndex 单元测试（2026-08-25）
library;

import 'dart:ui';

import 'package:drawing_notes_app/features/drawing/application/spatial_index.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SpatialIndex 初始化', () {
    test('默认 cellSize 为 64', () {
      final index = SpatialIndex();
      expect(index.cellSize, 64.0);
    });

    test('自定义 cellSize', () {
      final index = SpatialIndex(cellSize: 32);
      expect(index.cellSize, 32);
    });

    test('空索引 query 返回空', () {
      final index = SpatialIndex();
      final result = index.query(const Rect.fromLTRB(0, 0, 100, 100));
      expect(result, isEmpty);
    });
  });

  group('SpatialIndex.insert', () {
    test('插入单个元素可查询', () {
      final index = SpatialIndex();
      index.insert('a', const Rect.fromLTWH(10, 10, 50, 50));
      final result = index.query(const Rect.fromLTWH(0, 0, 100, 100));
      expect(result, contains('a'));
    });

    test('插入多个元素', () {
      final index = SpatialIndex();
      index.insert('a', const Rect.fromLTWH(0, 0, 50, 50));
      index.insert('b', const Rect.fromLTWH(100, 100, 50, 50));
      index.insert('c', const Rect.fromLTWH(30, 30, 50, 50));

      final result = index.query(const Rect.fromLTWH(0, 0, 40, 40));
      expect(result, contains('a'));
      expect(result, contains('c'));
      expect(result, isNot(contains('b')));
    });

    test('debugGrid 包含插入的元素', () {
      final index = SpatialIndex();
      index.insert('x', const Rect.fromLTWH(0, 0, 10, 10));
      expect(index.debugGrid, isNotEmpty);
    });
  });

  group('SpatialIndex.remove', () {
    test('移除后查询不到', () {
      final index = SpatialIndex();
      index.insert('a', const Rect.fromLTWH(10, 10, 50, 50));
      index.remove('a');
      final result = index.query(const Rect.fromLTWH(0, 0, 100, 100));
      expect(result, isEmpty);
    });

    test('移除不存在的元素不崩溃', () {
      final index = SpatialIndex();
      expect(() => index.remove('nonexistent'), returnsNormally);
    });

    test('移除后网格被清理', () {
      final index = SpatialIndex();
      index.insert('a', const Rect.fromLTWH(0, 0, 10, 10));
      index.remove('a');
      expect(index.debugGrid, isEmpty);
    });
  });

  group('SpatialIndex.query', () {
    test('查询不重叠区域返回空', () {
      final index = SpatialIndex();
      index.insert('a', const Rect.fromLTWH(0, 0, 50, 50));
      final result = index.query(const Rect.fromLTWH(200, 200, 50, 50));
      expect(result, isEmpty);
    });

    test('查询包含区域返回所有重叠元素', () {
      final index = SpatialIndex();
      index.insert('a', const Rect.fromLTWH(10, 10, 20, 20));
      index.insert('b', const Rect.fromLTWH(30, 30, 20, 20));
      index.insert('c', const Rect.fromLTWH(200, 200, 20, 20));

      final result = index.query(const Rect.fromLTWH(0, 0, 60, 60));
      expect(result.length, 2);
      expect(result, contains('a'));
      expect(result, contains('b'));
      expect(result, isNot(contains('c')));
    });

    test('边界相交被正确检测', () {
      final index = SpatialIndex();
      index.insert('edge', const Rect.fromLTWH(50, 50, 50, 50));
      // 查询区域完全不重叠
      final result = index.query(const Rect.fromLTWH(0, 0, 10, 10));
      expect(result, isEmpty);

      // 查询区域与元素有交集
      final result2 = index.query(const Rect.fromLTWH(40, 40, 20, 20));
      expect(result2, contains('edge'));
    });

    test('跨网格单元的大元素正确查询', () {
      final index = SpatialIndex(cellSize: 32);
      // 一个大矩形跨越多个网格单元
      index.insert('big', const Rect.fromLTWH(0, 0, 128, 128));
      final result = index.query(const Rect.fromLTWH(100, 100, 10, 10));
      expect(result, contains('big'));
    });
  });

  group('SpatialIndex.queryPoint', () {
    test('点命中元素', () {
      final index = SpatialIndex();
      index.insert('a', const Rect.fromLTWH(10, 10, 50, 50));
      expect(index.queryPoint(const Offset(25, 25)), contains('a'));
    });

    test('点在元素外', () {
      final index = SpatialIndex();
      index.insert('a', const Rect.fromLTWH(10, 10, 50, 50));
      expect(index.queryPoint(const Offset(100, 100)), isEmpty);
    });
  });

  group('SpatialIndex.boundsFor', () {
    test('返回已插入元素的边界', () {
      final index = SpatialIndex();
      const bounds = Rect.fromLTWH(10, 20, 30, 40);
      index.insert('x', bounds);
      expect(index.boundsFor('x'), bounds);
    });

    test('不存在的元素返回 null', () {
      final index = SpatialIndex();
      expect(index.boundsFor('nope'), isNull);
    });
  });

  group('SpatialIndex.clear', () {
    test('清空后所有查询返回空', () {
      final index = SpatialIndex();
      index.insert('a', const Rect.fromLTWH(0, 0, 50, 50));
      index.insert('b', const Rect.fromLTWH(50, 50, 50, 50));
      index.clear();
      expect(index.query(const Rect.fromLTWH(0, 0, 200, 200)), isEmpty);
      expect(index.debugGrid, isEmpty);
    });
  });

  group('SpatialIndex 负坐标', () {
    test('负坐标元素正确处理', () {
      final index = SpatialIndex();
      index.insert('neg', const Rect.fromLTWH(-100, -100, 50, 50));
      final result = index.query(const Rect.fromLTWH(-150, -150, 200, 200));
      expect(result, contains('neg'));
    });

    test('跨原点矩形', () {
      final index = SpatialIndex();
      index.insert('cross', const Rect.fromLTWH(-20, -20, 40, 40));
      expect(index.queryPoint(const Offset(0, 0)), contains('cross'));
    });
  });
}
