import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/storage/encryption_service.dart';

/// 审计修复（2026-08-15）：PBKDF2 迭代 10 万 → 60 万（OWASP 2026 推荐）。
/// 军工升级（2026-08-24）：PBKDF2 → Argon2id t=3 m=64MiB p=1 + HKDF-SHA256。
/// 验证 v 字段版本兼容：新数据 v=5（Argon2id）、旧数据 v=2/3/4（PBKDF2）均可解。
void main() {
  // 使用测试参数（m=1024KiB→1MiB, t=1）加速——生产用64MiB t=3。
  const encryption = EncryptionService.test();

  test('新数据 v=5：Argon2id roundtrip', () async {
    final cipher = await encryption.encrypt('秘密内容', 'password123');
    final map = jsonDecode(cipher) as Map<String, dynamic>;
    expect(map['v'], 5, reason: '新格式必须标记 v=5（Argon2id 军工升级）');
    expect(await encryption.decrypt(cipher, 'password123'), '秘密内容');
  });

  test('旧数据 v=2：10 万次迭代兼容解密（不破坏存量笔记）', () async {
    // 手工构造 v=2 旧格式密文（PBKDF2 10 万次 + AES-GCM-256）。
    final salt = List<int>.generate(16, (i) => i);
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 100000,
      bits: 256,
    );
    final key = await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode('old-pass')),
      nonce: salt,
    );
    final aes = AesGcm.with256bits();
    final nonce = List<int>.generate(12, (i) => 255 - i);
    final box = await aes.encrypt(
      utf8.encode('旧格式内容'),
      secretKey: key,
      nonce: nonce,
    );
    final oldJson = jsonEncode({
      's': base64Encode(salt),
      'n': base64Encode(nonce),
      'c': base64Encode(box.cipherText),
      'm': base64Encode(box.mac.bytes),
      'v': 2,
    });
    expect(await encryption.decrypt(oldJson, 'old-pass'), '旧格式内容');
  });

  test('信封 v=5：wrap(Argon2id) roundtrip + 旧信封（v=3 PBKDF2）兼容', () async {
    final masterKey = List<int>.generate(32, (i) => i * 3);
    final env = await encryption.wrapMasterKey(masterKey, 'RECOVER-24-ABCD-WXYZ');
    expect((jsonDecode(env) as Map)['v'], 5, reason: '新信封必须标记 v=5（Argon2id）');
    expect(
      await encryption.unwrapMasterKey(env, 'RECOVER-24-ABCD-WXYZ'),
      masterKey,
    );

    // 模拟旧 v=3 信封（PBKDF2 60 万次）——应能解。
    final salt = List<int>.generate(16, (i) => i * 5);
    final pbkdf2 = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 600000, bits: 256);
    final kek = await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode('RECOVER-OLD')),
      nonce: salt,
    );
    final aes = AesGcm.with256bits();
    final nonce2 = List<int>.generate(12, (i) => 100 + i);
    final box = await aes.encrypt(masterKey, secretKey: kek, nonce: nonce2);
    final oldEnvelope = jsonEncode({
      'salt': base64Encode(salt),
      'n2': base64Encode(nonce2),
      'ek': base64Encode(box.cipherText),
      'm2': base64Encode(box.mac.bytes),
      'v': 3,
    });
    expect(await encryption.unwrapMasterKey(oldEnvelope, 'RECOVER-OLD'), masterKey);
  });
}
