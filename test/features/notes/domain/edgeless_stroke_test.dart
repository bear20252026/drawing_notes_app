// M11 契约测试：Edgeless 笔迹/形状领域模型 + EdgelessDoc 扩展。
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart' show Offset, Size;

import 'package:drawing_notes_app/features/notes/domain/edgeless_doc.dart';
import 'package:drawing_notes_app/features/notes/domain/edgeless_stroke.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block_doc.dart';

void main() {
  group('EdgelessStroke', () {
    test('点列存取与追加（不可变）', () {
      final s = EdgelessStroke(
        id: 's1',
        points: [0, 0, 10, 10],
        color: '#1D1D1F',
        width: 3,
      );
      expect(s.pointCount, 2);
      final s2 = s.copyWithAppended(const Offset(20, 20));
      expect(s2.pointCount, 3);
      expect(s.pointCount, 2); // 原实例不变
    });

    test('hitTest：线段附近命中，远处不命中', () {
      final s = EdgelessStroke(
        id: 's1',
        points: [0, 0, 100, 0],
        color: '#000000',
        width: 3,
      );
      expect(s.hitTest(const Offset(50, 4), tolerance: 6), isTrue);
      expect(s.hitTest(const Offset(50, 50), tolerance: 6), isFalse);
      // 单点笔迹：按距离命中。
      final dot = EdgelessStroke(
        id: 's2',
        points: [10, 10],
        color: '#000000',
        width: 3,
      );
      expect(dot.hitTest(const Offset(12, 12), tolerance: 6), isTrue);
    });

    test('JSON 往返一致', () {
      final s = EdgelessStroke(
        id: 's1',
        points: [1.5, 2.5, 3.5, 4.5],
        color: '#0066CC',
        width: 2.5,
      );
      final back = EdgelessStroke.fromJson(s.toJson());
      expect(back, s);
    });
  });

  group('EdgelessShape', () {
    test('JSON 往返一致 + kind 回退', () {
      final e = EdgelessShape(
        id: 'e1',
        x: 0,
        y: 0,
        w: 100,
        h: 50,
        kind: EdgelessShapeKind.ellipse,
        color: '#330066CC',
      );
      expect(EdgelessShape.fromJson(e.toJson()), e);
      final fallback = EdgelessShape.fromJson({
        'id': 'e2',
        'x': 0,
        'y': 0,
        'w': 1,
        'h': 1,
      });
      expect(fallback.kind, EdgelessShapeKind.rect);
    });
  });

  group('EdgelessDoc 笔迹/形状操作', () {
    late EdgelessDoc doc;
    setUp(() {
      doc = EdgelessDoc.empty('edoc');
    });

    test('addStroke / removeStroke', () {
      final stroke = EdgelessStroke(
        id: 'a',
        points: [0, 0, 5, 5],
        color: '#000000',
        width: 2,
      );
      final withStroke = doc.addStroke(stroke);
      expect(withStroke.strokes.length, 1);
      final removed = withStroke.removeStroke('a');
      expect(removed.strokes, isEmpty);
      expect(withStroke.removeStroke('not-exist'), same(withStroke));
    });

    test('addShape / removeShape', () {
      final shape = EdgelessShape(
        id: 'sh1',
        x: 0,
        y: 0,
        w: 10,
        h: 10,
        kind: EdgelessShapeKind.rect,
        color: '#330066CC',
      );
      final withShape = doc.addShape(shape);
      expect(withShape.shapes.length, 1);
      expect(withShape.removeShape('sh1').shapes, isEmpty);
    });

    test('eraseAt 擦除命中的笔迹（后添加优先）', () {
      final s1 = EdgelessStroke(
        id: 'a',
        points: [0, 0, 100, 0],
        color: '#000000',
        width: 3,
      );
      final s2 = EdgelessStroke(
        id: 'b',
        points: [0, 50, 100, 50],
        color: '#000000',
        width: 3,
      );
      final d = doc.addStroke(s1).addStroke(s2);
      final after = d.eraseAt(const Offset(50, 51), tolerance: 8);
      expect(after.strokes.map((e) => e.id), ['a']);
      // 未命中返回同一实例
      expect(d.eraseAt(const Offset(50, 500)), same(d));
    });

    test('eraseAt 擦除命中的形状', () {
      final shape = EdgelessShape(
        id: 'sh1',
        x: 0,
        y: 0,
        w: 100,
        h: 100,
        kind: EdgelessShapeKind.rect,
        color: '#330066CC',
      );
      final d = doc.addShape(shape);
      expect(d.eraseAt(const Offset(50, 50)).shapes, isEmpty);
    });

    test('序列化：strokes/shapes 进出 JSON', () {
      final d = doc
          .addStroke(
            EdgelessStroke(
              id: 'a',
              points: [0, 0, 5, 5],
              color: '#000000',
              width: 2,
            ),
          )
          .addShape(
            EdgelessShape(
              id: 'sh1',
              x: 0,
              y: 0,
              w: 10,
              h: 10,
              kind: EdgelessShapeKind.ellipse,
              color: '#330066CC',
            ),
          );
      final back = EdgelessDoc.fromJson(d.toJson());
      expect(back.strokes, d.strokes);
      expect(back.shapes, d.shapes);
      expect(back, d);
    });

    test('addFrame 支持 size（便签小尺寸）', () {
      final withSticky = doc.addFrame(
        NoteBlockDoc.empty('sticky-1', title: '便签'),
        at: const Offset(10, 10),
        size: const Size(220, 220),
      );
      expect(withSticky.frames.last.w, 220);
      expect(withSticky.frames.last.h, 220);
    });
  });
}
