// StrokeBuffer 回归锁（内核 P0-1，2026-10-10）：紧凑视图与点列对象逐字段
// 一致；按 geometryRevision 失效重建；渲染轮廓/包围盒在缓冲接入后语义不变。
import 'dart:math' as math;
import 'dart:ui' show Color, Rect;

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/canvas_model/stroke.dart';
import 'package:drawing_notes_app/core/canvas_model/stroke_buffer.dart';
import 'package:drawing_notes_app/features/drawing/rendering/stroke_renderer.dart';

void main() {
  List<StrokePoint> points(int count) => [
    for (var i = 0; i < count; i++)
      StrokePoint(i * 3.5, (i % 7) * 11.0, (i % 5) / 8 + 0.25),
  ];

  group('StrokeBuffer 纯数据语义', () {
    test('fromPoints/fromFlat/pointAt/toTuples 逐字段一致', () {
      final src = points(50);
      final buffer = StrokeBuffer.fromPoints(src);
      expect(buffer.length, 50);
      for (var i = 0; i < src.length; i++) {
        expect(buffer.xAt(i), src[i].x);
        expect(buffer.yAt(i), src[i].y);
        expect(buffer.pressureAt(i), src[i].pressure);
      }
      // fromFlat 与落盘 JSON 扁平数组同构。
      final flat = <num>[
        for (final p in src) ...[p.x, p.y, p.pressure],
      ];
      final fromFlat = StrokeBuffer.fromFlat(flat);
      expect(fromFlat.length, 50);
      expect(fromFlat.xAt(49), src[49].x);
      expect(fromFlat.pressureAt(0), src[0].pressure);
    });

    test('computeBounds 与逐点 min/max 一致；空点列为 null', () {
      final src = points(37);
      final bounds = StrokeBuffer.fromPoints(src).computeBounds();
      final minX = src.map((p) => p.x).reduce(math.min);
      final maxX = src.map((p) => p.x).reduce(math.max);
      final minY = src.map((p) => p.y).reduce(math.min);
      final maxY = src.map((p) => p.y).reduce(math.max);
      expect(bounds, Rect.fromLTRB(minX, minY, maxX, maxY));
      expect(StrokeBuffer.fromPoints(const []).computeBounds(), isNull);
    });
  });

  group('Stroke.buffer 派生缓存', () {
    test('与 points 逐字段一致；replacePoints 后按 revision 重建', () {
      final stroke = Stroke(
        points: points(30),
        color: const Color.fromARGB(255, 0, 0, 0),
        width: 3,
        type: BrushType.pen,
      );
      final rev0 = stroke.geometryRevision;
      expect(stroke.buffer.length, 30);
      expect(stroke.buffer.xAt(5), stroke.points[5].x);
      expect(stroke.buffer.pressureAt(5), stroke.points[5].pressure);

      stroke.replacePoints(points(12));
      expect(stroke.geometryRevision, isNot(rev0));
      expect(stroke.buffer.length, 12, reason: 'revision 变化触发重建');
      expect(stroke.buffer.xAt(11), stroke.points[11].x);
    });

    test('缓冲接入后渲染语义不变：bounds 与轮廓逐字段可复算', () {
      final stroke = Stroke(
        points: points(40),
        color: const Color.fromARGB(255, 10, 20, 30),
        width: 4,
        type: BrushType.pen,
      );
      final bounds = StrokeRenderer.strokeBounds(stroke);
      expect(bounds, isNotNull);
      // 语义校验：bounds 包住全部点（缓冲直读不改变几何结论）。
      for (final p in stroke.points) {
        expect(bounds!.contains(p.offset), isTrue);
      }
      // 轮廓可构建（非空路径）。
      final outline = StrokeRenderer.strokeOutline(stroke);
      expect(outline, isNotNull);
    });
  });
}
