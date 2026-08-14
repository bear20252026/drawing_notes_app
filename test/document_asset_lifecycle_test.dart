import 'dart:io';
import 'dart:typed_data';

import 'package:drawing_notes_app/models/document.dart';
import 'package:drawing_notes_app/models/document_image_item.dart';
import 'package:drawing_notes_app/storage/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'document_asset_lifecycle_',
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  DrawingDocument documentWithImage(String id, String path) => DrawingDocument(
    id: id,
    title: id,
    imageItems: [
      DocumentImageItem(
        id: '${id}_image',
        x: 10,
        y: 20,
        width: 100,
        height: 60,
        filePath: path,
      ),
    ],
  );

  test('删除文档会回收其唯一引用的受管离线图片和备份', () async {
    final storage = StorageService(directoryProvider: () async => tempDir);
    final source = File('${tempDir.path}${Platform.pathSeparator}source.png');
    await source.writeAsBytes(const <int>[1, 2, 3, 4]);
    final storedPath = await storage.storeImage(source.path, 'asset_owner');
    await storage.save(documentWithImage('asset_owner', storedPath));
    await storage.save(documentWithImage('asset_owner', storedPath));

    expect(await File(storedPath).exists(), isTrue);
    expect(
      await File(
        '${tempDir.path}${Platform.pathSeparator}documents${Platform.pathSeparator}asset_owner.json.bak',
      ).exists(),
      isTrue,
    );

    expect(await storage.delete('asset_owner'), isTrue);
    expect(await File(storedPath).exists(), isFalse);
    expect(await source.exists(), isTrue);
    expect(
      await File(
        '${tempDir.path}${Platform.pathSeparator}documents${Platform.pathSeparator}asset_owner.json.bak',
      ).exists(),
      isFalse,
    );
  });

  test('删除文档不会回收仍被其他文档引用的受管图片', () async {
    final storage = StorageService(directoryProvider: () async => tempDir);
    final source = File('${tempDir.path}${Platform.pathSeparator}source.jpg');
    await source.writeAsBytes(const <int>[5, 6, 7]);
    final storedPath = await storage.storeImage(source.path, 'first_doc');
    await storage.save(documentWithImage('first_doc', storedPath));
    await storage.save(documentWithImage('second_doc', storedPath));

    expect(await storage.delete('first_doc'), isTrue);
    expect(await File(storedPath).exists(), isTrue);
    expect(await storage.delete('second_doc'), isTrue);
    expect(await File(storedPath).exists(), isFalse);
  });

  test('删除文档绝不删除外部图片路径', () async {
    final storage = StorageService(directoryProvider: () async => tempDir);
    final external = File(
      '${tempDir.path}${Platform.pathSeparator}external_user_photo.webp',
    );
    await external.writeAsBytes(Uint8List.fromList(const <int>[8, 9, 10]));
    await storage.save(documentWithImage('external_path', external.path));

    expect(await storage.delete('external_path'), isTrue);
    expect(await external.exists(), isTrue);
  });
}
