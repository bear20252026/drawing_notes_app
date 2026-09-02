/// 批B：Argon2id KDF 升级迁移兼容测试。
///
/// 核心契约（LUKS2 每槽位独立 KDF 语义）：
/// 1. **旧数据只读兼容**——批B 前的槽位（无 `kdf` 字段 = PBKDF2）全部可解，
///    且解锁本身不偷偷改写文件（fail-closed 之外的静默写是事故源）；
/// 2. **改密懒升级**——changePin / rewrap / changeFilePassword 换盐重绕时，
///    新槽位自动携带 Argon2id KDF 字段（主密钥/DEK/载荷密文不动）；
/// 3. USB 重置盘槽全程原样保留（无 KDF，跨版本通用）。
///
/// 旧格式构造方式：全部经公开 API 生成（显式 pbkdf2 小迭代 / 可注入
/// [KdfParams.newSlotDefault]），再从信封中剥除 `kdf` 字段还原旧形态——
/// 不触碰任何私有 AAD/序列化细节。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drawing_notes_app/core/security/kdf_params.dart';
import 'package:drawing_notes_app/core/security/vault_key_service.dart';
import 'package:drawing_notes_app/core/storage/encryption_service.dart';
import 'package:drawing_notes_app/core/storage/vault_file_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('KdfParams 参数描述符', () {
    test('生产默认 = Argon2id 64MiB t2 p2（批A 实测定案）', () {
      const p = KdfParams.argon2idProduction;
      expect(p.kdf, KdfParams.kdfArgon2id);
      expect(p.memoryKiB, 65536);
      expect(p.timeCost, 2);
      expect(p.parallelism, 2);
      // 生产默认不可被测试注入污染（static 可变量初值恒定）。
      // ignore: unnecessary_type_check
      expect(KdfParams.newSlotDefault is KdfParams, isTrue);
    });

    test('toSlotJson：argon2id 输出 m/t/p；pbkdf2 输出 iter', () {
      expect(
        KdfParams.argon2idProduction.toSlotJson(),
        {'kdf': 'argon2id', 'm': 65536, 't': 2, 'p': 2},
      );
      expect(
        const KdfParams.pbkdf2(600000).toSlotJson(),
        {'kdf': 'pbkdf2', 'iter': 600000},
      );
    });

    test('fromSlotJson：两种形态往返；kdf 缺失回退 legacyDefault', () {
      final a = KdfParams.fromSlotJson(
        KdfParams.argon2idProduction.toSlotJson(),
        legacyDefault: const KdfParams.pbkdf2(1),
      );
      expect(a, KdfParams.argon2idProduction);

      final b = KdfParams.fromSlotJson(
        const KdfParams.pbkdf2(600000).toSlotJson(),
        legacyDefault: const KdfParams.pbkdf2(1),
      );
      expect(b, const KdfParams.pbkdf2(600000));

      // 批B 前旧槽位：无 kdf 字段（可能仅有 iter）→ 调用方提供的旧参数。
      final legacy = KdfParams.fromSlotJson(
        {'iter': 600000},
        legacyDefault: const KdfParams.pbkdf2(600000),
      );
      expect(legacy, const KdfParams.pbkdf2(600000));
      expect(
        KdfParams.fromSlotJson(
          const {},
          legacyDefault: const KdfParams.pbkdf2(42),
        ),
        const KdfParams.pbkdf2(42),
      );
    });

    test('fromSlotJson：畸形/未知 KDF fail-closed 抛 ArgumentError', () {
      // argon2id 缺 m / 非法值。
      for (final bad in [
        {'kdf': 'argon2id', 't': 2, 'p': 2},
        {'kdf': 'argon2id', 'm': 0, 't': 2, 'p': 2},
        {'kdf': 'argon2id', 'm': 65536, 't': 2},
      ]) {
        expect(
          () => KdfParams.fromSlotJson(bad, legacyDefault: const KdfParams.pbkdf2(1)),
          throwsArgumentError,
          reason: '$bad 应拒绝',
        );
      }
      // pbkdf2 缺 iter。
      expect(
        () => KdfParams.fromSlotJson(
          {'kdf': 'pbkdf2'},
          legacyDefault: const KdfParams.pbkdf2(1),
        ),
        throwsArgumentError,
      );
      // 未知算法名。
      expect(
        () => KdfParams.fromSlotJson(
          {'kdf': 'scrypt', 'n': 1},
          legacyDefault: const KdfParams.pbkdf2(1),
        ),
        throwsArgumentError,
      );
    });

    test('相等性：同参数相等；不同 KDF/参数不等', () {
      expect(
        KdfParams.argon2idProduction,
        KdfParams.argon2idProduction,
      );
      expect(
        KdfParams.argon2idProduction,
        isNot(equals(KdfParams.testLight)),
      );
      expect(
        const KdfParams.pbkdf2(600000),
        isNot(equals(const KdfParams.pbkdf2(100000))),
      );
      expect(
        KdfParams.argon2idProduction.hashCode,
        KdfParams.argon2idProduction.hashCode,
      );
    });
  });

  group('保险库（VaultKeyService）迁移', () {
    late Directory tempDir;
    late File vaultFile;
    late VaultKeyService service;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('kdf_vault_');
      vaultFile = File(
        '${tempDir.path}${Platform.pathSeparator}vault.json',
      );
      service = VaultKeyService(
        vaultFileResolver: () async => vaultFile,
        newSlotKdf: KdfParams.testLight,
      );
    });

    tearDown(() async {
      service.lock();
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('v2 旧文件（PBKDF2 槽位无 kdf）解锁成功；解锁不改写文件', () async {
      // 手工构造批B 前 v2 保险库：槽位 {type,salt,wrapped}，doc 级 iter。
      final salt = VaultKeyService.randomBytes(16);
      final mk = VaultKeyService.randomBytes(32);
      final kek = await VaultKeyService.deriveKek(
        '9527',
        salt,
        const KdfParams.pbkdf2(2000),
      );
      final wrapped = await VaultKeyService.aeadEncrypt(
        kek,
        mk,
        'drawing-notes|vault|v1'.codeUnits,
      );
      final legacyJson = jsonEncode({
        'v': 2,
        'kdf': 'PBKDF2-HMAC-SHA256',
        'iter': 2000,
        'slots': [
          {'type': 'pin', 'salt': base64Encode(salt), 'wrapped': base64Encode(wrapped)},
        ],
      });
      await vaultFile.writeAsString(legacyJson);

      await service.unlock('9527');
      expect(service.isUnlocked, isTrue);
      expect(service.masterKey, equals(mk));

      // 只读兼容：解锁本身不偷偷升级文件（升级只发生在改密）。
      expect(await vaultFile.readAsString(), legacyJson);

      service.lock();
      await service.unlock('9527'); // 重解锁仍可读
      expect(service.masterKey, equals(mk));
    });

    test('changePin 懒升级：新槽 Argon2id + 主密钥不变 + 旧 PIN 失效 + USB 槽保留', () async {
      await service.initialize('9527');
      final usbKey = VaultKeyService.randomBytes(32);
      await service.addUsbKeySlot(externalKey: usbKey);
      final mkBefore = service.masterKey;

      // 初始新槽即 Argon2id（newSlotKdf 注入 testLight）。
      var doc =
          jsonDecode(await vaultFile.readAsString()) as Map<String, dynamic>;
      var pin = (doc['slots'] as List).cast<Map<String, dynamic>>().first;
      expect(doc['v'], 3);
      expect(pin['kdf'], KdfParams.kdfArgon2id);
      expect(pin['m'], KdfParams.testLight.memoryKiB);

      await service.changePin(oldPin: '9527', newPin: '8888');
      expect(service.masterKey, equals(mkBefore));

      doc = jsonDecode(await vaultFile.readAsString()) as Map<String, dynamic>;
      final slots = (doc['slots'] as List).cast<Map<String, dynamic>>();
      pin = slots.firstWhere((s) => s['type'] == 'pin');
      expect(pin['kdf'], KdfParams.kdfArgon2id);
      expect(slots.any((s) => s['type'] == 'usb'), isTrue); // USB 槽保留

      service.lock();
      await service.unlock('8888');
      expect(service.masterKey, equals(mkBefore));
      service.lock();
      await expectLater(
        service.unlock('9527'),
        throwsA(isA<VaultUnlockException>()),
      );
    });
  });

  group('DNV v3 信封（VaultFileCodec）迁移', () {
    const aad = 'doc:kdf-mig-1';
    final plain = Uint8List.fromList(utf8.encode('旧信封里的机密画作'));

    /// 从 v3 信封剥除密码槽 `kdf` 字段，还原批B 前形态（重算头部长度）。
    Uint8List stripSlotKdf(Uint8List blob) {
      final jsonLen = ByteData.sublistView(blob, 4, 8).getUint32(0);
      final header =
          jsonDecode(utf8.decode(blob.sublist(8, 8 + jsonLen)))
              as Map<String, dynamic>;
      for (final s in (header['slots'] as List).cast<Map<String, dynamic>>()) {
        s.remove('kdf');
      }
      final newJson = utf8.encode(jsonEncode(header));
      final len = ByteData(4)..setUint32(0, newJson.length);
      return Uint8List.fromList([
        ...blob.sublist(0, 4),
        ...len.buffer.asUint8List(),
        ...newJson,
        ...blob.sublist(8 + jsonLen),
      ]);
    }

    test('旧槽位（无 kdf = PBKDF2）解锁成功，明文一致', () async {
      final blob = await VaultFileCodec.encryptWithPasswordV3(
        plain,
        '777888',
        aadContext: aad,
        kdf: const KdfParams.pbkdf2(1000),
      );
      final legacy = stripSlotKdf(blob);
      expect(VaultFileCodec.isV3Envelope(legacy), isTrue);

      final unlocked = await VaultFileCodec.unlockWithPasswordV3(
        legacy,
        '777888',
        aadContext: aad,
      );
      expect(unlocked.plain, plain);
    });

    test('rewrap 懒升级：新槽 Argon2id + 载荷与 USB 槽字节原样 + 旧密码失效', () async {
      // 两步构造带 USB 槽的旧格式信封：1) 无 USB 生成 → 取 DEK；
      // 2) USB 包裹同一把 DEK → 带 usbWrapped 重生成（生产同构）。
      final usbKey = VaultKeyService.randomBytes(32);
      final seed = await VaultFileCodec.encryptWithPasswordV3(
        plain,
        '777888',
        aadContext: aad,
        kdf: const KdfParams.pbkdf2(1000),
      );
      final dek = (await VaultFileCodec.unlockWithPasswordV3(
        seed,
        '777888',
        aadContext: aad,
      ))
          .dek;
      final realUsbWrapped = await VaultKeyService.aeadEncrypt(
        usbKey,
        dek,
        // USB 槽 AAD 稳定为 v1（与开屏密码盘槽位钥匙通用，跨版本不变）。
        'drawing-notes|file-slot|usb|v1|$aad'.codeUnits,
      );
      final withUsb = await VaultFileCodec.encryptWithPasswordV3(
        plain,
        '777888',
        aadContext: aad,
        kdf: const KdfParams.pbkdf2(1000),
        dek: dek,
        usbWrapped: realUsbWrapped,
      );
      final legacy = stripSlotKdf(withUsb);
      final jsonLenOld = ByteData.sublistView(legacy, 4, 8).getUint32(0);
      final payloadOld = legacy.sublist(8 + jsonLenOld);

      final rewrapped = await VaultFileCodec.rewrapPasswordSlotV3(
        legacy,
        usbKey,
        '333444',
        aadContext: aad,
      );

      // 载荷字节与 USB 槽字节原样（LUKS 槽位语义）。
      final jsonLenNew =
          ByteData.sublistView(rewrapped.blob, 4, 8).getUint32(0);
      expect(
        rewrapped.blob.sublist(8 + jsonLenNew),
        payloadOld,
      );
      expect(rewrapped.usbWrapped, realUsbWrapped);

      // 新槽位为 Argon2id（newSlotDefault 注入 testLight）。
      final header = jsonDecode(
        utf8.decode(
          rewrapped.blob.sublist(
            8,
            8 + jsonLenNew,
          ),
        ),
      ) as Map<String, dynamic>;
      final pwSlot =
          (header['slots'] as List).cast<Map<String, dynamic>>().first;
      expect(pwSlot['kdf'], KdfParams.kdfArgon2id);

      // 新密码可解、旧密码拒绝、U 盘重置通道仍通。
      expect(
        (await VaultFileCodec.unlockWithPasswordV3(
          rewrapped.blob,
          '333444',
          aadContext: aad,
        ))
            .plain,
        plain,
      );
      await expectLater(
        VaultFileCodec.unlockWithPasswordV3(
          rewrapped.blob,
          '777888',
          aadContext: aad,
        ),
        throwsA(isA<VaultFileException>()),
      );
    });
  });

  group('v5 载荷（EncryptionService bd）迁移', () {
    const svc = EncryptionService();
    const id = 'bd_kdf_mig';
    const pw = 'old-pass-1';

    test('旧 pw 槽（无 kdf = PBKDF2 it）解锁成功；改密懒升级 Argon2id', () async {
      // 生成槽位（注入 pbkdf2(1000)）→ 删 kdf 字段 → 批B 前旧形态。
      KdfParams.newSlotDefault = const KdfParams.pbkdf2(1000);
      final envelope = await svc.encryptBlockDocPasswordV5(
        docId: id,
        plaintext: '旧载荷机密',
        password: pw,
      );
      KdfParams.newSlotDefault = KdfParams.testLight;

      final map = jsonDecode(envelope) as Map<String, dynamic>;
      final pwSlot = (map['slots'] as Map)['pw'] as Map<String, dynamic>;
      expect(pwSlot.remove('kdf'), KdfParams.kdfPbkdf2);
      // 旧格式字段名是 it（批B 新写为 iter）——改名还原旧形态。
      pwSlot['it'] = pwSlot.remove('iter');
      expect(pwSlot['it'], 1000);
      final legacyEnvelope = jsonEncode(map);

      // 旧格式解锁成功。
      expect(
        await svc.decryptBlockDocPassword(
          docId: id,
          encryptedJson: legacyEnvelope,
          password: pw,
        ),
        '旧载荷机密',
      );

      // 改密 → 懒升级 Argon2id；载荷与 USB 槽语义保持。
      final upgraded = await svc.changeBlockDocPasswordV5(
        docId: id,
        encryptedJson: legacyEnvelope,
        oldPassword: pw,
        newPassword: 'new-pass-2',
      );
      final up = jsonDecode(upgraded) as Map<String, dynamic>;
      final upPw = (up['slots'] as Map)['pw'] as Map<String, dynamic>;
      expect(upPw['kdf'], KdfParams.kdfArgon2id);
      expect(upPw['m'], KdfParams.testLight.memoryKiB);

      expect(
        await svc.decryptBlockDocPassword(
          docId: id,
          encryptedJson: upgraded,
          password: 'new-pass-2',
        ),
        '旧载荷机密',
      );
      expect(
        () => svc.decryptBlockDocPassword(
          docId: id,
          encryptedJson: upgraded,
          password: pw,
        ),
        throwsFormatException,
      );
    });
  });
}
