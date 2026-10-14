// 删除文档不得留下 `.bak` 侧车（批次 D 第二层的地基，任务 #23）。
//
// 为什么单独钉这一条：残留侧车会让这篇文档**既删不掉又不会消失**——列表只认
// `.json` 看不见它，而 `load` 会凭 `.bak` 把它读回来；更糟的是同步侧
// （块文档是唯一喂 WebDAV 的家族）看到的形状是「基线有、本次清单无」，
// 那是删除墓碑的判据 ⇒ 云端副本收到 `DELETE`。侧车必须跟正文一起消失。
//
// 顺带钉「只剩侧车」这一格：那是 rename 期崩溃留下的。旧写法在
// `deleteDocumentToTrash` 里 `if (!file.existsSync()) return false` 直接判
// 「无此文档」⇒ 用户点删除什么也没发生，而那颗复活种子还在原地。
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';

import '../../helpers/temp_dir_cleanup.dart';

void main() {
  late Directory tempDir;
  late StorageService repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('trash_bak_');
    repo = StorageService(directoryProvider: () async => tempDir);
  });

  tearDown(() async {
    await deleteTempDirWithRetry(tempDir);
  });

  String pathOf(String id) =>
      '${tempDir.path}${Platform.pathSeparator}documents'
      '${Platform.pathSeparator}$id.json';

  DrawingDocument doc(String id, String title) =>
      DrawingDocument(id: id, title: title, width: 400, height: 300);

  Future<void> saveTwice(String id) async {
    await repo.save(doc(id, '第一版'));
    await repo.save(doc(id, '第二版'));
  }

  group('画布删除（回收站域）：侧车一起消失', () {
    test('正常删除 ⇒ 正文进回收站、`.bak` 被清掉、load 返回 null', () async {
      await saveTwice('bk_a');
      expect(File('${pathOf('bk_a')}.bak').existsSync(), isTrue,
          reason: '前置条件：写过两次才有侧车');

      expect(await repo.delete('bk_a'), isTrue);

      expect(File(pathOf('bk_a')).existsSync(), isFalse);
      expect(File('${pathOf('bk_a')}.bak').existsSync(), isFalse,
          reason: '删过的笔记留着侧车就是复活种子（列表/同步都会因此出错）');
      expect(await repo.load('bk_a'), isNull);
      expect((await repo.listDocuments()).map((m) => m.id), isNot(contains('bk_a')));
    });

    test('只剩 `.bak`（rename 期崩溃留下的）也删得掉，且不留残', () async {
      await saveTwice('bk_b');
      // 模拟兜底「先删目标再改名」之后断电：正文没了，侧车还在。
      File(pathOf('bk_b')).deleteSync();
      expect(File(pathOf('bk_b')).existsSync(), isFalse);
      expect(File('${pathOf('bk_b')}.bak').existsSync(), isTrue);

      expect(
        await repo.delete('bk_b'),
        isTrue,
        reason: '旧写法这里 return false —— 用户点删除什么也没发生，种子还在',
      );
      expect(File('${pathOf('bk_b')}.bak').existsSync(), isFalse);
      expect(await repo.load('bk_b'), isNull);

      // 第二次删除如实返回 false（真的没有这篇了），不是「删不掉」。
      expect(await repo.delete('bk_b'), isFalse);
    });

    test('侧车位置被目录占住时，删除依然成功且不抛给调用方', () async {
      // 这是写路径那批「`.bak` 被占」用例留下的真实形态：侧卡路径上是个目录。
      // 旧写法里正文已进回收站之后 `backup.delete()` 一旦抛出就会向冒——调用方看到
      // 「删除失败」，文档却已经消失；现在它被收进 try 并落审计。
      await saveTwice('bk_c');
      final bak = File('${pathOf('bk_c')}.bak');
      bak.deleteSync();
      Directory(bak.path).createSync(recursive: true);

      expect(await repo.delete('bk_c'), isTrue);
      expect(File(pathOf('bk_c')).existsSync(), isFalse,
          reason: '正文必须已经进回收站');
      expect(await repo.load('bk_c'), isNull);

      Directory(bak.path).deleteSync();
    });
  });

  test('画布删除后正文确实落在回收站里（不是被顺手销毁）', () async {
    await saveTwice('bk_d');
    await repo.delete('bk_d');

    // 回收站条目形状：(落盘文件名, 文档 id, 删除时间)。
    final trashed = await repo.listTrash();
    expect(trashed.map((e) => e.$2), contains('bk_d'),
        reason: '删除是移入回收站，不是顺手销毁——误删还得能恢复');
    expect(trashed.first.$1, startsWith('bk_d_'));
  });
}
