// H3 修复回归：v1（PBKDF2）→ v2（Argon2id）同步信封迁移。
//
// 背景：同步 KDF 从 PBKDF2-HMAC-SHA256 600k 切到 Argon2id 后，同口令同盐
// 产出**不同**密钥，PBKDF2 时代上传云端的老信封全部不可解（解密侧还强制
// 只认 v == 2）。修复前唯一的出路是「重新配置同步口令 + 全量重传」——
// 用户丢了云端历史。
//
// 本文件锁三件事：
//  ① 旧口令仍能派生 v1 密钥时，迁移能把老信封重封成 v2，且新信封可被
//     当前 [AesSyncCipher] 正常解回（真实双 KDF，不注入）；
//  ② 口令已改 / 数据损坏时，迁移**确定性失败**并归入
//     [SyncKeyMismatchException]（不退避重试，调用方据此提示重新配置）；
//  ③ 迁移的放宽口没有削弱生产 fail-closed：v1 信封仍被普通解密路径拒绝。
//
// 真 KDF 套件（PBKDF2 600k ≈ 3s + Argon2id 64MiB ≈ 0.35s），按本仓口径
// 打 `@Tags(['kdf'])` 进 CI 串行分片。同文件内 KekSessionCache 会缓存派生
// 结果，后续用例命中缓存，不重复付成本。

@Tags(['kdf'])
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:drawing_notes_app/core/sync/sync_cipher.dart';
import 'package:flutter_test/flutter_test.dart';

final List<int> _salt = List<int>.generate(16, (i) => 100 + i);

// AAD 在测试里**逐字硬写**，不复用生产常量：迁移正确的判据之一就是
// 「用的 AAD 与当年加密时逐字相同」，复用它就等于用生产代码自证。
const String _docAad = 'drawing-notes|sync|doc|doc-1|v1';
const String _manifestAad = 'drawing-notes|sync|manifest|v1';

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  group('v1 → v2 文档信封迁移', () {
    test('旧口令仍能派生 v1 密钥 → 重封成 v2，当前加密器可解回', () async {
      const password = 'P1';
      const docId = 'doc-1';
      final plain = _bytes('{"id":"doc-1","title":"云端老笔记"}');

      // 用真实 PBKDF2 v1 密钥构造一个**真实形状**的 v1 信封。
      final v1Key = await deriveMasterKeyV1(password, _salt);
      final v1Cipher = await AesSyncCipher.encryptEnvelopeWithKey(
        plain: plain,
        aad: _bytes(_docAad),
        mode: 'sync-doc',
        key: v1Key,
        version: syncEnvelopeV1,
      );
      // 前提自检：这确实是个 v1 信封（下面所有断言都依赖它）。
      expect((jsonDecode(utf8.decode(v1Cipher)) as Map)['v'], 1);

      final v2Cipher = await migrateSyncDocumentEnvelopeV1ToV2(
        v1Cipher: v1Cipher,
        docId: docId,
        password: password,
        salt: _salt,
      );

      // 产物是 v2 线格式。
      final wire = jsonDecode(utf8.decode(v2Cipher)) as Map<String, dynamic>;
      expect(wire['v'], 2, reason: '迁移必须重封成当前线格式版本');
      expect(wire['mode'], 'sync-doc');

      // 用当前 Argon2id 主密钥的加密器解得回原文。
      final v2Key = await deriveMasterKey(password, _salt);
      final restored = await AesSyncCipher(
        key: v2Key,
      ).decryptDocumentBytes(v2Cipher, docId);
      expect(utf8.decode(restored), utf8.decode(plain));
    });

    test('v1 manifest 信封同样可迁移（AAD 绑定 manifest 上下文）', () async {
      const password = 'P1';
      final plain = _bytes('{"entries":{},"deletedIds":[]}');

      final v1Key = await deriveMasterKeyV1(password, _salt);
      final v1Cipher = await AesSyncCipher.encryptEnvelopeWithKey(
        plain: plain,
        aad: _bytes(_manifestAad),
        mode: 'sync-manifest',
        key: v1Key,
        version: syncEnvelopeV1,
      );

      final v2Cipher = await migrateSyncManifestEnvelopeV1ToV2(
        v1Cipher: v1Cipher,
        password: password,
        salt: _salt,
      );

      final wire = jsonDecode(utf8.decode(v2Cipher)) as Map<String, dynamic>;
      expect(wire['v'], 2);
      expect(wire['mode'], 'sync-manifest');

      final v2Key = await deriveMasterKey(password, _salt);
      final restored = await AesSyncCipher(
        key: v2Key,
      ).openManifestJson(utf8.decode(v2Cipher));
      expect(restored, utf8.decode(plain));
    });
  });

  group('v1 → v2 迁移失败路径', () {
    test('口令已改（旧口令派生不出能解开的 v1 密钥）→ 确定性失败', () async {
      final plain = _bytes('{"id":"doc-1"}');

      final v1Key = await deriveMasterKeyV1('P1', _salt);
      final v1Cipher = await AesSyncCipher.encryptEnvelopeWithKey(
        plain: plain,
        aad: _bytes(_docAad),
        mode: 'sync-doc',
        key: v1Key,
        version: syncEnvelopeV1,
      );

      await expectLater(
        migrateSyncDocumentEnvelopeV1ToV2(
          v1Cipher: v1Cipher,
          docId: 'doc-1',
          password: 'P2', // 不是上传时的那个口令
          salt: _salt,
        ),
        throwsA(isA<SyncKeyMismatchException>()),
      );
    });

    test('迁移只认 v1：拿已经是 v2 的信封来迁移 → 拒绝（版本收窄不可绕过）',
        () async {
      // 用当前 Argon2id 密钥造一个真实 v2 信封。
      final v2Key = await deriveMasterKey('P1', _salt);
      final v2Cipher = await AesSyncCipher(
        key: v2Key,
      ).encryptDocumentBytes(_bytes('{"id":"doc-1"}'), 'doc-1');
      expect((jsonDecode(utf8.decode(v2Cipher)) as Map)['v'], 2);

      // 迁移函数的放宽口只开在 v1 上：v2 信封必须被拒，而不是被「解密后
      // 原样重封」——后者会让迁移路径变成绕过版本门禁的后门。
      await expectLater(
        migrateSyncDocumentEnvelopeV1ToV2(
          v1Cipher: v2Cipher,
          docId: 'doc-1',
          password: 'P1',
          salt: _salt,
        ),
        throwsA(isA<SyncKeyMismatchException>()),
      );
    });
  });

  group('迁移不得削弱生产 fail-closed 口径', () {
    test('v1 信封仍被普通解密路径拒绝（放宽口只开在迁移函数里）', () async {
      final plain = _bytes('{"id":"doc-1"}');
      final v1Key = await deriveMasterKeyV1('P1', _salt);
      final v1Cipher = await AesSyncCipher.encryptEnvelopeWithKey(
        plain: plain,
        aad: _bytes(_docAad),
        mode: 'sync-doc',
        key: v1Key,
        version: syncEnvelopeV1,
      );

      // 用**当前**密钥的普通解密路径：即便用户口令没变（Argon2id 密钥
      // 恰好能派生），v1 线格式也必须被拒。
      final v2Key = await deriveMasterKey('P1', _salt);
      await expectLater(
        AesSyncCipher(key: v2Key).decryptDocumentBytes(v1Cipher, 'doc-1'),
        throwsA(isA<SyncKeyMismatchException>()),
      );
    });
  });
}
