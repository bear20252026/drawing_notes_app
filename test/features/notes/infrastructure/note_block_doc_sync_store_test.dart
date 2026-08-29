// 由 Claude 团队生成 | Drawing Notes App
// NoteBlockDocSyncStore 适配器集成测试：用临时目录驱动真实 NoteBlockDocStore。

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/features/notes/domain/note_block_doc.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/note_block_doc_store.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/note_block_doc_sync_store.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('nbdsync_');
  });

  tearDown(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  test('listDocuments 返回 id/updatedAt/size 元数据', () async {
    final store = NoteBlockDocStore(directoryProvider: () async => tmp);
    final sync = NoteBlockDocSyncStore(store);
    await store.saveDocument(NoteBlockDoc.empty('d1', title: '设计'));

    final metas = await sync.listDocuments();
    expect(metas, hasLength(1));
    expect(metas.single.id, 'd1');
    expect(metas.single.updatedAt,
        (await store.loadDocument('d1'))!.updatedAt.millisecondsSinceEpoch);
    expect(metas.single.size, greaterThan(0));
  });

  test('readDocument / writeDocument / deleteDocument 闭环', () async {
    final store = NoteBlockDocStore(directoryProvider: () async => tmp);
    final sync = NoteBlockDocSyncStore(store);
    await store.saveDocument(NoteBlockDoc.empty('d1', title: '本地'));

    // read
    final bytes = await sync.readDocument('d1');
    expect(bytes, isNotNull);

    // write（远程文档，id 与内容一致）
    final remote = NoteBlockDoc.empty('d2', title: '远程');
    await sync.writeDocument(
      'd2',
      Uint8List.fromList(utf8.encode(jsonEncode(remote.toJson()))),
    );
    final loaded = await store.loadDocument('d2');
    expect(loaded, isNotNull);
    expect(loaded!.title, '远程');

    // delete
    await sync.deleteDocument('d1');
    expect(await store.loadDocument('d1'), isNull);
  });

  test('writeDocument 会纠正字节内 id 与传入 id 不一致的情况', () async {
    final store = NoteBlockDocStore(directoryProvider: () async => tmp);
    final sync = NoteBlockDocSyncStore(store);
    // 字节里是其它 id，但 writeDocument('x', ...) 强制以 'x' 落盘。
    final other = NoteBlockDoc.empty('weird', title: '改');
    await sync.writeDocument(
      'x',
      Uint8List.fromList(utf8.encode(jsonEncode(other.toJson()))),
    );
    final loaded = await store.loadDocument('x');
    expect(loaded, isNotNull);
    expect(loaded!.id, 'x');
    expect(loaded.title, '改');
  });
}
