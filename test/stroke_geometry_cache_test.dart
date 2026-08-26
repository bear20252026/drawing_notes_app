/// StrokeGeometryCache 单元测试（2026-08-25）
library;

import 'package:drawing_notes_app/infrastructure/rendering/stroke_geometry_cache.dart';
import 'package:drawing_notes_app/features/drawing/domain/stroke.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  StrokePoint makePoint(double x, double y, [double pressure = 0.5]) =>
      StrokePoint(x, y, pressure);

  group('StrokeGeometryCache 初始化', () {
    test('初始状态包含第一个点', () {
      final cache = StrokeGeometryCache(makePoint(10, 20));
      expect(cache.previewPoints.length, 1);
      expect(cache.previewPoints[0].x, 10);
      expect(cache.rawPointCount, 1);
    });

    test('currentSpeed 初始为 0', () {
      final cache = StrokeGeometryCache(makePoint(0, 0));
      expect(cache.currentSpeed, 0);
    });
  });

  group('StrokeGeometryCache.append', () {
    test('远距离点增加预览点', () {
      final cache = StrokeGeometryCache(makePoint(0, 0));
      cache.append(makePoint(10, 10)); // 距离 ≈ 14 > previewSpacing (1.5)
      expect(cache.previewPoints.length, 2);
      expect(cache.rawPointCount, 2);
    });

    test('近距离点不增加预览点但更新末端', () {
      final cache = StrokeGeometryCache(makePoint(0, 0));
      cache.append(makePoint(0.1, 0.1)); // 距离 ≈ 0.14 < 1.5
      expect(cache.previewPoints.length, 1);
      expect(cache.rawPointCount, 2);
      // 末端被更新
      expect(cache.previewPoints[0].x, 0.1);
    });

    test('压感变化强制添加点', () {
      final cache = StrokeGeometryCache(makePoint(0, 0));
      cache.append(makePoint(0.1, 0.1, 0.8)); // 压感差 0.3 > 0.015
      expect(cache.previewPoints.length, 2);
    });

    test('相同压感近距离不添加', () {
      final cache = StrokeGeometryCache(makePoint(0, 0));
      cache.append(makePoint(0.5, 0.5)); // 近距离、相同压感
      expect(cache.previewPoints.length, 1);
    });

    test('大量点正确追加原始数据', () {
      final cache = StrokeGeometryCache(makePoint(0, 0));
      for (var i = 1; i <= 100; i++) {
        cache.append(makePoint(i * 5.0, 0));
      }
      expect(cache.rawPointCount, 101);
    });
  });

  group('StrokeGeometryCache.finish', () {
    test('单点返回原列表', () {
      final cache = StrokeGeometryCache(makePoint(5, 5));
      final result = cache.finish();
      expect(result.length, 1);
    });

    test('两点返回两点', () {
      final cache = StrokeGeometryCache(makePoint(0, 0));
      cache.append(makePoint(10, 10));
      final result = cache.finish();
      expect(result.length, 2);
    });

    test('三点以上去重压缩', () {
      final cache = StrokeGeometryCache(makePoint(0, 0));
      // 添加密集点（距离 < finalSpacing）
      for (var i = 1; i <= 20; i++) {
        cache.append(makePoint(i * 0.01, 0));
      }
      // 再添加远点
      cache.append(makePoint(100, 0));
      final result = cache.finish();
      expect(result.length, lessThan(22));
      // 首点和尾点必须保留
      expect(result.first.x, 0);
      expect(result.last.x, 100);
    });

    test('压感变化即使距离近也保留', () {
      final cache = StrokeGeometryCache(makePoint(0, 0, 0.3));
      cache.append(makePoint(0.01, 0, 0.3));
      cache.append(makePoint(0.02, 0, 0.9)); // 压感突变
      cache.append(makePoint(100, 0, 0.9));
      final result = cache.finish();
      // 压感变化点应保留
      expect(result.length, greaterThanOrEqualTo(3));
    });

    test('finish 不影响 previewPoints', () {
      final cache = StrokeGeometryCache(makePoint(0, 0));
      cache.append(makePoint(10, 10));
      final previewLen = cache.previewPoints.length;
      cache.finish();
      expect(cache.previewPoints.length, previewLen);
    });
  });

  group('StrokeGeometryCache.speedWidthFactor', () {
    test('低于参考速度返回 1.0', () {
      expect(StrokeGeometryCache.speedWidthFactor(0), 1.0);
      expect(StrokeGeometryCache.speedWidthFactor(0.5), 1.0);
      expect(StrokeGeometryCache.speedWidthFactor(0.8), 1.0);
    });

    test('高于参考速度线性减细', () {
      final factor = StrokeGeometryCache.speedWidthFactor(1.6);
      expect(factor, lessThan(1.0));
      expect(factor, greaterThan(0.0));
    });

    test('极高速度不低于最小系数', () {
      final factor = StrokeGeometryCache.speedWidthFactor(100);
      expect(factor, greaterThanOrEqualTo(StrokeGeometryCache.speedMinWidthFactor));
    });

    test('精确参考速度返回 1.0', () {
      expect(StrokeGeometryCache.speedWidthFactor(StrokeGeometryCache.referenceSpeed), 1.0);
    });
  });

  group('StrokeGeometryCache 常量', () {
    test('previewSpacing > finalSpacing', () {
      expect(
        StrokeGeometryCache.previewSpacing,
        greaterThan(StrokeGeometryCache.finalSpacing),
      );
    });

    test('pressureTolerance 合理', () {
      expect(StrokeGeometryCache.pressureTolerance, greaterThan(0));
      expect(StrokeGeometryCache.pressureTolerance, lessThan(1));
    });

    test('speedMinWidthFactor 在 0~1 范围', () {
      expect(StrokeGeometryCache.speedMinWidthFactor, greaterThan(0));
      expect(StrokeGeometryCache.speedMinWidthFactor, lessThan(1));
    });
  });
}
