/// EdgelessDocStore 本地存储门面测试。
///
/// 使用临时目录注入 [EdgelessDocStore.directoryProvider]，避免污染真实
/// 应用文档目录，也不依赖 path_provider 的平台通道。
library;

import 'dart:io';

import 'package:drawing_notes_app/features/notes/domain/edgeless_doc.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block_doc.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/edgeless_doc_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late EdgelessDocStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('edgelessdoc_store_test_');
    store = EdgelessDocStore(directoryProvider: () async => tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  EdgelessDoc buildDoc([String id = 'edg-doc-1']) {
    return EdgelessDoc.empty(id)
        .addFrame(NoteBlockDoc.empty('frame-a'), at: const Offset(80, 80))
        .addFrame(NoteBlockDoc.empty('frame-b'), at: const Offset(420, 80));
  }

  test('保存后可加载，内容等价（往返）', () async {
    final original = buildDoc();
    await store.saveDoc(original);

    final loaded = await store.loadDoc(original.id);
    expect(loaded, isNotNull);
    expect(loaded, original); // == / hashCode 已实现
    expect(loaded!.frames.length, 2);
    expect(loaded.camera.zoom, original.camera.zoom);
  });

  test('不存在的 ID 返回 null', () async {
    expect(await store.loadDoc('missing-id'), isNull);
  });

  test('重写存在的文档为最新内容', () async {
    final first = buildDoc();
    await store.saveDoc(first);

    final updated = buildDoc(
      'edg-doc-1',
    ).addFrame(NoteBlockDoc.empty('frame-c'), at: const Offset(200, 200));
    await store.saveDoc(updated);

    final loaded = await store.loadDoc('edg-doc-1');
    expect(loaded, updated);
    expect(loaded!.frames.length, 3);
  });

  test('删除后无法再加载，并返回是否实际删除', () async {
    final doc = buildDoc();
    await store.saveDoc(doc);

    expect(await store.deleteDoc(doc.id), isTrue);
    expect(await store.loadDoc(doc.id), isNull);
    expect(await store.deleteDoc(doc.id), isFalse);
  });

  test('listIds 返回不含后缀的文档 ID', () async {
    await store.saveDoc(buildDoc('alpha'));
    await store.saveDoc(buildDoc('beta'));

    final ids = await store.listIds();
    expect(ids.toSet(), {'alpha', 'beta'});
  });

  test('非法 ID 触发路径遍历防护', () async {
    await expectLater(store.saveDoc(buildDoc('../evil')), throwsArgumentError);
  });
}
