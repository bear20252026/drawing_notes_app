// ============================================================================
// notebook_storage_delete_bak_test.dart —— 删除笔记本须连带清理 .bak（三-5）
// ============================================================================
//
// 审计第 4 轮三-5：delete 只删主文件，.bak 备份留在磁盘（隐私残留），
// 且下次 load 可凭备份「复活」已删除的笔记本。本文件锁定修复后的行为。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/features/notes/domain/notebook.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/notebook_storage.dart';

import '../../../helpers/temp_dir_cleanup.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('nb_del_bak_');
  });

  tearDown(() async {
    await deleteTempDirWithRetry(tempDir);
  });

  File mainFile(String id) => File(
    '${tempDir.path}${Platform.pathSeparator}notebooks'
    '${Platform.pathSeparator}$id.json',
  );

  File bakFile(String id) => File('${mainFile(id).path}.bak');

  NotebookStorage newStorage() =>
      NotebookStorage(directoryProvider: () async => tempDir);

  test('删除笔记本：主文件与 .bak 一并清除（隐私不留残）', () async {
    final storage = newStorage();
    final nb = Notebook(id: 'nb1', title: '被删除的笔记本');
    // 保存两次：第二次写入前会为主文件留 .bak。
    await storage.save(nb);
    await storage.save(nb);
    expect(await mainFile('nb1').exists(), isTrue);
    expect(await bakFile('nb1').exists(), isTrue,
        reason: '前置条件：二次保存后应存在 .bak');

    final ok = await storage.delete('nb1');

    expect(ok, isTrue);
    expect(await mainFile('nb1').exists(), isFalse);
    expect(await bakFile('nb1').exists(), isFalse,
        reason: '三-5：.bak 不得残留旧内容');
    // 删除后 load 不再凭备份复活。
    expect(await storage.load('nb1'), isNull);
  });

  test('仅剩 .bak（rename 期崩溃形态）：delete 返回 true 并清掉备份', () async {
    final storage = newStorage();
    final nb = Notebook(id: 'nb2', title: '只剩备份的笔记本');
    await storage.save(nb);
    await storage.save(nb);
    // 模拟主文件丢失、备份仍在。
    await mainFile('nb2').delete();
    expect(await bakFile('nb2').exists(), isTrue);

    final ok = await storage.delete('nb2');

    expect(ok, isTrue);
    expect(await bakFile('nb2').exists(), isFalse);
  });

  test('主文件与备份都不存在：delete 返回 false（原行为保留）', () async {
    final storage = newStorage();
    expect(await storage.delete('nb_missing'), isFalse);
  });
}
