// 审计 U4：块文档大载荷 isolate 编解码/加密路径回归——
// saveDocument/loadDocument 在阈值以上（走 Isolate.run）仍保序往返一致。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/features/doc/domain/note_block.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block_doc.dart';
import 'package:drawing_notes_app/features/doc/infrastructure/note_block_doc_store.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('nbdiso_');
  });

  tearDown(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  test('大文档（超 isolate 阈值）save/load 往返一致', () async {
    final store = NoteBlockDocStore(directoryProvider: () async => tmp);
    // 单块 40_000 码元文本——编码/解析两侧均越过 32K 码元阈值，
    // save 与 load 全部走 Isolate.run 路径。
    final bigText = '甲' * 40000;
    final doc = NoteBlockDoc(
      id: NoteBlockDocStore.newId('iso'),
      title: '大文档',
      body: [NoteBlock.textBlock('${'iso'}_b0', text: bigText)],
      createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(1700000001000),
    );

    await store.saveDocument(doc);
    final loaded = await store.loadDocument(doc.id);

    expect(loaded, isNotNull);
    expect(loaded, doc);
    expect(loaded!.body.single.text, bigText);
  });

  test('小文档（阈值以下，主线程路径）save/load 往返一致', () async {
    final store = NoteBlockDocStore(directoryProvider: () async => tmp);
    final doc = NoteBlockDoc.empty('small1', title: '小文档');

    await store.saveDocument(doc);
    final loaded = await store.loadDocument('small1');

    expect(loaded, isNotNull);
    expect(loaded, doc);
  });
}
