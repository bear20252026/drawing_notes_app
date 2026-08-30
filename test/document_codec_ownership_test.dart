import 'dart:io';

import 'package:drawing_notes_app/core/storage/document_codec.dart'
    as core_codec;
import 'package:drawing_notes_app/core/storage/storage_service.dart';
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/features/drawing/infrastructure/document_codec.dart'
    as legacy_codec;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DocumentCodec 所有权迁移', () {
    test('旧绘图路径导出核心存储的同一个编解码类型', () {
      const legacy = legacy_codec.DocumentCodec();

      expect(legacy, isA<core_codec.DocumentCodec>());
      expect(
        legacy_codec.DocumentCodec.latestVersion,
        core_codec.DocumentCodec.latestVersion,
      );
    });

    test('新旧路径对稳定文档产生相同字节并可交叉恢复', () {
      final document = DrawingDocument(
        id: 'codec_boundary_doc',
        title: '所有权迁移',
        width: 640,
        height: 480,
        createdAt: DateTime.utc(2026, 8, 27, 12),
        updatedAt: DateTime.utc(2026, 8, 27, 12, 1),
      );
      const legacy = legacy_codec.DocumentCodec();
      const canonical = core_codec.DocumentCodec();

      final legacyBytes = legacy.encode(document);
      final canonicalBytes = canonical.encode(document);
      final restored = canonical.decode(legacyBytes);

      expect(legacyBytes, orderedEquals(canonicalBytes));
      expect(restored.id, document.id);
      expect(restored.title, document.title);
      expect(restored.width, document.width);
      expect(restored.height, document.height);
    });

    test('StorageService 接受核心存储路径的编解码器', () async {
      final tempDir = await Directory.systemTemp.createTemp('codec_owner_');
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });
      final storage = StorageService(
        codec: const core_codec.DocumentCodec(),
        directoryProvider: () async => tempDir,
      );
      final document = DrawingDocument(id: 'core_codec_storage', title: '核心存储');

      await storage.save(document);
      final restored = await storage.load(document.id);

      expect(restored, isNotNull);
      expect(restored!.title, document.title);
    });
  });
}
