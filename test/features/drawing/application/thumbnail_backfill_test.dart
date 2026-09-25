// v1.17.20 退出路径缩略图后台补渲队列回归测试。
//
// 用 renderOverride 注入假渲染（不触碰 dart:ui 真实栅格化），
// StorageService 用真实实现 + 临时目录，验证字节真正落盘。
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';
import 'package:drawing_notes_app/features/drawing/application/thumbnail_backfill.dart';

void main() {
  late Directory tempDir;
  late StorageService storage;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('thumb_backfill_test_');
    storage = StorageService(directoryProvider: () async => tempDir);
  });

  tearDown(() async {
    ThumbnailBackfill.resetForTest();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('submit 后异步补渲并把缩略图写入存储', () async {
    final calls = <String>[];
    ThumbnailBackfill.renderOverride = (doc) async {
      calls.add(doc.id);
      return Uint8List.fromList([1, 2, 3, 4]);
    };
    final doc = DrawingDocument(id: 'doc_a', title: 'A');

    ThumbnailBackfill.submit(doc, storage);
    // 轮询等待 drain 完成（submit 内部 unawaited）：以缩略图落盘为准，
    // 不能只看渲染回调触发（渲染与写盘之间还有一步 await）。
    Uint8List? bytes;
    for (var i = 0; i < 100; i++) {
      bytes = await storage.thumbnailBytes('doc_a');
      if (bytes != null) break;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    expect(calls, ['doc_a']);
    expect(bytes, isNotNull);
    expect(bytes, Uint8List.fromList([1, 2, 3, 4]));
  });

  test('渲染失败不抛出、不中断（缩略图可再生语义）', () async {
    ThumbnailBackfill.renderOverride = (doc) async => throw StateError('boom');
    final doc = DrawingDocument(id: 'doc_bad', title: 'B');

    ThumbnailBackfill.submit(doc, storage);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(await storage.thumbnailBytes('doc_bad'), isNull);
    expect(ThumbnailBackfill.isPending, isFalse);
  });

  test('快照语义：submit 后修改原文档不影响补渲内容', () async {
    DrawingDocument? captured;
    ThumbnailBackfill.renderOverride = (doc) async {
      captured = doc;
      return Uint8List.fromList([9]);
    };
    final doc = DrawingDocument(id: 'doc_snap', title: 'origin');

    ThumbnailBackfill.submit(doc, storage);
    // submit 立即深拷贝：此后改原文档标题不应影响队列中的快照。
    doc.title = 'changed';
    for (var i = 0; i < 100 && captured == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    expect(captured?.title, 'origin');
  });
}
