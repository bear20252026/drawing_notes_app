import 'package:drawing_notes_app/engine/drawing_controller.dart';
import 'package:drawing_notes_app/models/document.dart';
import 'package:drawing_notes_app/models/document_image_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DrawingController makeController() {
    final document = DrawingDocument(
      id: 'image_edit',
      title: '图片对象编辑',
      infinite: true,
      imageItems: [
        DocumentImageItem(
          id: 'image_1',
          x: 100,
          y: 80,
          width: 240,
          height: 120,
          zOrder: 3,
          filePath: '/stable/assets/image_1.png',
        ),
      ],
    );
    return DrawingController(document);
  }

  test('图片命中选择取最上层对象且不依赖解码位图', () {
    final controller = makeController();
    controller.document.imageItems.add(
      DocumentImageItem(
        id: 'image_top',
        x: 120,
        y: 100,
        width: 80,
        height: 60,
        zOrder: 8,
        filePath: '/stable/assets/image_top.png',
      ),
    );

    final hit = controller.selectDocumentImageAt(const Offset(150, 120));

    expect(hit?.id, 'image_top');
    expect(controller.selectedDocumentImageId, 'image_top');
  });

  test('图片拖动以一条历史记录完成撤销和重做', () {
    final controller = makeController();
    controller.selectDocumentImageAt(const Offset(120, 100));

    controller.moveSelectedDocumentImage(const Offset(30, -20));
    controller.moveSelectedDocumentImage(const Offset(10, 5));
    controller.endDocumentImageTransform();

    final image = controller.document.imageItems.single;
    expect(image.position, const Offset(140, 65));
    expect(controller.canUndo, isTrue);

    controller.undo();
    expect(
      controller.document.imageItems.single.position,
      const Offset(100, 80),
    );
    expect(controller.canRedo, isTrue);

    controller.redo();
    expect(
      controller.document.imageItems.single.position,
      const Offset(140, 65),
    );
  });

  test('图片缩放围绕自身中心且可撤销', () {
    final controller = makeController();
    controller.selectDocumentImageAt(const Offset(120, 100));
    final originalCenter = controller.document.imageItems.single.bounds.center;

    controller.scaleSelectedDocumentImage(0.5);
    controller.endDocumentImageTransform();

    final image = controller.document.imageItems.single;
    expect(image.width, 120);
    expect(image.height, 60);
    expect(image.bounds.center, originalCenter);

    controller.undo();
    expect(controller.document.imageItems.single.width, 240);
    expect(controller.document.imageItems.single.height, 120);
  });

  test('删除图片可撤销恢复原始资源引用与层级', () {
    final controller = makeController();
    controller.selectDocumentImageAt(const Offset(120, 100));

    controller.deleteSelectedDocumentImage();
    expect(controller.document.imageItems, isEmpty);

    controller.undo();
    final restored = controller.document.imageItems.single;
    expect(restored.filePath, '/stable/assets/image_1.png');
    expect(restored.zOrder, 3);
    expect(restored.bounds, const Rect.fromLTWH(100, 80, 240, 120));

    controller.redo();
    expect(controller.document.imageItems, isEmpty);
  });

  test('取消图片拖动会恢复到手势前状态且不写入历史', () {
    final controller = makeController();
    controller.selectDocumentImageAt(const Offset(120, 100));

    controller.moveSelectedDocumentImage(const Offset(80, 40));
    controller.cancelDocumentImageTransform();

    expect(
      controller.document.imageItems.single.position,
      const Offset(100, 80),
    );
    expect(controller.canUndo, isFalse);
  });

  test('清除选区同时清除独立图片选择', () {
    final controller = makeController();
    controller.selectDocumentImageAt(const Offset(120, 100));
    expect(controller.hasSelectedDocumentImage, isTrue);

    controller.clearSelection();

    expect(controller.hasSelectedDocumentImage, isFalse);
  });

  test('锁定图片可撤销且会阻止移动、缩放和删除', () {
    final controller = makeController();
    controller.selectDocumentImageAt(const Offset(120, 100));

    controller.toggleSelectedDocumentImageLock();
    final image = controller.document.imageItems.single;
    expect(image.locked, isTrue);
    expect(image.toJson()['locked'], isTrue);

    controller.moveSelectedDocumentImage(const Offset(40, 20));
    controller.scaleSelectedDocumentImage(2);
    controller.deleteSelectedDocumentImage();
    expect(image.bounds, const Rect.fromLTWH(100, 80, 240, 120));
    expect(controller.document.imageItems, hasLength(1));

    controller.undo();
    expect(controller.document.imageItems.single.locked, isFalse);
    controller.redo();
    expect(controller.document.imageItems.single.locked, isTrue);
  });
}
