// U2 画布性能批次（2026-09-02）测试：视口剔除 + 包围盒缓存 + isolate 编码。
//
// 覆盖 P1-8（InkLayerPainter.cullStrokes / StrokeRenderer.strokeBounds 缓存）
// 与 P1-10（DocumentCodec.encodeSnapshotAsync 与同步 encode 字节一致）。

import 'dart:ui' show Color, Rect;

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/layer.dart';
import 'package:drawing_notes_app/core/canvas_model/stroke.dart';
import 'package:drawing_notes_app/core/storage/document_codec.dart';
import 'package:drawing_notes_app/features/drawing/rendering/ink_layer_painter.dart';
import 'package:drawing_notes_app/features/drawing/rendering/stroke_renderer.dart';
import 'package:drawing_notes_app/shared/utils/image_decode_cap.dart';

Stroke _stroke({
  required List<StrokePoint> points,
  BrushType type = BrushType.pen,
}) {
  return Stroke(
    points: points,
    color: const Color(0xFF222222),
    width: 6,
    type: type,
  );
}

void main() {
  group('ImageDecodeCap.targetSize（P1-13 降采样目标尺寸）', () {
    test('小图不放大', () {
      final t = ImageDecodeCap.targetSize(800, 600, 2048);
      expect(t.width, 800);
      expect(t.height, 600);
    });

    test('横图长边超限按比例缩', () {
      final t = ImageDecodeCap.targetSize(4000, 2000, 2048);
      expect(t.width, 2048);
      expect(t.height, 1024);
    });

    test('竖图长边超限按比例缩', () {
      final t = ImageDecodeCap.targetSize(1000, 3000, 2048);
      expect(t.width, 683); // 1000 * 2048/3000 = 682.67 → 683
      expect(t.height, 2048);
    });

    test('零尺寸防御性原样返回', () {
      final t = ImageDecodeCap.targetSize(0, 0, 2048);
      expect(t.width, 0);
      expect(t.height, 0);
    });
  });

  group('InkLayerPainter.cullStrokes（P1-8 视口剔除）', () {
    test('视口内笔画保留、视口外剔除、空点列剔除', () {
      final inside = _stroke(
        points: const [StrokePoint(100, 100, 1), StrokePoint(120, 120, 1)],
      );
      final outside = _stroke(
        points: const [StrokePoint(5000, 5000, 1), StrokePoint(5100, 5100, 1)],
      );
      final empty = _stroke(points: const []);

      final visible = InkLayerPainter.cullStrokes(
        [inside, outside, empty],
        const Rect.fromLTWH(0, 0, 640, 480),
      );

      expect(visible, hasLength(1));
      expect(visible.single, same(inside));
    });

    test('部分相交的笔画保留（粗笔越界不被裁掉）', () {
      final crossing = _stroke(
        points: const [StrokePoint(600, 100, 1), StrokePoint(700, 100, 1)],
      );
      final visible = InkLayerPainter.cullStrokes(
        [crossing],
        const Rect.fromLTWH(0, 0, 640, 480),
      );
      expect(visible, hasLength(1));
    });
  });

  group('StrokeRenderer.strokeBounds 缓存（P1-8）', () {
    test('同一几何版本重复查询结果一致', () {
      final stroke = _stroke(
        points: const [StrokePoint(10, 10, 1), StrokePoint(200, 60, 1)],
      );
      final a = StrokeRenderer.strokeBounds(stroke)!;
      final b = StrokeRenderer.strokeBounds(stroke)!;
      expect(a, b);
      expect(a.left, lessThan(10));
      expect(a.right, greaterThan(200));
    });

    test('点列替换后（geometryRevision 递增）包围盒随之更新', () {
      final stroke = _stroke(
        points: [
          const StrokePoint(10, 10, 1),
          const StrokePoint(200, 60, 1),
        ],
      );
      final before = StrokeRenderer.strokeBounds(stroke)!;

      stroke.replacePoints([
        const StrokePoint(1000, 1000, 1),
        const StrokePoint(1200, 1040, 1),
      ]);

      final after = StrokeRenderer.strokeBounds(stroke)!;
      expect(after, isNot(before));
      expect(after.left, greaterThan(900));
    });
  });

  group('DocumentCodec isolate 编码（P1-10）', () {
    test('encodeSnapshotAsync 与同步 encode 输出字节一致（小文档主线程路径）', () async {
      final doc = _docWithStrokes(3);
      final codec = const DocumentCodec();
      final syncBytes = codec.encode(doc);
      final asyncBytes = await DocumentCodec.encodeSnapshotAsync(
        DocumentCodec.snapshotOf(doc),
      );
      expect(asyncBytes, syncBytes);
    });

    test('大文档走 isolate 路径仍与同步 encode 字节一致', () async {
      final doc = _docWithStrokes(DocumentCodec.isolateEncodeThreshold + 10);
      final codec = const DocumentCodec();
      final syncBytes = codec.encode(doc);
      final asyncBytes = await DocumentCodec.encodeSnapshotAsync(
        DocumentCodec.snapshotOf(doc),
      );
      expect(asyncBytes, syncBytes);
    });
  });
}

DrawingDocument _docWithStrokes(int strokeCount) {
  final strokes = List<Stroke>.generate(strokeCount, (i) {
    return Stroke(
      points: [
        StrokePoint(10.0 + i, 10.0, 1),
        StrokePoint(110.0 + i, 80.0, 1),
      ],
      color: const Color(0xFF111111),
      width: 4,
      type: BrushType.pen,
    );
  });
  final doc = DrawingDocument(
    id: 'u2codec',
    title: 'U2 isolate 编码测试',
    width: 640,
    height: 480,
  );
  doc.layers.add(
    Layer(id: 'layer-u2', name: '图层 1', strokes: strokes),
  );
  return doc;
}
