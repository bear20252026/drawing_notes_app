import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/document_image_item.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('document_image_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('独立文档图片会复制为离线副本，并在保存重开后完整恢复', () async {
    final storage = StorageService(directoryProvider: () async => tempDir);
    final source = File('${tempDir.path}${Platform.pathSeparator}source.png');
    await source.writeAsBytes(_tinyPng());

    final storedPath = await storage.storeImage(source.path, 'doc_image');
    expect(storedPath, isNot(source.path));
    expect(await File(storedPath).exists(), isTrue);
    expect(await File(storedPath).readAsBytes(), await source.readAsBytes());

    final document = DrawingDocument(
      id: 'doc_image',
      title: '图片画布',
      imageItems: [
        DocumentImageItem(
          id: 'image_1',
          x: 120,
          y: 80,
          width: 320,
          height: 180,
          zOrder: 3,
          locked: true,
          filePath: storedPath,
        ),
      ],
    );
    await storage.save(document);

    final restored = await storage.load(document.id);
    expect(restored, isNotNull);
    expect(restored!.imageItems, hasLength(1));
    final image = restored.imageItems.single;
    expect(image.id, 'image_1');
    expect(image.filePath, storedPath);
    expect(image.x, 120);
    expect(image.y, 80);
    expect(image.width, 320);
    expect(image.height, 180);
    expect(image.zOrder, 3);
    expect(image.locked, isTrue);
  });

  test('导入图片参与无限画布边界与 PNG 导出', () async {
    final source = File('${tempDir.path}${Platform.pathSeparator}image.png');
    await source.writeAsBytes(_tinyPng());
    final document = DrawingDocument(
      id: 'image_export',
      title: '图片导出',
      infinite: true,
      imageItems: [
        DocumentImageItem(
          id: 'image_export_1',
          x: -150,
          y: 220,
          width: 360,
          height: 180,
          filePath: source.path,
        ),
      ],
    );
    final controller = DrawingController(document);
    addTearDown(controller.dispose);

    final bounds = controller.contentBounds();
    expect(bounds.left, lessThanOrEqualTo(-174));
    expect(bounds.bottom, greaterThanOrEqualTo(424));
    final png = await controller.renderToPng();
    expect(png, isNotNull);
    expect(png, isNotEmpty);
  });

  test('图片导入拒绝不存在的源文件与非法文档 ID', () async {
    final storage = StorageService(directoryProvider: () async => tempDir);

    await expectLater(
      storage.storeImage('${tempDir.path}/missing.png', 'valid_document'),
      throwsArgumentError,
    );

    final source = File('${tempDir.path}/source.jpg');
    await source.writeAsBytes(const [1, 2, 3]);
    await expectLater(
      storage.storeImage(source.path, '../invalid'),
      throwsArgumentError,
    );
  });
}

Uint8List _tinyPng() {
  const b64 =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGBgAAAABQAB'
      'h6FO1AAAAABJRU5ErkJggg==';
  return Uint8List.fromList(const Base64Codec().decode(b64));
}
