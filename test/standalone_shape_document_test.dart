import 'dart:convert';
import 'dart:typed_data';

import 'package:drawing_notes_app/features/drawing/domain/document.dart';
import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';
import 'package:drawing_notes_app/features/drawing/infrastructure/document_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('独立绘图文档保存后恢复无限画布与形状集合', () {
    final original = DrawingDocument(
      id: 'shape-doc',
      title: '流程图',
      infinite: true,
      paperType: PaperType.dot,
      shapes: [
        PageShapeItem(
          id: 'arrow-1',
          shapeType: ShapeType.arrow,
          x: -120,
          y: 80,
          width: 260,
          height: 90,
          color: 0xFF3A6EA5,
          strokeWidth: 5,
          flipX: true,
          flipY: false,
        ),
      ],
    );

    final codec = DocumentCodec();
    final restored = codec.decode(codec.encode(original));

    expect(restored.infinite, isTrue);
    expect(restored.paperType, PaperType.dot);
    expect(restored.shapes, hasLength(1));
    final arrow = restored.shapes.single;
    expect(arrow.shapeType, ShapeType.arrow);
    expect(arrow.x, -120);
    expect(arrow.width, 260);
    expect(arrow.strokeWidth, 5);
    expect(arrow.flipX, isTrue);
    expect(arrow.flipY, isFalse);
  });

  test('旧版独立绘图文件不含形状字段时仍可正常打开', () {
    const legacy =
        '{"version":1,"document":{"id":"legacy","title":"旧文件","width":100,"height":80,"layers":[]}}';
    final restored = DocumentCodec().decode(
      Uint8List.fromList(utf8.encode(legacy)),
    );

    expect(restored.infinite, isFalse);
    expect(restored.shapes, isEmpty);
    expect(restored.title, '旧文件');
  });
}
