import 'dart:convert';
import 'dart:typed_data';

import 'package:drawing_notes_app/core/security/vault_key_service.dart';
import 'package:drawing_notes_app/core/storage/vault_file_codec.dart';
import 'package:flutter_test/flutter_test.dart';

/// 批次②：v2 独立密码信封（PBKDF2 现场派生 + 内嵌盐）回归测试。
///
/// 测试用小迭代数（encryptWithPassword 的 iterations 参数），避免
/// 600k PBKDF2 拖慢套件——迭代数本身随 blob 持久化，逻辑路径一致。
void main() {
  const aad = 'doc:test-file';
  final masterKey = VaultKeyService.randomBytes(32);

  Uint8List plainOf(String s) => Uint8List.fromList(utf8.encode(s));

  group('VaultFileCodec v2 密码信封', () {
    test('往返：原字节一致，头部为 DNV+0x02，内嵌盐与迭代数', () async {
      final plain = plainOf('{"document":{"title":"独立密码画作"}}');
      final blob = await VaultFileCodec.encryptWithPassword(
        plain,
        '654321',
        aadContext: aad,
        iterations: 1000,
      );

      expect(VaultFileCodec.isPasswordEnvelope(blob), isTrue);
      expect(VaultFileCodec.isEncrypted(blob), isTrue); // 同为 DNV 家族
      expect(blob[3], 2); // 版本 2

      final round = await VaultFileCodec.decryptWithPassword(
        blob,
        '654321',
        aadContext: aad,
      );
      expect(round, equals(plain));
    });

    test('错误密码 → 拒绝解密（密码错误与篡改统一报错，防侧信道）', () async {
      final blob = await VaultFileCodec.encryptWithPassword(
        plainOf('secret'),
        '654321',
        aadContext: aad,
        iterations: 1000,
      );
      await expectLater(
        VaultFileCodec.decryptWithPassword(blob, '000000', aadContext: aad),
        throwsA(isA<VaultFileException>()),
      );
    });

    test('AAD 绑定：v2 密文不可跨文件移植', () async {
      final blob = await VaultFileCodec.encryptWithPassword(
        plainOf('body'),
        '654321',
        aadContext: 'doc:one',
        iterations: 1000,
      );
      await expectLater(
        VaultFileCodec.decryptWithPassword(
          blob,
          '654321',
          aadContext: 'doc:two',
        ),
        throwsA(isA<VaultFileException>()),
      );
    });

    test('盐随机性：同一密码两次加密 → 密文不同（盐不重复）', () async {
      final a = await VaultFileCodec.encryptWithPassword(
        plainOf('same body'),
        'same-pass',
        aadContext: aad,
        iterations: 1000,
      );
      final b = await VaultFileCodec.encryptWithPassword(
        plainOf('same body'),
        'same-pass',
        aadContext: aad,
        iterations: 1000,
      );
      // 盐区（头部 4..20 字节）必须不同。
      expect(
        List<int>.from(a.sublist(4, 20)),
        isNot(equals(List<int>.from(b.sublist(4, 20)))),
      );
      expect(a, isNot(equals(b)));
    });

    test('v2 不可走主密钥解密：decrypt 抛明确指引（层级独立）', () async {
      final blob = await VaultFileCodec.encryptWithPassword(
        plainOf('body'),
        '654321',
        aadContext: aad,
        iterations: 1000,
      );
      await expectLater(
        VaultFileCodec.decrypt(blob, masterKey, aadContext: aad),
        throwsA(isA<VaultFileException>()),
      );
    });

    test('密文被篡改 → 拒绝解密（fail-closed）', () async {
      final blob = await VaultFileCodec.encryptWithPassword(
        plainOf('secret body'),
        '654321',
        aadContext: aad,
        iterations: 1000,
      );
      blob[blob.length - 1] ^= 0xFF;
      await expectLater(
        VaultFileCodec.decryptWithPassword(blob, '654321', aadContext: aad),
        throwsA(isA<VaultFileException>()),
      );
    });

    test('迭代数随 blob 持久化：换迭代数加密仍可解开', () async {
      final blob = await VaultFileCodec.encryptWithPassword(
        plainOf('body'),
        '654321',
        aadContext: aad,
        iterations: 12345,
      );
      final round = await VaultFileCodec.decryptWithPassword(
        blob,
        '654321',
        aadContext: aad,
      );
      expect(round, equals(plainOf('body')));
    });
  });
}
