// PBKDF2(600k) 用例在全量高并发下超默认 30s 超时，放宽到 3 分钟。
@Timeout(Duration(minutes: 3))
library;

import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/security/media_crypto_service.dart';

/// H-03 跨域专项基础组件（专家审计 2026-08-15）：MediaCryptoService——
/// BusinessCrypto 层媒体加密（会话密钥注入/清除 + AES-GCM 加解密）。
void main() {
  setUp(MediaCryptoService.instance.clearSessionKey);
  tearDown(MediaCryptoService.instance.clearSessionKey);

  final key = List<int>.generate(32, (i) => i);

  test('媒体加密：注入密钥后往返解密', () async {
    MediaCryptoService.instance.setSessionKey(key);
    final plain = Uint8List.fromList(utf8Encode('机密图片字节'));
    final enc = await MediaCryptoService.instance.encryptBytes(plain);
    expect(enc.length, greaterThan(plain.length));
    final dec = await MediaCryptoService.instance.decryptBytes(enc);
    expect(dec, plain);
  });

  test('媒体加密：未注入密钥时抛 StateError', () async {
    expect(
      () => MediaCryptoService.instance.encryptBytes(Uint8List(4)),
      throwsStateError,
    );
  });

  test('媒体加密：错误密钥解密认证失败', () async {
    MediaCryptoService.instance.setSessionKey(key);
    final enc = await MediaCryptoService.instance.encryptBytes(
      Uint8List.fromList(utf8Encode('数据')),
    );
    MediaCryptoService.instance.setSessionKey(
      List<int>.generate(32, (i) => i + 1),
    );
    expect(
      () => MediaCryptoService.instance.decryptBytes(enc),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });

  test('媒体加密：clearSessionKey 清除后不可用', () async {
    MediaCryptoService.instance.setSessionKey(key);
    expect(MediaCryptoService.instance.isActive, isTrue);
    MediaCryptoService.instance.clearSessionKey();
    expect(MediaCryptoService.instance.isActive, isFalse);
    expect(
      () => MediaCryptoService.instance.decryptBytes(Uint8List(32)),
      throwsStateError,
    );
  });

  test('密码模式：同盐往返 + 不同盐失败（方案 B）', () async {
    final salt = MediaCryptoService.generateSalt();
    await MediaCryptoService.instance.setSessionPassword('secret123', salt);
    final enc = await MediaCryptoService.instance.encryptBytes(
      Uint8List.fromList(utf8Encode('数据')),
    );
    // 同盐重派生（跨会话同全局盐）可解密。
    await MediaCryptoService.instance.setSessionPassword('secret123', salt);
    expect(await MediaCryptoService.instance.decryptBytes(enc), isNotEmpty);
    // 不同盐派生——key 不同——解密认证失败。
    await MediaCryptoService.instance.setSessionPassword(
      'secret123',
      MediaCryptoService.generateSalt(),
    );
    expect(
      () => MediaCryptoService.instance.decryptBytes(enc),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });

  test('每笔记 K_note：AAD 绑定笔记 ID——跨笔记密钥不能互解', () async {
    MediaCryptoService.instance.setNotebookKey('noteA', key);
    final enc = await MediaCryptoService.instance.encryptBytes(
      Uint8List.fromList(utf8Encode('笔记A媒体')),
    );
    // 切换到 noteB（不同 K_note）——AAD 不同——解密认证失败。
    MediaCryptoService.instance.setNotebookKey(
      'noteB',
      List<int>.generate(32, (i) => i + 1),
    );
    expect(
      () => MediaCryptoService.instance.decryptBytes(enc),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
    // 同一笔记 K_note 可解。
    MediaCryptoService.instance.setNotebookKey('noteA', key);
    final dec = await MediaCryptoService.instance.decryptBytes(enc);
    expect(dec, Uint8List.fromList(utf8Encode('笔记A媒体')));
  });

  test('每笔记 K_note：clearNotebookKey 清除后不可用', () async {
    MediaCryptoService.instance.setNotebookKey('noteA', key);
    MediaCryptoService.instance.clearNotebookKey();
    expect(MediaCryptoService.instance.isActive, isFalse);
  });
}

Uint8List utf8Encode(String s) =>
    Uint8List.fromList(s.codeUnits.map((c) => c & 0xFF).toList());
