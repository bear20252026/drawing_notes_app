import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/stroke.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';

/// S3 实体纯净化验证：domain 实体不依赖 Widget/Context/渲染对象，
/// toJson/fromJson 往返在纯逻辑环境（无 UI 渲染）下即可完成。
void main() {
  group('S3 domain 实体纯逻辑可测性', () {
    test('Document 实体往返：纯数据不依赖渲染', () {
      final doc = DrawingDocument(id: 'd1', title: '纯逻辑');
      final restored = DrawingDocument.fromJson(doc.toJson());
      expect(restored.id, 'd1');
      expect(restored.title, '纯逻辑');
      expect(restored.layers.length, doc.layers.length);
    });

    test('Stroke 实体往返：点列/颜色/宽度纯 Dart 数据', () {
      final stroke = Stroke(
        points: const [StrokePoint(1, 2, 0.5), StrokePoint(3, 4, 0.9)],
        color: const Color(0xFF112233),
        width: 3.5,
        type: BrushType.pen,
      );
      final restored = Stroke.fromJson(stroke.toJson());
      expect(restored.points.length, 2);
      expect(restored.points.first.x, 1);
      expect(restored.points.first.pressure, 0.5);
      expect(restored.width, 3.5);
      expect(restored.type, BrushType.pen);
    });

    test('PageTextItem 往返：字号/样式纯 Dart 字段', () {
      final item = PageTextItem(
        id: 't1',
        x: 10,
        y: 20,
        text: '你好',
        fontSize: 24,
        bold: true,
        color: 0xFF112233,
      );
      final restored = PageTextItem.fromJson(item.toJson());
      expect(restored.text, '你好');
      expect(restored.fontSize, 24);
      expect(restored.bold, true);
      expect(restored.position.dx, 10);
      expect(restored.position.dy, 20);
    });

    test('PageShapeItem 往返：形状类型/端点纯 Dart 数据', () {
      final shape = PageShapeItem(
        id: 's1',
        shapeType: ShapeType.rect,
        x: 0,
        y: 0,
        width: 100,
        height: 50,
      );
      final restored = PageShapeItem.fromJson(shape.toJson());
      expect(restored.shapeType, ShapeType.rect);
      expect(restored.width, 100);
      expect(restored.height, 50);
    });

    test('Notebook 实体往返：页面元数据不依赖 UI', () {
      final nb = Notebook(id: 'n1', title: '笔记本');
      final restored = Notebook.fromJson(nb.toJson());
      expect(restored.id, 'n1');
      expect(restored.title, '笔记本');
    });
  });
}
