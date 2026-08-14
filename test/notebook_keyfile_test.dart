import 'dart:io';

import 'package:drawing_notes_app/engine/encryption_service.dart';
import 'package:drawing_notes_app/models/document.dart';
import 'package:drawing_notes_app/models/notebook.dart';
import 'package:drawing_notes_app/storage/notebook_storage.dart';
import 'package:drawing_notes_app/storage/password_disk.dart';
import 'package:flutter_test/flutter_test.dart';

/// 密码盘接入笔记本加密（keyfile 模式）集成测试。
///
/// 全链路：U盘钥匙加密笔记本 → 插盘解锁 → U盘丢失用恢复密钥找回 →
/// 编辑会话保存（内容不丢失、明文不落盘）。
void main() {
  late Directory tempDir;
  late Directory diskDir;
  late NotebookStorage storage;
  late MockPasswordDisk disk;
  const encryption = EncryptionService();

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('nb_keyfile_');
    diskDir = await Directory.systemTemp.createTemp('nb_keyfile_disk_');
    storage = NotebookStorage(directoryProvider: () async => tempDir);
    disk = MockPasswordDisk(baseDir: diskDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
    if (await diskDir.exists()) await diskDir.delete(recursive: true);
  });

  Notebook makeNotebook() => Notebook(id: 'nb1', title: '涉密会议');

  NotebookPage makePage(String text) => NotebookPage(
    id: 'pg1',
    title: '记录',
    document: DrawingDocument(id: 'd1', title: '页', width: 2480, height: 3508),
  )..textItems.add(PageTextItem(id: 't1', x: 60, y: 60, text: text));

  test('keyfile 加密：U盘钥匙加密笔记本，明文不落盘、模式与信封保存', () async {
    await disk.createKeyFile(diskDir.path);
    final masterKey = (await disk.readKey(diskDir.path))!;
    const recovery = 'RECOVER-24-ABCD-WXYZ';

    final nb = makeNotebook()..pages.add(makePage('绝密内容'));
    await storage.encryptAndSaveWithKey(nb, masterKey, recovery);

    // 磁盘内容检查。
    final raw = await File(
      '${tempDir.path}${Platform.pathSeparator}notebooks'
      '${Platform.pathSeparator}nb1.json',
    ).readAsString();
    expect(raw.contains('绝密内容'), isFalse, reason: '明文不应落盘');
    expect(raw.contains('keyfile'), isTrue, reason: '应标记 keyfile 模式');
    expect(raw.contains('recoveryEnvelope'), isTrue, reason: '应存恢复信封');

    // 重新加载：模式与信封保留。
    final loaded = (await storage.load('nb1'))!;
    expect(loaded.encrypted, isTrue);
    expect(loaded.encryptionMode, EncryptionMode.keyfile);
    expect(loaded.recoveryEnvelope, isNotNull);
  });

  test('插盘解锁：U盘主密钥解密还原页面内容', () async {
    await disk.createKeyFile(diskDir.path);
    final masterKey = (await disk.readKey(diskDir.path))!;

    final nb = makeNotebook()..pages.add(makePage('插盘解锁测试'));
    await storage.encryptAndSaveWithKey(nb, masterKey, 'RECOVER-24-ABCD-WXYZ');

    // 模拟打开：加载 → 插盘读密钥 → 解锁。
    final loaded = (await storage.load('nb1'))!;
    final key2 = (await disk.readKey(diskDir.path))!;
    final ok = await storage.decryptNotebookWithKey(loaded, key2);
    expect(ok, isTrue);
    expect(
      loaded.pages.first.textItems.first.text,
      '插盘解锁测试',
      reason: '解锁后应还原页面内容',
    );
  });

  test('U盘丢失恢复：恢复密钥解信封找回主密钥 → 解锁', () async {
    await disk.createKeyFile(diskDir.path);
    final masterKey = (await disk.readKey(diskDir.path))!;
    const recovery = 'RECOVER-24-ABCD-WXYZ';

    final nb = makeNotebook()..pages.add(makePage('丢失恢复测试'));
    await storage.encryptAndSaveWithKey(nb, masterKey, recovery);

    // 模拟 U 盘丢失：删除密钥文件。
    await File('${diskDir.path}${Platform.pathSeparator}key.frogkey').delete();

    // 从存储加载，取出信封，用恢复密钥解出主密钥。
    final loaded = (await storage.load('nb1'))!;
    final envelope = loaded.recoveryEnvelope!;
    final recovered = await encryption.unwrapMasterKey(envelope, recovery);
    expect(recovered, masterKey, reason: '恢复的主密钥应一致');

    // 用恢复出的密钥解锁。
    final ok = await storage.decryptNotebookWithKey(loaded, recovered);
    expect(ok, isTrue);
    expect(loaded.pages.first.textItems.first.text, '丢失恢复测试');
  });

  test('错误密钥解锁失败（防篡改）', () async {
    await disk.createKeyFile(diskDir.path);
    final masterKey = (await disk.readKey(diskDir.path))!;

    final nb = makeNotebook()..pages.add(makePage('防篡改'));
    await storage.encryptAndSaveWithKey(nb, masterKey, 'RECOVER-24-ABCD-WXYZ');

    final loaded = (await storage.load('nb1'))!;
    final wrongKey = List<int>.generate(32, (i) => i + 1);
    await expectLater(
      storage.decryptNotebookWithKey(loaded, wrongKey),
      throwsA(isA<Object>()),
      reason: '错误主密钥解锁应失败',
    );
  });

  test('编辑会话保存：keyfile 模式用 saveWithKey 重加密，内容保留', () async {
    await disk.createKeyFile(diskDir.path);
    final masterKey = (await disk.readKey(diskDir.path))!;

    final nb = makeNotebook()..pages.add(makePage('初始内容'));
    await storage.encryptAndSaveWithKey(nb, masterKey, 'RECOVER-24-ABCD-WXYZ');

    // 模拟编辑会话：解锁 → 添加内容 → saveWithKey 保存。
    final loaded = (await storage.load('nb1'))!;
    await storage.decryptNotebookWithKey(loaded, masterKey);
    loaded.pages.first.textItems.add(
      PageTextItem(id: 't2', x: 200, y: 200, text: '编辑后新增'),
    );
    await storage.saveWithKey(loaded, masterKey);

    // 重开验证：新内容在、旧内容在、明文不落盘。
    final reloaded = (await storage.load('nb1'))!;
    final raw = await File(
      '${tempDir.path}${Platform.pathSeparator}notebooks'
      '${Platform.pathSeparator}nb1.json',
    ).readAsString();
    expect(raw.contains('编辑后新增'), isFalse, reason: '明文不应落盘');
    await storage.decryptNotebookWithKey(reloaded, masterKey);
    expect(
      reloaded.pages.first.textItems.any((t) => t.text == '编辑后新增'),
      isTrue,
      reason: '编辑内容必须保留',
    );
    expect(
      reloaded.pages.first.textItems.any((t) => t.text == '初始内容'),
      isTrue,
      reason: '原内容必须保留',
    );
  });
}
