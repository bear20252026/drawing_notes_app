// 首页刷新修复回归测试（2026-09-01）。
//
// 根因：首页只监听 AppServices.dataVersion，而 bumpDataVersion 的调用点
// 只在 app_shell 的打开/恢复/清除路径——笔记本页内部新建（NotebookViewPage
// ._createPage）、画布自动保存、DocPage 保存等内部写路径不通知，首页不刷新；
// IndexedStack 保活下切回首页也不重建。
//
// 修复①（本文件验证的契约）：三个存储层（块文档/笔记本/画布）的写成功
// 回调 onWrite——落盘成功即触发，由 shell 注入 bumpDataVersion，
// 覆盖所有写路径，不再依赖调用点逐一通知。
import 'dart:io';
import 'dart:typed_data';

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block_doc.dart';
import 'package:drawing_notes_app/features/doc/infrastructure/note_block_doc_store.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/notebook_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('home_refresh_fix');
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('修复①：存储层写成功回调（onWrite）', () {
    test('NoteBlockDocStore：保存/删除/恢复均触发回调，读操作不触发', () async {
      final store = NoteBlockDocStore(directoryProvider: () async => tempDir);
      var writes = 0;
      store.onWrite = () => writes++;

      final doc = NoteBlockDoc(
        id: 'refresh_doc1',
        title: '刷新测试',
        createdAt: DateTime(2026, 9, 1),
        updatedAt: DateTime(2026, 9, 1),
      );
      await store.saveDocument(doc);
      expect(writes, 1, reason: '保存应触发 1 次写回调');

      await store.loadDocument('refresh_doc1');
      expect(writes, 1, reason: '读操作不应触发回调');

      await store.deleteDocument('refresh_doc1');
      expect(writes, 2, reason: '软删除应触发回调');

      await store.restoreDocument('refresh_doc1');
      expect(writes, 3, reason: '恢复应触发回调');

      await store.purgeDocument('refresh_doc1');
      expect(writes, 4, reason: '彻底删除应触发回调');
    });

    test('NotebookStorage：保存（明文/密钥路径）与删除触发回调', () async {
      final storage = NotebookStorage(directoryProvider: () async => tempDir);
      var writes = 0;
      storage.onWrite = () => writes++;

      final notebook = Notebook(id: 'refresh_nb1', title: '刷新笔记本');
      await storage.save(notebook);
      expect(writes, 1, reason: 'save 应触发回调');

      // saveWithKey（keyfile 编辑会话路径）也汇入 _writeNotebook 单一出口。
      final loaded = await storage.load('refresh_nb1');
      await storage.saveWithKey(
        loaded!,
        Uint8List.fromList(List.filled(32, 7)),
      );
      expect(writes, 2, reason: 'saveWithKey 应触发回调');

      await storage.delete('refresh_nb1');
      expect(writes, 3, reason: 'delete 应触发回调');
    });

    test('StorageService：画布保存/缩略图/删除触发回调', () async {
      final storage = StorageService(directoryProvider: () async => tempDir);
      var writes = 0;
      storage.onWrite = () => writes++;

      final doc = DrawingDocument(id: 'refresh_draw1', title: '画布');
      await storage.save(doc);
      expect(writes, 1, reason: '画布保存应触发回调');

      await storage.saveThumbnail(
        'refresh_draw1',
        Uint8List.fromList([1, 2, 3]),
      );
      expect(writes, 2, reason: '缩略图更新应触发回调');

      await storage.delete('refresh_draw1');
      expect(writes, 3, reason: '删除（移入回收站）应触发回调');
    });
  });
}
