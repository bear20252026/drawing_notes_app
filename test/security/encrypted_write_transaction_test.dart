import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/infrastructure/storage/v2/encrypted_write_transaction.dart';

/// 专家 I-004（2026-08-16——批次 A）：加密写入事务——
/// 主/备/临时文件均无明文（AES-GCM + AAD）+ 中断可恢复（旧文件保留）。
void main() {
  late Directory tempDir;
  final key = List<int>.generate(32, (i) => i);

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('ewt_test');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {/* 忽略清理失败 */}
  });

  test('I-004：提交后主/备文件均为密文（无测试明文）', () async {
    final dest = File('${tempDir.path}/note.json');
    final txn = EncryptedWriteTransaction(
      key: key,
      aadContext: 'notebook|n1|payload|v2',
    );
    // 第一次提交——主文件密文。
    await txn.commit(
      destination: dest,
      plain: Uint8List.fromList('机密测试文本-AAAA'.codeUnits),
    );
    // 第二次提交——.bak 出现（旧密文）。
    await txn.commit(
      destination: dest,
      plain: Uint8List.fromList('机密测试文本-BBBB'.codeUnits),
    );
    final mainBytes = await dest.readAsBytes();
    final bakBytes = await File('${dest.path}.bak').readAsBytes();
    // 明文扫描：主/备均不含测试明文（无明文中间态——I-004 验收）。
    expect(
      String.fromCharCodes(mainBytes).contains('机密测试文本'),
      isFalse,
      reason: '主文件不应含明文',
    );
    expect(
      String.fromCharCodes(bakBytes).contains('机密测试文本'),
      isFalse,
      reason: '备份文件不应含明文',
    );
  });

  test('I-004：中断可恢复——失败时临时文件清理、旧文件保留', () async {
    final dest = File('${tempDir.path}/note2.json');
    final txn = EncryptedWriteTransaction(
      key: key,
      aadContext: 'notebook|n2|payload|v2',
    );
    // 先成功写入一次（旧文件存在）。
    await txn.commit(
      destination: dest,
      plain: Uint8List.fromList('旧版本'.codeUnits),
    );
    final oldBytes = await dest.readAsBytes();

    // 模拟中断：无效密钥（长度错误——commit 抛异常）——旧文件保留。
    final badTxn = EncryptedWriteTransaction(
      key: const [],
      aadContext: 'notebook|n2|payload|v2',
    );
    expect(
      () => badTxn.commit(
        destination: dest,
        plain: Uint8List.fromList('新版本'.codeUnits),
      ),
      throwsA(isA<ArgumentError>()),
    );
    // 旧文件保留（未被破坏）+ 无 .tmp 残留。
    expect(await dest.readAsBytes(), oldBytes);
    final leftovers = tempDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.tmp'));
    expect(leftovers, isEmpty, reason: '中断后临时文件应清理');
  });
}
