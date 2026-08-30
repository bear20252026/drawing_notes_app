import 'dart:ui' show Color, Offset;

import 'package:drawing_notes_app/features/drawing/application/document_object_transform_service.dart';
import 'package:drawing_notes_app/core/canvas_model/document_image_item.dart';
import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';
import 'package:drawing_notes_app/core/canvas_model/stroke.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('平移仅变换选中的未锁笔画、形状和图片', () {
    final strokes = <Stroke>[
      Stroke(
        points: const <StrokePoint>[
          StrokePoint(10, 20, 1),
          StrokePoint(20, 30, 0.8),
        ],
        color: const Color(0xFF000000),
        width: 3,
        type: BrushType.pen,
      ),
    ];
    final selectedShape = PageShapeItem(
      id: 'shape',
      shapeType: ShapeType.rect,
      x: 30,
      y: 40,
      width: 50,
      height: 60,
    );
    final lockedShape = PageShapeItem(
      id: 'locked-shape',
      shapeType: ShapeType.ellipse,
      x: 70,
      y: 80,
      locked: true,
    );
    final selectedImage = DocumentImageItem(
      id: 'image',
      x: 90,
      y: 100,
      width: 110,
      height: 120,
      filePath: '/tmp/image.png',
    );
    final lockedImage = DocumentImageItem(
      id: 'locked-image',
      x: 130,
      y: 140,
      filePath: '/tmp/locked.png',
      locked: true,
    );

    DocumentObjectTransformService.transformSelection(
      strokes: strokes,
      selectedStrokeIndices: const <int>[0],
      shapes: <PageShapeItem>[selectedShape, lockedShape],
      selectedShapeIds: const <String>{'shape', 'locked-shape'},
      images: <DocumentImageItem>[selectedImage, lockedImage],
      selectedImageIds: const <String>{'image', 'locked-image'},
      transform: (point) => point + const Offset(7, -5),
      scale: null,
    );

    expect(strokes.single.points.first.offset, const Offset(17, 15));
    expect(strokes.single.points.last.offset, const Offset(27, 25));
    expect(selectedShape.position, const Offset(37, 35));
    expect(selectedImage.position, const Offset(97, 95));
    expect(lockedShape.position, const Offset(70, 80));
    expect(lockedImage.position, const Offset(130, 140));
  });

  test('缩放以调用方变换位置并对形状与图片应用最小尺寸下限', () {
    final shape = PageShapeItem(
      id: 'shape',
      shapeType: ShapeType.rect,
      x: 100,
      y: 120,
      width: 40,
      height: 30,
    );
    final image = DocumentImageItem(
      id: 'image',
      x: 200,
      y: 220,
      width: 100,
      height: 80,
      filePath: '/tmp/image.png',
    );

    DocumentObjectTransformService.transformSelection(
      strokes: <Stroke>[],
      selectedStrokeIndices: const <int>[],
      shapes: <PageShapeItem>[shape],
      selectedShapeIds: const <String>{'shape'},
      images: <DocumentImageItem>[image],
      selectedImageIds: const <String>{'image'},
      transform: (point) => point * 0.1,
      scale: 0.1,
    );

    expect(shape.position, const Offset(10, 12));
    expect(shape.width, 16);
    expect(shape.height, 16);
    expect(image.position, const Offset(20, 22));
    expect(image.width, 32);
    expect(image.height, 24);
  });

  test('可变换判定忽略锁定的形状和图片，但保留笔画选择', () {
    final lockedShape = PageShapeItem(
      id: 'locked-shape',
      shapeType: ShapeType.rect,
      x: 0,
      y: 0,
      locked: true,
    );
    final lockedImage = DocumentImageItem(
      id: 'locked-image',
      x: 0,
      y: 0,
      filePath: '/tmp/locked.png',
      locked: true,
    );

    expect(
      DocumentObjectTransformService.hasTransformableSelection(
        selectedStrokeIndices: const <int>[],
        shapes: <PageShapeItem>[lockedShape],
        selectedShapeIds: const <String>{'locked-shape'},
        images: <DocumentImageItem>[lockedImage],
        selectedImageIds: const <String>{'locked-image'},
      ),
      isFalse,
    );
    expect(
      DocumentObjectTransformService.hasTransformableSelection(
        selectedStrokeIndices: const <int>[0],
        shapes: <PageShapeItem>[lockedShape],
        selectedShapeIds: const <String>{'locked-shape'},
        images: <DocumentImageItem>[lockedImage],
        selectedImageIds: const <String>{'locked-image'},
      ),
      isTrue,
    );
  });
}
