import 'dart:convert';
import 'dart:typed_data';

import 'package:drawing_notes_app/core/security/kdf_params.dart';
import 'package:drawing_notes_app/core/security/vault_key_service.dart';
import 'package:drawing_notes_app/core/storage/vault_file_codec.dart';
import 'package:flutter_test/flutter_test.dart';

/// M-06 收口（2026-11-14，删除旧版加密支持）：v2 独立密码信封（PBKDF2
/// 现场派生 + 内嵌盐）的加解密方法已移除。本套件验证 v2 旧信封不再可解——
/// 主密钥解密路径抛明确指引（fail-closed），存量旧数据须先升级 v3。
///
/// 真 KDF 口径（2026-11-20）：v3 用例注入 [KdfParams.testLight]（Argon2id
/// 8MiB/t1/p1，仍是 Argon2id，仅换工作因子）——本套件验的是信封格式、往返
/// 与 fail-closed 语义，与密钥成本无关，故走 testLight 腿（全仓同口径，见
/// test/architecture/kdf_suite_hygiene_test.dart）。
/// 起因：master CI（2d11e06c）本文件 v3 用例在满并发 Windows runner 上撞 30s
/// 默认超时（无 @Timeout 注解），本地秒过 ⇒ 环境敏感假红。
void main() {
  const aad = 'doc:test-file';
  final masterKey = VaultKeyService.randomBytes(32);

  Uint8List plainOf(String s) => Uint8List.fromList(utf8.encode(s));

  /// 手工构造 v2 旧信封字节（DNV + 0x02 + salt(16) + iter(4) + 载荷）。
  /// 载荷内容任意（v2 解密已删除，不再实际解密——只验证识别与拒绝）。
  Uint8List legacyV2Blob() {
    final salt = List<int>.generate(16, (i) => i);
    final iter = ByteData(4)..setUint32(0, 600000);
    final payload = List<int>.generate(48, (i) => i); // nonce+密文+tag 占位
    return Uint8List.fromList([
      0x44, 0x4E, 0x56, 0x02, // DNV + v2
      ...salt,
      ...iter.buffer.asUint8List(),
      ...payload,
    ]);
  }

  group('VaultFileCodec v2 旧信封（删除旧版支持）', () {
    test('v2 旧信封仍被识别为密码信封（读路径据此要求会话密码）', () {
      final blob = legacyV2Blob();
      expect(VaultFileCodec.isPasswordEnvelope(blob), isTrue);
      expect(VaultFileCodec.isPasswordEnvelopeV2(blob), isTrue);
      expect(VaultFileCodec.isEncrypted(blob), isTrue); // 同为 DNV 家族
      expect(blob[3], 2); // 版本 2
      expect(VaultFileCodec.isV3Envelope(blob), isFalse);
    });

    test('v2 不可走主密钥解密：decrypt 抛明确指引（fail-closed）', () async {
      final blob = legacyV2Blob();
      await expectLater(
        VaultFileCodec.decrypt(blob, masterKey, aadContext: aad),
        throwsA(isA<VaultFileException>()),
        reason: 'v2 密码信封不走主密钥路径，删除旧版后仍 fail-closed',
      );
    });

    test('v3 双保护器信封：Argon2id 往返（唯一支持的文件密码格式）', () async {
      final plain = plainOf('{"document":{"title":"独立密码画作"}}');
      final blob = await VaultFileCodec.encryptWithPasswordV3(
        plain,
        '654321',
        kdf: KdfParams.testLight,
        aadContext: aad,
      );
      expect(VaultFileCodec.isV3Envelope(blob), isTrue);
      expect(VaultFileCodec.isPasswordEnvelopeV2(blob), isFalse);
      final unlock = await VaultFileCodec.unlockWithPasswordV3(
        blob,
        '654321',
        aadContext: aad,
      );
      expect(unlock.plain, equals(plain));
    });

    test('v3 错误密码 → 拒绝解密（fail-closed）', () async {
      final blob = await VaultFileCodec.encryptWithPasswordV3(
        plainOf('secret'),
        '654321',
        kdf: KdfParams.testLight,
        aadContext: aad,
      );
      await expectLater(
        VaultFileCodec.unlockWithPasswordV3(blob, '000000', aadContext: aad),
        throwsA(isA<VaultFileException>()),
      );
    });

    test('v3 AAD 绑定：密文不可跨文件移植', () async {
      final blob = await VaultFileCodec.encryptWithPasswordV3(
        plainOf('body'),
        '654321',
        kdf: KdfParams.testLight,
        aadContext: 'doc:one',
      );
      await expectLater(
        VaultFileCodec.unlockWithPasswordV3(
          blob,
          '654321',
          aadContext: 'doc:two',
        ),
        throwsA(isA<VaultFileException>()),
      );
    });
  });
}