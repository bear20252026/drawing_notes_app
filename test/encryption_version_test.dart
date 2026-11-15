// 真 KDF 派生（password→encrypt/decrypt），CI 高负载可超 30s 默认超时。
// @Tags(['kdf'])（v1.17.23 审计修复 #7）：真 KDF 套件必须打标参与 CI 分流。
@Tags(['kdf'])
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/storage/encryption_service.dart';

/// M-06 收口（2026-11-14，删除旧版加密支持）：EncryptionService 仅支持 v5
/// 双保护器格式（Argon2id + AAD）。旧版 v2/v3（PBKDF2 无 AAD）、v4（PBKDF2+AAD）
/// 一律 fail-closed 拒绝。本套件验证旧格式密文不再可解（删除旧版读支持）。
void main() {
  const encryption = EncryptionService();

  test('v5 双保护器：Argon2id roundtrip（唯一支持格式）', () async {
    final cipher = await encryption.encryptWithPasswordV5(
      notebookId: 'nb-ver-1',
      plaintext: '秘密内容',
      password: 'password123',
    );
    final map = jsonDecode(cipher) as Map<String, dynamic>;
    expect(map['v'], 5, reason: '新格式必须标记 v=5');
    expect(map['mode'], 'password');
    expect(EncryptionService.isDualProtectorEnvelope(cipher), isTrue);
    expect(
      await encryption.decryptWithPasswordAad(
        notebookId: 'nb-ver-1',
        encryptedJson: cipher,
        password: 'password123',
      ),
      '秘密内容',
    );
  });

  test('旧版 v=2（PBKDF2 10 万次无 AAD）→ 拒绝（删除旧版支持）', () async {
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
    expect(
      () => encryption.decryptWithPasswordAad(
        notebookId: 'nb-ver-1',
        encryptedJson: oldJson,
        password: 'old-pass',
      ),
      throwsFormatException,
      reason: '旧版 v2 不再支持，fail-closed 拒绝',
    );
  });

  test('旧版 v=3（PBKDF2 60 万次无 AAD）→ 拒绝（删除旧版支持）', () async {
    final salt = List<int>.generate(16, (i) => i + 1);
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 600000,
      bits: 256,
    );
    final key = await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode('old-pass-3')),
      nonce: salt,
    );
    final aes = AesGcm.with256bits();
    final nonce = List<int>.generate(12, (i) => i);
    final box = await aes.encrypt(
      utf8.encode('旧格式 v3 内容'),
      secretKey: key,
      nonce: nonce,
    );
    final oldJson = jsonEncode({
      's': base64Encode(salt),
      'n': base64Encode(nonce),
      'c': base64Encode(box.cipherText),
      'm': base64Encode(box.mac.bytes),
      'v': 3,
    });
    expect(
      () => encryption.decryptWithPasswordAad(
        notebookId: 'nb-ver-1',
        encryptedJson: oldJson,
        password: 'old-pass-3',
      ),
      throwsFormatException,
      reason: '旧版 v3 不再支持，fail-closed 拒绝',
    );
  });

  test('旧版 v=4（PBKDF2+AAD 载荷）→ 拒绝（删除旧版支持）', () async {
    // v4 载荷格式 {mode:'payload', v:4, s, n, c, m}——无 v5 双保护器槽位。
    final oldJson = jsonEncode({
      'mode': 'payload',
      'v': 4,
      's': base64Encode(List<int>.generate(16, (i) => i)),
      'n': base64Encode(List<int>.generate(12, (i) => i)),
      'c': base64Encode(List<int>.generate(32, (i) => i)),
      'm': base64Encode(List<int>.generate(16, (i) => i)),
    });
    expect(
      () => encryption.decryptWithPasswordAad(
        notebookId: 'nb-ver-1',
        encryptedJson: oldJson,
        password: 'any-pass',
      ),
      throwsFormatException,
      reason: '旧版 v4 不再支持，fail-closed 拒绝',
    );
  });
}