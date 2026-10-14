// 删除块文档不得留下 `.bak` 侧车（批次 D 第二层的地基，任务 #23）。
//
// 块文档（打字笔记）是**唯一喂 WebDAV 同步**的文档家族，所以这条比画布那条更要紧：
// 残留侧车让这篇文档既「删不掉」（`loadDocument` 会凭 `.bak` 把它读回来），
// 又正好凑成同步侧删除墓碑的判据形状「基线有、本次清单无」（清单只认 `.json`）
// ⇒ 云端副本收到 `DELETE`。侧车必须跟正文一起消失。
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/documents/note_block.dart';
import 'package:drawing_notes_app/core/documents/note_block_doc.dart';
import 'package:drawing_notes_app/core/documents/note_block_doc_store.dart';

import '../../helpers/temp_dir_cleanup.dart';

void main() {
  late Directory tempDir;
  late NoteBlockDocStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('blockdoc_bak_');
    // 明文装配：本文件验的是文件面，不需要真 KDF。
    store = NoteBlockDocStore(directoryProvider: () async => tempDir);
  });

  tearDown(() async {
    await deleteTempDirWithRetry(tempDir);
  });

  String pathOf(String id) =>
      '${tempDir.path}${Platform.pathSeparator}blockdocs'
      '${Platform.pathSeparator}$id.json';

  NoteBlockDoc doc(String id, String title) {
    final t = DateTime.fromMillisecondsSinceEpoch(0);
    return NoteBlockDoc(
      id: id,
      title: title,
      body: [NoteBlock.textBlock('${id}_b1', text: '正文 $title')],
      createdAt: t,
      updatedAt: t,
    );
  }

  Future<void> saveTwice(String id) async {
    await store.saveDocument(doc(id, '第一版'));
    await store.saveDocument(doc(id, '第二版'));
  }

  test('正常删除 ⇒ 正文与 .bak 都不在盘上，load 返回 null', () async {
    await saveTwice('bd_a');
    expect(
      File('${pathOf('bd_a')}.bak').existsSync(),
      isTrue,
      reason: '前置条件：写过两次才有侧车',
    );

    expect(await store.deleteDocument('bd_a'), isTrue);

    expect(File(pathOf('bd_a')).existsSync(), isFalse);
    expect(
      File('${pathOf('bd_a')}.bak').existsSync(),
      isFalse,
      reason: '删过的笔记留着侧车就是复活种子：列表看不见它而基线里有它 ⇒ 云端被 DELETE',
    );
    expect(await store.loadDocument('bd_a'), isNull);
    expect((await store.listDocHeaders()).map((h) => h.id), isNot(contains('bd_a')));
  });

  test('只剩 .bak（rename 期崩溃留下的）也删得掉，且不留残', () async {
    await saveTwice('bd_b');
    File(pathOf('bd_b')).deleteSync();
    expect(File('${pathOf('bd_b')}.bak').existsSync(), isTrue);

    expect(
      await store.deleteDocument('bd_b'),
      isTrue,
      reason: '旧写法在这里 return false：用户点删除什么也没发生，种子还在原地',
    );
    expect(File('${pathOf('bd_b')}.bak').existsSync(), isFalse);
    expect(await store.loadDocument('bd_b'), isNull);

    // 第二次如实返回 false（真的没有这篇了），不是「删不掉」。
    expect(await store.deleteDocument('bd_b'), isFalse);
  });

  test('彻底删除（不经回收站）也不留侧车', () async {
    await saveTwice('bd_c');

    expect(await store.purgeDocument('bd_c'), isTrue);

    expect(File(pathOf('bd_c')).existsSync(), isFalse);
    expect(File('${pathOf('bd_c')}.bak').existsSync(), isFalse);
    expect(await store.loadDocument('bd_c'), isNull);
  });

  test('侧车位置被目录占住时删除仍然成功，不把异常抛给调用方', () async {
    // 写路径那批「`.bak` 被占」用例留下的真实形态：侧卡路径上是个目录。
    await saveTwice('bd_d');
    final bak = File('${pathOf('bd_d')}.bak');
    bak.deleteSync();
    Directory(bak.path).createSync(recursive: true);

    expect(await store.deleteDocument('bd_d'), isTrue);
    expect(File(pathOf('bd_d')).existsSync(), isFalse, reason: '正文必须已经进回收站');
    expect(await store.loadDocument('bd_d'), isNull);

    Directory(bak.path).deleteSync();
  });
}
