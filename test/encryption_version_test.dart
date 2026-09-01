import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/storage/encryption_service.dart';

/// 审计修复（2026-08-15）：PBKDF2 迭代 10 万 → 60 万（OWASP 2026 推荐）。
/// 验证 v 字段版本兼容：新数据 v=3（60 万次）、旧数据 v=2（10 万次）均可解。
void main() {
  const encryption = EncryptionService();

  test('新数据 v=3：PBKDF2 60 万次 roundtrip', () async {
    final cipher = await encryption.encrypt('秘密内容', 'password123');
    final map = jsonDecode(cipher) as Map<String, dynamic>;
    expect(map['v'], 3, reason: '新格式必须标记 v=3');
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
}
