import 'dart:convert';
import 'dart:typed_data';

import 'package:drawing_notes_app/core/security/kdf_params.dart';
import 'package:drawing_notes_app/core/security/vault_key_service.dart';
import 'package:drawing_notes_app/core/storage/vault_file_codec.dart';
import 'package:flutter_test/flutter_test.dart';

/// N4 批 2：v3 双保护器信封（随机 DEK + 密码槽 + 可选重置盘槽）测试。
///
/// 测试用 Argon2id 轻量参数（kdf 参数随槽位 JSON 持久化），避免生产档
/// 348ms 拖慢套件——逻辑路径与生产一致。
void main() {
  const aad = 'doc:test-v3';
  const usbKey = <int>[
    // 32 字节固定测试钥匙（重置密码盘 FROG v1 文件的 32B 语义等价物）。
    0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, //
    0x99, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0x10, 0x20, //
    0x30, 0x40, 0x50, 0x60, 0x70, 0x80, 0x90, 0xA0, //
    0xB0, 0xC0, 0xD0, 0xE0, 0xF0, 0x01, 0x02, 0x03,
  ];
  final wrongUsbKey = VaultKeyService.randomBytes(32);

  Uint8List plainOf(String s) => Uint8List.fromList(utf8.encode(s));

  /// 建一个绑定重置盘的 v3 信封。
  Future<Uint8List> sealedWithUsb({
    String password = '654321',
    KdfParams kdf = KdfParams.testLight,
  }) async {
    final dek = VaultFileCodec.generateDek();
    final usbWrapped = await VaultFileCodec.wrapUsbSlotV3(
      usbKey: usbKey,
      dek: dek,
      aadContext: aad,
    );
    return VaultFileCodec.encryptWithPasswordV3(
      plainOf('{"document":{"title":"v3画作"}}'),
      password,
      aadContext: aad,
      kdf: kdf,
      dek: dek,
      usbWrapped: usbWrapped,
    );
  }

  group('VaultFileCodec v3 双保护器信封', () {
    test('往返：原字节一致，头部为 DNV+0x03，默认无 USB 槽', () async {
      final plain = plainOf('{"document":{"title":"v3画作"}}');
      final blob = await VaultFileCodec.encryptWithPasswordV3(
        plain,
        '654321',
        aadContext: aad,
        kdf: KdfParams.testLight,
      );

      expect(VaultFileCodec.isEncrypted(blob), isTrue);
      expect(VaultFileCodec.isPasswordEnvelope(blob), isTrue);
      expect(VaultFileCodec.isV3Envelope(blob), isTrue);
      expect(blob[3], 3);
      expect(VaultFileCodec.hasUsbSlotV3(blob), isFalse);

      final unlock = await VaultFileCodec.unlockWithPasswordV3(
        blob,
        '654321',
        aadContext: aad,
      );
      expect(unlock.plain, equals(plain));
      expect(unlock.dek.length, 32);
      expect(unlock.usbWrapped, isNull);
    });

    test('错误密码 → 拒绝解锁；错误 context → 拒绝（AAD 绑定）', () async {
      final blob = await VaultFileCodec.encryptWithPasswordV3(
        plainOf('secret'),
        '654321',
        aadContext: aad,
        kdf: KdfParams.testLight,
      );
      await expectLater(
        VaultFileCodec.unlockWithPasswordV3(blob, '000000', aadContext: aad),
        throwsA(isA<VaultFileException>()),
      );
      await expectLater(
        VaultFileCodec.unlockWithPasswordV3(
          blob,
          '654321',
          aadContext: 'doc:other',
        ),
        throwsA(isA<VaultFileException>()),
      );
    });

    test('载密被篡改 → 拒绝解锁（fail-closed）', () async {
      final blob = await VaultFileCodec.encryptWithPasswordV3(
        plainOf('secret'),
        '654321',
        aadContext: aad,
        kdf: KdfParams.testLight,
      );
      blob[blob.length - 1] ^= 0xFF;
      await expectLater(
        VaultFileCodec.unlockWithPasswordV3(blob, '654321', aadContext: aad),
        throwsA(isA<VaultFileException>()),
      );
    });

    test('绑定重置盘：hasUsbSlot 识别，USB 钥匙可解锁，错钥拒绝', () async {
      final blob = await sealedWithUsb();
      expect(VaultFileCodec.hasUsbSlotV3(blob), isTrue);

      final unlock = await VaultFileCodec.unlockWithUsbKeyV3(
        blob,
        usbKey,
        aadContext: aad,
      );
      expect(unlock.plain, equals(plainOf('{"document":{"title":"v3画作"}}')));
      expect(unlock.usbWrapped, isNotNull);

      await expectLater(
        VaultFileCodec.unlockWithUsbKeyV3(blob, wrongUsbKey, aadContext: aad),
        throwsA(isA<VaultFileException>()),
      );
      // AAD 绑定：USB 槽位不可移植到其他文件。
      await expectLater(
        VaultFileCodec.unlockWithUsbKeyV3(blob, usbKey, aadContext: 'doc:x'),
        throwsA(isA<VaultFileException>()),
      );
    });

    test('重绕密码槽：载荷与 USB 槽位字节不动，新密码可开旧密码失效',
        () async {
      final blob = await sealedWithUsb();
      // 载荷起点 = 8 + jsonLen（重绕前后应逐字节一致——LUKS 同款）。
      final jsonLen =
          ByteData.sublistView(blob, 4, 8).getUint32(0);
      final oldPayload = blob.sublist(8 + jsonLen);
      final oldUsbWrapped = (await VaultFileCodec.unlockWithUsbKeyV3(
        blob,
        usbKey,
        aadContext: aad,
      )).usbWrapped!;

      final rewrap = await VaultFileCodec.rewrapPasswordSlotV3(
        blob,
        usbKey,
        '999999',
        aadContext: aad,
        kdf: KdfParams.testLight,
      );

      final newJsonLen =
          ByteData.sublistView(rewrap.blob, 4, 8).getUint32(0);
      final newPayload = rewrap.blob.sublist(8 + newJsonLen);
      expect(newPayload, equals(oldPayload)); // 载荷密文一字节不动
      expect(rewrap.usbWrapped, equals(oldUsbWrapped)); // USB 槽位原样保留

      // 新密码可解锁，旧密码被拒。
      final unlock = await VaultFileCodec.unlockWithPasswordV3(
        rewrap.blob,
        '999999',
        aadContext: aad,
      );
      expect(unlock.plain, equals(plainOf('{"document":{"title":"v3画作"}}')));
      await expectLater(
        VaultFileCodec.unlockWithPasswordV3(
          rewrap.blob,
          '654321',
          aadContext: aad,
        ),
        throwsA(isA<VaultFileException>()),
      );
      // USB 钥匙继续有效（槽位保留）。
      final usbUnlock = await VaultFileCodec.unlockWithUsbKeyV3(
        rewrap.blob,
        usbKey,
        aadContext: aad,
      );
      expect(usbUnlock.plain, equals(unlock.plain));
      // 重绕结果仍带 USB 槽位标记。
      expect(VaultFileCodec.hasUsbSlotV3(rewrap.blob), isTrue);
    });

    test('错误重置盘钥匙 → 重绕拒绝（fail-closed）', () async {
      final blob = await sealedWithUsb();
      await expectLater(
        VaultFileCodec.rewrapPasswordSlotV3(
          blob,
          wrongUsbKey,
          '999999',
          aadContext: aad,
          kdf: KdfParams.testLight,
        ),
        throwsA(isA<VaultFileException>()),
      );
    });

    test('结构守卫：USB 槽位不配 DEK 传入直接拒绝（防槽位静默失效）', () async {
      final usbWrapped = await VaultFileCodec.wrapUsbSlotV3(
        usbKey: usbKey,
        dek: VaultFileCodec.generateDek(),
        aadContext: aad,
      );
      expect(
        () => VaultFileCodec.encryptWithPasswordV3(
          plainOf('body'),
          '654321',
          aadContext: aad,
          kdf: KdfParams.testLight,
          usbWrapped: usbWrapped, // 缺 dek
        ),
        throwsArgumentError,
      );
    });

    // ---- v2/v3 并存兼容（旧文件只读兼容承诺） ----

    test('v2 文件兼容：isPasswordEnvelope 含 v2，v3 解锁器拒绝 v2', () async {
      final v2blob = await VaultFileCodec.encryptWithPassword(
        plainOf('old v2 body'),
        '654321',
        aadContext: aad,
        iterations: 1000,
      );
      expect(VaultFileCodec.isPasswordEnvelope(v2blob), isTrue);
      expect(VaultFileCodec.isPasswordEnvelopeV2(v2blob), isTrue);
      expect(VaultFileCodec.isV3Envelope(v2blob), isFalse);
      expect(VaultFileCodec.hasUsbSlotV3(v2blob), isFalse);

      // v2 仍走原解密路径。
      final round = await VaultFileCodec.decryptWithPassword(
        v2blob,
        '654321',
        aadContext: aad,
      );
      expect(round, equals(plainOf('old v2 body')));

      // v3 解锁器不接 v2（结构不同，明确报错）。
      await expectLater(
        VaultFileCodec.unlockWithPasswordV3(v2blob, '654321', aadContext: aad),
        throwsA(isA<VaultFileException>()),
      );
    });

    test('v3 文件不可走 v2 解密路径（头部结构不同，明确报错）', () async {
      final blob = await VaultFileCodec.encryptWithPasswordV3(
        plainOf('body'),
        '654321',
        aadContext: aad,
        kdf: KdfParams.testLight,
      );
      await expectLater(
        VaultFileCodec.decryptWithPassword(blob, '654321', aadContext: aad),
        throwsA(isA<VaultFileException>()),
      );
      // 主密钥路径同样拒绝（层级独立）。
      await expectLater(
        VaultFileCodec.decrypt(
          blob,
          VaultKeyService.randomBytes(32),
          aadContext: aad,
        ),
        throwsA(isA<VaultFileException>()),
      );
    });

    test('头部损坏：截断 / JSON 篡改 → 拒绝（fail-closed）', () async {
      final blob = await sealedWithUsb();
      // 截断到只剩头部。
      final truncated = blob.sublist(0, 8);
      await expectLater(
        VaultFileCodec.unlockWithPasswordV3(
          Uint8List.fromList(truncated),
          '654321',
          aadContext: aad,
        ),
        throwsA(isA<VaultFileException>()),
      );
      // jsonLen 撒谎（超出文件长度）。
      final lying = Uint8List.fromList(blob);
      ByteData.sublistView(lying, 4, 8).setUint32(0, 0xFFFFFF);
      await expectLater(
        VaultFileCodec.unlockWithPasswordV3(lying, '654321', aadContext: aad),
        throwsA(isA<VaultFileException>()),
      );
    });
  });
}
