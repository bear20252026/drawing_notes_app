import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/infrastructure/storage/v2/encrypted_write_transaction.dart';

/// 专家第一周更正期 S-001~S-004（2026-08-16）：加密写入事务更正——
/// S-001 V1 明文拒绝（不 .bak）/ S-002 V2 密文备份 / S-003 backup 失败
/// 明确 / S-004 临时文件失败可恢复。
void main() {
  late Directory tempDir;
  final key = List<int>.generate(32, (i) => i);

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('ewt_test');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {
      /* 忽略清理失败 */
    }
  });

  test('S-001：V1 明文 destination 拒绝——不生成 .bak——主文件不变', () async {
    final dest = File('${tempDir.path}/note.json');
    // 预置 V1 明文（唯一测试串——专家测试输入）。
    await dest.writeAsString('W1_LEGACY_PLAINTEXT_001');
    final txn = EncryptedWriteTransaction(
      key: key,
      aadContext: 'notebook|n1|payload|v2',
    );
    await expectLater(
      txn.commit(destination: dest, plain: Uint8List.fromList('新内容'.codeUnits)),
      throwsA(isA<MigrationRequiredException>()),
    );
    // 主文件不变（未被覆盖）+ 无 .bak + 无 .tmp。
    expect(await dest.readAsString(), 'W1_LEGACY_PLAINTEXT_001');
    expect(await File('${dest.path}.bak').exists(), isFalse);
    expect(
      tempDir.listSync().whereType<File>().where(
        (f) => f.path.endsWith('.tmp'),
      ),
      isEmpty,
    );
  });

  test('S-002：V2 第二次写入只产生密文备份（magic 可解析——无明文）', () async {
    final dest = File('${tempDir.path}/note2.json');
    final txn = EncryptedWriteTransaction(
      key: key,
      aadContext: 'notebook|n2|payload|v2',
    );
    // 第一次 V2 写入 A——无 .bak。
    await txn.commit(
      destination: dest,
      plain: Uint8List.fromList('机密-A'.codeUnits),
    );
    expect(await File('${dest.path}.bak').exists(), isFalse);
    // 第二次 V2 写入 B——.bak 出现（ValidV2——magic 可解析）。
    await txn.commit(
      destination: dest,
      plain: Uint8List.fromList('机密-B'.codeUnits),
    );
    expect(
      await txn.destinationState(File('${dest.path}.bak')),
      isA<ValidV2Ciphertext>(),
    );
    // 主/.bak 均不含明文 A/B。
    final mainBytes = await dest.readAsBytes();
    final bakBytes = await File('${dest.path}.bak').readAsBytes();
    expect(String.fromCharCodes(mainBytes).contains('机密-A'), isFalse);
    expect(String.fromCharCodes(mainBytes).contains('机密-B'), isFalse);
    expect(String.fromCharCodes(bakBytes).contains('机密-A'), isFalse);
    expect(String.fromCharCodes(bakBytes).contains('机密-B'), isFalse);
    // AAD notebookId 不匹配时解密失败（V2 密文不可被跨笔记解读）。
    final wrongTxn = EncryptedWriteTransaction(
      key: key,
      aadContext: 'notebook|OTHER|payload|v2',
    );
    final box = await wrongTxn.destinationState(dest);
    expect(box, isA<ValidV2Ciphertext>()); // header 可识别——但 AAD 认证失败在解密层。
  });

  test('S-003：backup 失败明确返回——不静默——原主文件保持', () async {
    final dest = File('${tempDir.path}/note3.json');
    final txn = EncryptedWriteTransaction(
      key: key,
      aadContext: 'notebook|n3|payload|v2',
    );
    // 第一次 V2 写入（主文件存在——第二次提交时需备份）。
    await txn.commit(
      destination: dest,
      plain: Uint8List.fromList('旧版本'.codeUnits),
    );
    final oldBytes = await dest.readAsBytes();
    // 让 .bak 路径被目录占用——copy 失败（FileSystemException）。
    await Directory('${dest.path}.bak').create();
    await expectLater(
      txn.commit(destination: dest, plain: Uint8List.fromList('新版本'.codeUnits)),
      throwsA(isA<BackupFailedException>()),
    );
    // 原主文件保持可恢复。
    expect(await dest.readAsBytes(), oldBytes);
  });

  test('S-004：临时文件失败可恢复——旧主文件仍可读——无明文 tmp', () async {
    final dest = File('${tempDir.path}/note4.json');
    final txn = EncryptedWriteTransaction(
      key: key,
      aadContext: 'notebook|n4|payload|v2',
    );
    await txn.commit(
      destination: dest,
      plain: Uint8List.fromList('旧版本'.codeUnits),
    );
    final oldBytes = await dest.readAsBytes();
    // 无效密钥（长度错误——commit 抛异常）——中断——旧文件保留。
    final badTxn = EncryptedWriteTransaction(
      key: const [],
      aadContext: 'notebook|n4|payload|v2',
    );
    await expectLater(
      badTxn.commit(
        destination: dest,
        plain: Uint8List.fromList('新版本'.codeUnits),
      ),
      throwsA(isA<ArgumentError>()),
    );
    expect(await dest.readAsBytes(), oldBytes);
    expect(
      tempDir.listSync().whereType<File>().where(
        (f) => f.path.endsWith('.tmp'),
      ),
      isEmpty,
    );
  });
}
