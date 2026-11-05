import 'dart:convert';
import 'dart:typed_data';

import 'package:drawing_notes_app/core/security/vault_key_service.dart';
import 'package:drawing_notes_app/core/storage/vault_file_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final key = VaultKeyService.randomBytes(32);

  Uint8List plainOf(String s) => Uint8List.fromList(utf8.encode(s));

  test('加解密往返：原字节一致，且带 DNV 魔数头', () async {
    final plain = plainOf('{"document":{"title":"机密"}}');
    final blob = await VaultFileCodec.encrypt(plain, key, aadContext: 'doc:a1');

    expect(VaultFileCodec.isEncrypted(blob), isTrue);
    expect(blob[0], 0x44); // 'D'
    expect(blob[1], 0x4E); // 'N'
    expect(blob[2], 0x56); // 'V'
    expect(blob[3], 1); // 版本

    final round = await VaultFileCodec.decrypt(blob, key, aadContext: 'doc:a1');
    expect(round, equals(plain));
  });

  test('明文嗅探：普通 JSON/PNG 开头不误判为信封', () {
    expect(VaultFileCodec.isEncrypted(plainOf('{"document":{}}')), isFalse);
    expect(
      VaultFileCodec.isEncrypted(Uint8List.fromList(<int>[0x89, 0x50, 0x4E])),
      isFalse,
    );
  });

  test('篡改防护：密文任一比特被改 → 拒绝解密（fail-closed）', () async {
    final blob = await VaultFileCodec.encrypt(
      plainOf('secret body'),
      key,
      aadContext: 'doc:a1',
    );
    blob[blob.length - 1] ^= 0xFF; // 翻转 tag 最后一字节
    expect(
      () => VaultFileCodec.decrypt(blob, key, aadContext: 'doc:a1'),
      throwsA(isA<VaultFileException>()),
    );
  });

  test('错误密钥 → 拒绝解密', () async {
    final blob = await VaultFileCodec.encrypt(
      plainOf('secret body'),
      key,
      aadContext: 'doc:a1',
    );
    final wrong = VaultKeyService.randomBytes(32);
    expect(
      () => VaultFileCodec.decrypt(blob, wrong, aadContext: 'doc:a1'),
      throwsA(isA<VaultFileException>()),
    );
  });

  test('AAD 绑定：密文不可跨文件移植（swap 攻击防护）', () async {
    final blob = await VaultFileCodec.encrypt(
      plainOf('doc one body'),
      key,
      aadContext: 'doc:one',
    );
    expect(
      () => VaultFileCodec.decrypt(blob, key, aadContext: 'doc:two'),
      throwsA(isA<VaultFileException>()),
    );
  });

  test('未知信封版本 → 拒绝解密（前向兼容守卫）', () async {
    final blob = await VaultFileCodec.encrypt(
      plainOf('body'),
      key,
      aadContext: 'doc:a1',
    );
    blob[3] = 99; // 版本号篡改
    expect(
      () => VaultFileCodec.decrypt(blob, key, aadContext: 'doc:a1'),
      throwsA(isA<VaultFileException>()),
    );
  });

  test('R53：载荷被截断到过短 → VaultFileException（不得逃逸 VaultUnlockException）', () async {
    // R53 审计：`VaultKeyService.aeadDecrypt` 对 payload.length <= 28 抛的是
    // VaultUnlockException('密文长度不合法')，而 VaultFileCodec 的对外契约是
    // VaultFileException。调用方 StorageFilePasswordManager.verifyFilePassword
    // 只 catch VaultFileException——接不住就逃逸到 PinPad._submit（无 try/catch）
    // ⇒ 解锁界面假死（不抖、不报错）。
    final blob = await VaultFileCodec.encrypt(
      plainOf('secret body'),
      key,
      aadContext: 'doc:a1',
    );
    // 4 字节头 + 28 字节载荷（= aeadDecrypt 的截断阈值）⇒ 触发 VaultUnlockException。
    final truncated = Uint8List.fromList(blob.sublist(0, 4 + 28));
    expect(
      () => VaultFileCodec.decrypt(truncated, key, aadContext: 'doc:a1'),
      throwsA(isA<VaultFileException>()),
      reason: '过短载荷必须转成 VaultFileException，否则解锁界面假死',
    );
  });
}
