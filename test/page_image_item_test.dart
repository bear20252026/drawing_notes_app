import 'package:drawing_notes_app/core/canvas_model/page_image_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('分页图片模型保持既有 JSON 字段与可选元数据', () {
    final item = PageImageItem(
      id: 'image-1',
      x: 12.5,
      y: 24.5,
      filePath: '/managed/image.png',
      width: 360,
      height: 240,
      zOrder: 7,
      groupId: 'group-1',
      href: 'https://example.com',
      fractionalIndex: 'a1',
    );

    final restored = PageImageItem.fromJson(item.toJson());

    expect(restored.id, 'image-1');
    expect(restored.position.dx, 12.5);
    expect(restored.position.dy, 24.5);
    expect(restored.filePath, '/managed/image.png');
    expect(restored.width, 360);
    expect(restored.height, 240);
    expect(restored.zOrder, 7);
    expect(restored.groupId, 'group-1');
    expect(restored.href, 'https://example.com');
    expect(restored.fractionalIndex, 'a1');
  });

  test('旧图片 JSON 缺少可选字段时维持原有默认值', () {
    final restored = PageImageItem.fromJson({
      'id': 'legacy-image',
      'x': 1,
      'y': 2,
      'filePath': '/managed/legacy.png',
    });

    expect(restored.width, 200);
    expect(restored.height, 150);
    expect(restored.zOrder, 0);
    expect(restored.groupId, isNull);
    expect(restored.href, isNull);
    expect(restored.fractionalIndex, isNull);
  });
}
