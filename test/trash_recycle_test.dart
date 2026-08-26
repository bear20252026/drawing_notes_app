import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/infrastructure/storage/storage_service.dart';
import 'package:drawing_notes_app/features/drawing/domain/document.dart';

/// M-06 修复（专家审计 2026-08-15）：回收站——删除移入回收站（30 天保留，
/// Android 官方 createTrashRequest/Files by Google 模式）+ 恢复 + 过期清理。
void main() {
  late Directory tempDir;
  late StorageService storage;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('trash_test');
    storage = StorageService(directoryProvider: () async => tempDir);
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test('M-06：删除移入回收站（listTrash 可见，listDocuments 不可见）', () async {
    final doc = DrawingDocument(id: 'doc1', title: '回收站测试');
    await storage.save(doc);
    expect(await storage.delete('doc1'), isTrue);
    // 列表不可见（回收站为独立目录）。
    expect(await storage.listDocuments(), isEmpty);
    // 回收站可见（含原始 id 与删除时间）。
    final trash = await storage.listTrash();
    expect(trash.length, 1);
    expect(trash.first.$2, 'doc1');
  });

  test('M-06：恢复回收站项（restoreTrash 移回 documents）', () async {
    final doc = DrawingDocument(id: 'doc2', title: '恢复测试');
    await storage.save(doc);
    await storage.delete('doc2');
    final trash = await storage.listTrash();
    expect(trash, hasLength(1));
    final restoredId = await storage.restoreTrash(trash.first.$1);
    expect(restoredId, 'doc2');
    expect(await storage.listDocuments(), hasLength(1));
  });

  test('M-06：过期清理（purgeTrash 删除超保留期项）', () async {
    final doc = DrawingDocument(id: 'doc3', title: '清理测试');
    await storage.save(doc);
    await storage.delete('doc3');
    // 用零保留期强制清理（覆盖默认 30 天——测试语义）。
    final purged = await storage.purgeTrash(retention: Duration.zero);
    expect(purged, 1);
    expect(await storage.listTrash(), isEmpty);
  });
}
