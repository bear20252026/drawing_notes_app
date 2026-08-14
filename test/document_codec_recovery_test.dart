import 'dart:convert';
import 'dart:typed_data';

import 'package:drawing_notes_app/models/shape_item.dart';
import 'package:drawing_notes_app/storage/document_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final codec = DocumentCodec();

  Uint8List documentBytes(Map<String, dynamic> document) => Uint8List.fromList(
    utf8.encode(jsonEncode({'version': 2, 'document': document})),
  );

  test('根结构或文档 ID 无效时拒绝恢复，避免创建身份不明的文档', () {
    expect(
      () => codec.decode(Uint8List.fromList(utf8.encode('[]'))),
      throwsFormatException,
    );
    expect(
      () => codec.decode(documentBytes({'id': '../unsafe'})),
      throwsFormatException,
    );
  });

  test('局部对象损坏不会阻断可靠内容，并会修复失效箭头绑定', () {
    final restored = codec.decode(
      documentBytes({
        'id': 'recovery_doc',
        'title': '恢复测试',
        'width': 999999,
        'height': -5,
        'layers': [
          {
            'id': 'safe_layer',
            'name': '安全图层',
            'opacity': 4,
            'strokes': [
              {
                'points': [
                  {'x': 10, 'y': 20, 'p': 1.5},
                  {'x': 30, 'y': 40, 'p': -0.2},
                ],
                'color': 0xFF102030,
                'width': 6,
                'type': 'pen',
                'opacity': -1,
              },
              {'points': [], 'color': 0xFF000000, 'width': 4, 'type': 'pen'},
              {'points': 'not-a-list'},
            ],
          },
          {'id': 9, 'strokes': []},
          {'id': 'safe_layer', 'strokes': []},
        ],
        'shapes': [
          {
            'id': 'target',
            'shapeType': 'rect',
            'x': 0,
            'y': 0,
            'width': 100,
            'height': 80,
          },
          {
            'id': 'arrow',
            'shapeType': 'arrow',
            'x': 100,
            'y': 0,
            'width': 80,
            'height': 20,
            'startBinding': {
              'targetShapeId': 'target',
              'anchorX': 0.4,
              'anchorY': 0.5,
            },
            'endBinding': {
              'targetShapeId': 'missing',
              'anchorX': 0.8,
              'anchorY': 0.5,
            },
          },
          {
            'id': 'target',
            'shapeType': 'ellipse',
            'x': 200,
            'y': 0,
            'width': 60,
            'height': 60,
          },
          {
            'id': 'oversized',
            'shapeType': 'rect',
            'x': 0,
            'y': 0,
            'width': 9000,
            'height': 40,
          },
          {'id': 'broken', 'shapeType': 'rect'},
        ],
        'imageItems': [
          {
            'id': 'image_valid',
            'x': 10,
            'y': 10,
            'width': 200,
            'height': 100,
            'filePath': '/managed/image.png',
          },
          {
            'id': 'image_valid',
            'x': 10,
            'y': 10,
            'width': 200,
            'height': 100,
            'filePath': '/managed/duplicate.png',
          },
          {
            'id': 'image_invalid',
            'x': 10,
            'y': 10,
            'width': -1,
            'height': 100,
            'filePath': '/managed/invalid.png',
          },
        ],
      }),
    );

    expect(restored.width, 32768);
    expect(restored.height, 16);
    expect(restored.layers, hasLength(1));
    expect(restored.layers.single.opacity, 1);
    expect(restored.layers.single.strokes, hasLength(1));
    expect(restored.layers.single.strokes.single.opacity, 0);
    expect(restored.layers.single.strokes.single.points.first.pressure, 1);
    expect(restored.layers.single.strokes.single.points.last.pressure, 0);

    expect(restored.shapes.map((shape) => shape.id), ['target', 'arrow']);
    final arrow = restored.shapes.singleWhere((shape) => shape.id == 'arrow');
    expect(arrow.shapeType, ShapeType.arrow);
    expect(arrow.startBinding?.targetShapeId, 'target');
    expect(arrow.endBinding, isNull);

    expect(restored.imageItems, hasLength(1));
    expect(restored.imageItems.single.id, 'image_valid');
  });

  test('完全无效的可选集合会安全退化为默认图层', () {
    final restored = codec.decode(
      documentBytes({
        'id': 'fallback_layer',
        'layers': [
          null,
          {'id': '', 'strokes': []},
        ],
        'shapes': 'invalid',
        'imageItems': 'invalid',
      }),
    );

    expect(restored.layers, hasLength(1));
    expect(restored.layers.single.id, 'layer_1');
    expect(restored.shapes, isEmpty);
    expect(restored.imageItems, isEmpty);
  });
}
