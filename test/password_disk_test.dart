import 'dart:io';

import 'package:drawing_notes_app/core/storage/encryption_service.dart';
import 'package:drawing_notes_app/core/storage/password_disk.dart';
import 'package:flutter_test/flutter_test.dart';

/// 密码盘（U盘即钥匙）全闭环回归测试。
///
/// 使用 MockPasswordDisk（固定测试目录）模拟 U 盘，验证：
/// 创建密码盘 → 加密 → 解锁 → U盘丢失恢复 完整流程（设计见
/// docs/PASSWORD_DISK_DESIGN.md）。
void main() {
  late Directory tempDir;
  late MockPasswordDisk disk;
  const encryption = EncryptionService();

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('frogkey_test_');
    disk = MockPasswordDisk(baseDir: tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('创建密码盘：生成 key.frogkey 且格式有效', () async {
    final ok = await disk.createKeyFile(tempDir.path);
    expect(ok, isTrue);

    final valid = await disk.validateKeyFile(tempDir.path);
    expect(valid, isTrue, reason: '生成的密码盘文件应格式有效');

    final file = File('${tempDir.path}${Platform.pathSeparator}key.frogkey');
    expect(await file.exists(), isTrue);
    expect(
      await file.length(),
      PasswordDiskFile.fileLength,
      reason: '密钥文件应为定长 37 字节',
    );
  });

  test('创建→加密→解锁→解密闭环（主路径）', () async {
    await disk.createKeyFile(tempDir.path);
    final key = await disk.readKey(tempDir.path);
    expect(key, isNotNull);
    expect(key!.length, PasswordDiskFile.keyLength);

    // 加密（用主密钥）。
    const secret = '政府涉密会议纪要：2026 年度规划';
    final encrypted = await encryption.encryptWithKey(secret, key);
    expect(encrypted, isNot(contains('会议纪要')), reason: '密文不应含明文');

    // 解锁（重新读密钥）→ 解密。
    final key2 = await disk.readKey(tempDir.path);
    final decrypted = await encryption.decryptWithKey(encrypted, key2!);
    expect(decrypted, secret, reason: '解密回显应与原文一致');
  });

  test('被篡改/缺字段的密文抛 FormatException 而非 TypeError', () async {
    // 字段缺失（如去掉 salt）：必须按文档契约抛 FormatException，
    // 不得以 TypeError 泄漏内部结构。
    await expectLater(
      encryption.decrypt('{"n":"AA==","c":"AA==","m":"AA==","v":2}', 'pwd'),
      throwsA(isA<FormatException>()),
    );
    await expectLater(
      encryption.decrypt('{"s":123,"n":"AA==","c":"AA==","m":"AA=="}', 'pwd'),
      throwsA(isA<FormatException>()),
    );
    // 字段类型错误（salt 为数字）同样抛 FormatException。
    await expectLater(
      encryption.decrypt('{"s":42,"n":"AA==","c":"AA==","m":"AA=="}', 'pwd'),
      throwsA(isA<FormatException>()),
    );
    // 信封缺字段（如去掉 ek）。
    await expectLater(
      encryption.unwrapMasterKey('{"salt":"AA==","n2":"AA==","m2":"AA=="}', 'r'),
      throwsA(isA<FormatException>()),
    );
  });

  test('密钥错误时解密失败（防篡改）', () async {
    await disk.createKeyFile(tempDir.path);
    final key = await disk.readKey(tempDir.path);
    final encrypted = await encryption.encryptWithKey('机密数据', key!);

    final wrongKey = List<int>.generate(32, (i) => i + 1);
    await expectLater(
      encryption.decryptWithKey(encrypted, wrongKey),
      throwsA(isA<Object>()),
      reason: '错误密钥解密应失败（GCM 认证拦截）',
    );
  });

  test('恢复信封：U盘丢失后用恢复密钥找回主密钥', () async {
    await disk.createKeyFile(tempDir.path);
    final key = (await disk.readKey(tempDir.path))!;
    const recoveryKey = 'XG9-7kL-PqR-2sW-8mV-3aZ';

    // 创建时生成信封（U盘密钥被恢复密钥包裹）。
    final envelope = await encryption.wrapMasterKey(key, recoveryKey);
    expect(envelope, isNotEmpty);

    // 模拟 U 盘丢失：删除密钥文件。
    await File('${tempDir.path}${Platform.pathSeparator}key.frogkey').delete();
    expect(await disk.readKey(tempDir.path), isNull, reason: 'U盘已丢失');

    // 用恢复密钥解信封找回主密钥。
    final recovered = await encryption.unwrapMasterKey(envelope, recoveryKey);
    expect(recovered, key, reason: '恢复的主密钥应与原密钥一致');

    // 用恢复出的密钥解密数据。
    final encrypted = await encryption.encryptWithKey('恢复后的数据', recovered);
    final decrypted = await encryption.decryptWithKey(encrypted, recovered);
    expect(decrypted, '恢复后的数据');
  });

  test('恢复密钥错误时解信封失败', () async {
    await disk.createKeyFile(tempDir.path);
    final key = (await disk.readKey(tempDir.path))!;
    final envelope = await encryption.wrapMasterKey(key, 'CORRECT-0000');

    await expectLater(
      encryption.unwrapMasterKey(envelope, 'WRONG-9999'),
      throwsA(isA<Object>()),
      reason: '错误恢复密钥应解封失败',
    );
  });

  test('Mock 密码盘与真实实现文件格式一致（PasswordDiskFile 编解码）', () async {
    final key = PasswordDiskFile.generateKey();
    final bytes = PasswordDiskFile.encode(key);
    final decoded = PasswordDiskFile.decode(bytes);
    expect(decoded, key, reason: '编解码往返一致');
    // 篡改版本字节应判定无效。
    final tampered = List<int>.from(bytes)..[4] = 0x99;
    expect(PasswordDiskFile.decode(tampered), isNull, reason: '篡改应被拒绝');
  });
}
