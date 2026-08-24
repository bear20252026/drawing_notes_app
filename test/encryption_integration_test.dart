// 加密服务集成测试（2026-08-25）。
//
// 覆盖四大集成链路：
// 1. 密钥派生链：Argon2id → HKDF-SHA256 → K1(enc)/K2(auth)/K3(kek)
// 2. 三层加密/解密：L1 ChaCha20-Poly1305 + L2 AES-256-GCM+随机填充
//    + L3 AES-256-GCM+Ed25519 签名（K1/K2/K3 全链路打通）
// 3. 可否认加密双密钥槽：主密钥槽 A + 胁迫密钥槽 B，AAD 槽绑定
// 4. 密码盘（PasswordDisk）读写：v1 明文盘 + v2 PIN 盘 + Mock/Real 实现
//
// 集成点：
// - EncryptionService.deriveKeyChain 派生的 K1/K2/K3 直接喂给
//   ThreeLayerEncryptionService——验证真实密钥派生与三层封装的兼容性
// - 可否认加密密钥派生（HKDF 独立 salt）与 AES-GCM 槽绑定
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:drawing_notes_app/core/storage/encryption_service.dart';
import 'package:drawing_notes_app/core/storage/password_disk.dart';
import 'package:editor_core/src/domain/deniable_encryption.dart';
import 'package:editor_core/src/domain/envelope_encryption.dart';
import 'package:editor_core/src/domain/three_layer_encryption.dart';
import 'package:flutter_test/flutter_test.dart';

/// 生成 32 字节安全随机密钥。
Uint8List secureKey32() {
  final rng = Random.secure();
  return Uint8List.fromList(List.generate(32, (_) => rng.nextInt(256)));
}

void main() {
  // 测试参数 Argon2id（1MiB）加速；生产用 64MiB。
  const encryption = EncryptionService.test();

  group('集成 1：密钥派生链（Argon2id → HKDF → K1/K2/K3）', () {
    test('deriveKeyChain 返回三个独立 32 字节子密钥', () async {
      final salt = List<int>.generate(16, (i) => i);
      final (k1, k2, k3) = await encryption.deriveKeyChain(
        password: 'integration-test-password',
        salt: salt,
      );

      final k1Bytes = await k1.extractBytes();
      final k2Bytes = await k2.extractBytes();
      final k3Bytes = await k3.extractBytes();

      // 长度校验：AES-256 / ChaCha20 均需 32 字节密钥。
      expect(k1Bytes.length, 32, reason: 'K1 必须是 32 字节');
      expect(k2Bytes.length, 32, reason: 'K2 必须是 32 字节');
      expect(k3Bytes.length, 32, reason: 'K3 必须是 32 字节');

      // 独立性校验：三个子密钥互不相同（HKDF info 分离生效）。
      expect(k1Bytes, isNot(equals(k2Bytes)), reason: 'K1 ≠ K2');
      expect(k1Bytes, isNot(equals(k3Bytes)), reason: 'K1 ≠ K3');
      expect(k2Bytes, isNot(equals(k3Bytes)), reason: 'K2 ≠ K3');
    });

    test('相同密码+相同盐 → 密钥派生确定性', () async {
      final salt = List<int>.generate(16, (_) => 0x42);

      final (a1, a2, a3) = await encryption.deriveKeyChain(
        password: 'deterministic',
        salt: salt,
      );
      final (b1, b2, b3) = await encryption.deriveKeyChain(
        password: 'deterministic',
        salt: salt,
      );

      expect(await a1.extractBytes(), await b1.extractBytes());
      expect(await a2.extractBytes(), await b2.extractBytes());
      expect(await a3.extractBytes(), await b3.extractBytes());
    });

    test('不同盐 → 不同密钥（盐敏感）', () async {
      final saltA = List<int>.filled(16, 0x01);
      final saltB = List<int>.filled(16, 0x02);

      final (ka1, _, _) = await encryption.deriveKeyChain(
        password: 'same-password',
        salt: saltA,
      );
      final (kb1, _, _) = await encryption.deriveKeyChain(
        password: 'same-password',
        salt: saltB,
      );

      expect(await ka1.extractBytes(), isNot(await kb1.extractBytes()));
    });

    test('不同密码 → 不同密钥（密码敏感）', () async {
      final salt = List<int>.filled(16, 0x03);

      final (ka1, _, _) = await encryption.deriveKeyChain(
        password: 'password-alpha',
        salt: salt,
      );
      final (kb1, _, _) = await encryption.deriveKeyChain(
        password: 'password-bravo',
        salt: salt,
      );

      expect(await ka1.extractBytes(), isNot(await kb1.extractBytes()));
    });
  });

  group('集成 2：三层加密/解密全链路（派生密钥 × 三层封装 × Ed25519 签名）', () {
    late ThreeLayerEncryptionService threeLayer;
    late SignatureService signatureService;
    late EnvelopeEncryptionService envelopeService;

    setUp(() {
      signatureService = const SignatureService();
      envelopeService = const EnvelopeEncryptionService();
      threeLayer = ThreeLayerEncryptionService(
        signatureService: signatureService,
        envelopeService: envelopeService,
      );
    });

    test('端到端解密：派生密钥直接驱动三层加解密闭环', () async {
      final salt = Uint8List.fromList(List.generate(16, (i) => i * 2));
      const password = 'decrypt-path-test';

      final (k1s, k2s, k3s) = await encryption.deriveKeyChain(
        password: password,
        salt: salt,
      );
      final signingKeyPair = await signatureService.generateKeyPair();
      final kek = secureKey32();

      const plaintext = '解密路径集成验证——Argon2id→HKDF→三层解封';
      final encrypted = await threeLayer.encrypt(
        plaintext: utf8.encode(plaintext),
        k1: await k1s.extractBytes(),
        k2: await k2s.extractBytes(),
        k3: await k3s.extractBytes(),
        signingKeyPair: signingKeyPair,
        kek: kek,
      );

      // 结构断言：三层密文非空、签名 64 字节（Ed25519）、填充在合法范围。
      expect(encrypted.l1Ciphertext, isNotEmpty, reason: 'L1 ChaCha20 密文非空');
      expect(encrypted.l2Ciphertext, isNotEmpty, reason: 'L2 AES-GCM 密文非空');
      expect(encrypted.l3Ciphertext, isNotEmpty, reason: 'L3 外层密文非空');
      expect(encrypted.signature.signature.length, 64,
          reason: 'Ed25519 签名固定 64 字节');
      expect(encrypted.l2PaddingLength, inInclusiveRange(16, 256),
          reason: '随机填充必须落在 16~256 字节（隐藏真实大小）');

      // 用同一组派生密钥解密（kek 解包信封还原 k3）。
      final decrypted = await threeLayer.decrypt(
        result: encrypted,
        k1: await k1s.extractBytes(),
        k2: await k2s.extractBytes(),
        kek: kek,
        signingPublicKey: signingKeyPair.publicKey,
      );

      expect(utf8.decode(decrypted), plaintext);
    });

    test('大数据端到端：100KB 笔记载荷全链路', () async {
      final (k1s, k2s, k3s) = await encryption.deriveKeyChain(
        password: 'large-payload-test',
        salt: Uint8List.fromList(List.filled(16, 5)),
      );
      final signingKeyPair = await signatureService.generateKeyPair();
      final kek = secureKey32();

      // 模拟 100KB 笔记数据。
      final plaintext = Uint8List(100 * 1024);
      for (var i = 0; i < plaintext.length; i++) {
        plaintext[i] = i % 251;
      }

      final encrypted = await threeLayer.encrypt(
        plaintext: plaintext,
        k1: await k1s.extractBytes(),
        k2: await k2s.extractBytes(),
        k3: await k3s.extractBytes(),
        signingKeyPair: signingKeyPair,
        kek: kek,
      );

      final decrypted = await threeLayer.decrypt(
        result: encrypted,
        k1: await k1s.extractBytes(),
        k2: await k2s.extractBytes(),
        kek: kek,
        signingPublicKey: signingKeyPair.publicKey,
      );

      expect(decrypted, equals(plaintext));
    });

    test('错误密码派生的密钥无法通过 L1/L2 认证（解密失败）', () async {
      final salt = Uint8List.fromList(List.filled(16, 7));

      final (goodK1, goodK2, goodK3) = await encryption.deriveKeyChain(
        password: 'correct-horse-battery',
        salt: salt,
      );
      final (badK1, badK2, _) = await encryption.deriveKeyChain(
        password: 'wrong-password-xxx',
        salt: salt,
      );
      final signingKeyPair = await signatureService.generateKeyPair();
      final kek = secureKey32();

      final encrypted = await threeLayer.encrypt(
        plaintext: utf8.encode('认证失败测试'),
        k1: await goodK1.extractBytes(),
        k2: await goodK2.extractBytes(),
        k3: await goodK3.extractBytes(),
        signingKeyPair: signingKeyPair,
        kek: kek,
      );

      // 错误密码派生的 K1 → ChaCha20-Poly1305 认证失败。
      await expectLater(
        threeLayer.decrypt(
          result: encrypted,
          k1: await badK1.extractBytes(),
          k2: await goodK2.extractBytes(),
          kek: kek,
          signingPublicKey: signingKeyPair.publicKey,
        ),
        throwsA(anything),
        reason: 'L1 密钥错误必须导致 Poly1305 认证失败',
      );

      // 错误密码派生的 K2 → AES-GCM 认证失败（L1 正确但 L2 错误）。
      await expectLater(
        threeLayer.decrypt(
          result: encrypted,
          k1: await goodK1.extractBytes(),
          k2: await badK2.extractBytes(),
          kek: kek,
          signingPublicKey: signingKeyPair.publicKey,
        ),
        throwsA(anything),
        reason: 'L2 密钥错误必须导致 GCM 认证失败',
      );
    });

    test('篡改 L3 密文 → Ed25519 验签失败 + 告警回调触发', () async {
      final (k1s, k2s, k3s) = await encryption.deriveKeyChain(
        password: 'tamper-detection',
        salt: Uint8List.fromList(List.filled(16, 9)),
      );
      final signingKeyPair = await signatureService.generateKeyPair();
      final kek = secureKey32();

      final encrypted = await threeLayer.encrypt(
        plaintext: utf8.encode('防篡改集成测试'),
        k1: await k1s.extractBytes(),
        k2: await k2s.extractBytes(),
        k3: await k3s.extractBytes(),
        signingKeyPair: signingKeyPair,
        kek: kek,
      );

      // 翻转 L3 密文首字节模拟中间人篡改。
      final tampered = ThreeLayerResult(
        l1Ciphertext: encrypted.l1Ciphertext,
        l1Nonce: encrypted.l1Nonce,
        l2Ciphertext: encrypted.l2Ciphertext,
        l2Nonce: encrypted.l2Nonce,
        l2PaddingLength: encrypted.l2PaddingLength,
        l3Ciphertext: Uint8List.fromList(encrypted.l3Ciphertext)..[0] ^= 0xFF,
        l3Nonce: encrypted.l3Nonce,
        signature: encrypted.signature,
        envelope: encrypted.envelope,
        version: encrypted.version,
        processedAt: encrypted.processedAt,
        metadata: encrypted.metadata,
      );

      var alerted = false;
      await expectLater(
        threeLayer.decrypt(
          result: tampered,
          k1: await k1s.extractBytes(),
          k2: await k2s.extractBytes(),
          kek: kek,
          signingPublicKey: signingKeyPair.publicKey,
          onAlert: (context, meta) => alerted = true,
        ),
        throwsA(isA<SignatureVerificationException>()),
      );
      expect(alerted, isTrue, reason: '验签失败必须触发告警回调');
    });
  });

  group('集成 3：可否认加密双密钥槽', () {
    late DeniableEncryptionService deniable;

    setUp(() {
      deniable = DeniableEncryptionService();
    });

    DeniableContainer makeContainer() => deniable.initializeContainer(
          containerId: 'integration-container',
          primaryPassword: 'primary-secret-8chars',
          coercionPassword: 'coercion-decoy-99',
          recoveryKey: 'recovery-key-integration-0001',
        );

    test('容器初始化：双槽均初始化且分区归属正确', () {
      final container = makeContainer();

      expect(container.id, 'integration-container');
      expect(container.slotStates.length, 2);
      expect(container.slotStates[0].slotIndex, slotA);
      expect(container.slotStates[1].slotIndex, slotB);
      expect(container.slotStates[0].initialized, isTrue);
      expect(container.slotStates[1].initialized, isTrue);

      // 分区归属：每个分区的 slotIndex 只能是 A 或 B。
      final partA = container.getPartitionsForSlot(slotA);
      final partB = container.getPartitionsForSlot(slotB);
      expect(partA, isNotEmpty, reason: '槽 A 必须有分区');
      expect(partB, isNotEmpty, reason: '槽 B 必须有分区');
      for (final p in container.partitions) {
        expect(p.slotIndex, anyOf(slotA, slotB));
      }
    });

    test('initializeContainer 拒绝弱密码与相同密码', () {
      expect(
        () => deniable.initializeContainer(
          containerId: 'weak-primary',
          primaryPassword: 'short7', // < 8 字符
          coercionPassword: 'coercion-decoy-99',
          recoveryKey: 'rk',
        ),
        throwsArgumentError,
      );
      expect(
        () => deniable.initializeContainer(
          containerId: 'weak-coercion',
          primaryPassword: 'primary-secret-8chars',
          coercionPassword: 'short7',
          recoveryKey: 'rk',
        ),
        throwsArgumentError,
      );
      expect(
        () => deniable.initializeContainer(
          containerId: 'same-password',
          primaryPassword: 'identical-pw-123',
          coercionPassword: 'identical-pw-123',
          recoveryKey: 'rk',
        ),
        throwsArgumentError,
        reason: '主密码与胁迫密码必须不同',
      );
    });

    test('deriveDualKeys：主密钥与胁迫密钥相互独立', () {
      final (primaryKey, coercionKey) = deniable.deriveDualKeys(
        primaryPassword: 'primary-secret-8chars',
        coercionPassword: 'coercion-decoy-99',
      );

      expect(primaryKey.length, 32);
      expect(coercionKey.length, 32);
      expect(primaryKey, isNot(equals(coercionKey)),
          reason: '独立 salt 派生 → 两密钥必须不同');

      // 再次调用长度一致（salt 随机 → 不要求值相等）。
      final (again1, again2) = deniable.deriveDualKeys(
        primaryPassword: 'primary-secret-8chars',
        coercionPassword: 'coercion-decoy-99',
      );
      expect(again1.length, 32);
      expect(again2.length, 32);
    });

    test('槽 A 写读回环：encryptToSlot → decryptFromSlot', () {
      final (primaryKey, _) = deniable.deriveDualKeys(
        primaryPassword: 'primary-secret-8chars',
        coercionPassword: 'coercion-decoy-99',
      );

      const secret = '槽 A 机密数据——真实工作文件';
      final encrypted = deniable.encryptToSlot(
        slotIndex: slotA,
        plaintext: utf8.encode(secret),
        key: primaryKey,
      );

      final decrypted = deniable.decryptFromSlot(
        slotIndex: slotA,
        encryptedData: encrypted,
        key: primaryKey,
      );

      expect(utf8.decode(decrypted), secret);
    });

    test('槽 B 写读回环：胁迫密钥独立加解密', () {
      final (_, coercionKey) = deniable.deriveDualKeys(
        primaryPassword: 'primary-secret-8chars',
        coercionPassword: 'coercion-decoy-99',
      );

      const decoy = '槽 B 伪装数据——无害内容';
      final encrypted = deniable.encryptToSlot(
        slotIndex: slotB,
        plaintext: utf8.encode(decoy),
        key: coercionKey,
      );

      final decrypted = deniable.decryptFromSlot(
        slotIndex: slotB,
        encryptedData: encrypted,
        key: coercionKey,
      );

      expect(utf8.decode(decrypted), decoy);
    });

    test('AAD 槽绑定：A 槽数据不能以 B 槽身份解密（防跨槽重放）', () {
      final (primaryKey, coercionKey) = deniable.deriveDualKeys(
        primaryPassword: 'primary-secret-8chars',
        coercionPassword: 'coercion-decoy-99',
      );

      final encryptedA = deniable.encryptToSlot(
        slotIndex: slotA,
        plaintext: utf8.encode('slot-bound data'),
        key: primaryKey,
      );

      // 即使攻击者拿到主密钥，把 A 槽密文当作 B 槽解密也必须失败
      // （AAD 含槽标识 → GCM 认证失败）。
      expect(
        () => deniable.decryptFromSlot(
          slotIndex: slotB,
          encryptedData: encryptedA,
          key: primaryKey,
        ),
        throwsA(anything),
        reason: '槽标识混入 AAD → 跨槽解密必须被 GCM 拒绝',
      );

      // 错误密钥在正确槽位同样必须失败。
      expect(
        () => deniable.decryptFromSlot(
          slotIndex: slotA,
          encryptedData: encryptedA,
          key: coercionKey,
        ),
        throwsA(anything),
        reason: '错误密钥必须导致 GCM 认证失败',
      );
    });

    test('tryUnlock 主密码解锁槽 A 并重置失败计数', () {
      final container = makeContainer();
      final (primaryKey, coercionKey) = deniable.deriveDualKeys(
        primaryPassword: 'primary-secret-8chars',
        coercionPassword: 'coercion-decoy-99',
      );

      final result = deniable.tryUnlock(
        container: container,
        password: 'primary-secret-8chars',
        primaryKeyMaterial: primaryKey,
        coercionKeyMaterial: coercionKey,
      );

      expect(result.success, isTrue, reason: '主密码必须能解锁容器');
      expect(result.slotIndex, slotA);
      expect(deniable.selfDestructState.consecutiveFailures, 0,
          reason: '成功解锁后失败计数归零');
      expect(deniable.selfDestructState.destroyed, isFalse);
    });

    test('verifyContainerIntegrity 校验合法容器', () {
      final container = makeContainer();
      expect(deniable.verifyContainerIntegrity(container), isTrue);
    });
  });

  group('集成 4：密码盘（PasswordDisk）读写', () {
    test('v1 明文盘：generateKey → encode → decode 回环', () {
      final key = PasswordDiskFile.generateKey();
      expect(key.length, 32, reason: 'U 盘密钥固定 32 字节');

      final encoded = PasswordDiskFile.encode(key);
      expect(encoded.length, PasswordDiskFile.fileLength,
          reason: 'v1 文件固定 37 字节');

      // FROG 魔数头 + v1 版本号。
      expect(encoded.sublist(0, 4), [0x46, 0x52, 0x4F, 0x47]);
      expect(encoded[4], 0x01);

      final decoded = PasswordDiskFile.decode(encoded);
      expect(decoded, key, reason: 'v1 编解码必须无损回环');
    });

    test('v1 decode 拒绝损坏文件（返回 null 而非抛异常）', () {
      final key = PasswordDiskFile.generateKey();
      final encoded = PasswordDiskFile.encode(key);

      // 错误魔数。
      final badMagic = List<int>.from(encoded)..[0] = 0x00;
      expect(PasswordDiskFile.decode(badMagic), isNull);

      // 截断（不足 37 字节）。
      expect(PasswordDiskFile.decode(encoded.sublist(0, 5)), isNull);

      // 错误版本号。
      final badVersion = List<int>.from(encoded)..[4] = 0x09;
      expect(PasswordDiskFile.decode(badVersion), isNull);
    });

    test('v2 PIN 盘：encodeWithPin → decodeWithPin 回环', () async {
      final key = PasswordDiskFile.generateKey();
      const pin = '135790'; // ≥ 6 位。

      final encoded =
          await PasswordDiskFile.encodeWithPin(key: key, pin: pin);
      expect(encoded[4], 0x02, reason: 'PIN 保护格式版本号为 v2');

      final decoded = await PasswordDiskFile.decodeWithPin(encoded, pin);
      expect(decoded, key, reason: '正确 PIN 必须恢复原始密钥');
    });

    test('v2 PIN 盘：错误 PIN 返回 null（静默拒绝）', () async {
      final key = PasswordDiskFile.generateKey();
      final encoded = await PasswordDiskFile.encodeWithPin(
        key: key,
        pin: '246810',
      );

      final decoded = await PasswordDiskFile.decodeWithPin(encoded, '999999');
      expect(decoded, isNull, reason: '错误 PIN 必须返回 null 而非抛异常');
    });

    test('v2 encodeWithPin 拒绝短 PIN（<6 位）', () async {
      final key = PasswordDiskFile.generateKey();
      expect(
        () => PasswordDiskFile.encodeWithPin(key: key, pin: '12345'),
        throwsArgumentError,
        reason: '短 PIN 可被数小时离线暴力破解——核心层强制 ≥6 位',
      );
    });

    test('MockPasswordDisk：创建→读取→校验全流程', () async {
      final dir = Directory.systemTemp.createTempSync('pwdisk_integration_');
      addTearDown(() => dir.deleteSync(recursive: true));

      final disk = MockPasswordDisk(baseDir: dir.path);

      expect(await disk.pickDirectory(), dir.path);
      expect(await disk.readKey(dir.path), isNull, reason: '未创建前读取返回 null');
      expect(await disk.validateKeyFile(dir.path), isFalse);

      expect(await disk.createKeyFile(dir.path), isTrue);
      expect(await disk.validateKeyFile(dir.path), isTrue);

      final key = await disk.readKey(dir.path);
      expect(key, isNotNull);
      expect(key!.length, 32);

      // 二次读取一致（持久化语义）。
      final keyAgain = await disk.readKey(dir.path);
      expect(keyAgain, key);
    });

    test('MockPasswordDisk：PIN 创建→正确/错误 PIN 读取', () async {
      final dir =
          Directory.systemTemp.createTempSync('pwdisk_pin_integration_');
      addTearDown(() => dir.deleteSync(recursive: true));

      final disk = MockPasswordDisk(baseDir: dir.path);
      const pin = '112233';

      expect(await disk.createKeyFileWithPin(dir.path, pin: pin), isTrue);
      expect(await disk.validateKeyFile(dir.path), isTrue,
          reason: 'v2 PIN 盘 validate 也必须有效');

      final key = await disk.readKeyWithPin(dir.path, pin: pin);
      expect(key, isNotNull);
      expect(key!.length, 32);

      final wrongPin = await disk.readKeyWithPin(dir.path, pin: '000000');
      expect(wrongPin, isNull);
    });

    test('RealPasswordDisk：临时目录读写回环（绕过系统选择器）', () async {
      final dir =
          Directory.systemTemp.createTempSync('pwdisk_real_integration_');
      addTearDown(() => dir.deleteSync(recursive: true));

      const disk = RealPasswordDisk();

      expect(await disk.createKeyFile(dir.path), isTrue);
      expect(await disk.validateKeyFile(dir.path), isTrue);

      final key = await disk.readKey(dir.path);
      expect(key, isNotNull);
      expect(key!.length, 32);

      // PIN 流程。
      const pin = '445566';
      final pinDir = Directory.systemTemp.createTempSync('pwdisk_real_pin_');
      addTearDown(() => pinDir.deleteSync(recursive: true));
      expect(await disk.createKeyFileWithPin(pinDir.path, pin: pin), isTrue);
      final pinnedKey = await disk.readKeyWithPin(pinDir.path, pin: pin);
      expect(pinnedKey, isNotNull);
      expect(pinnedKey!.length, 32);
    });
  });

  group('跨组件集成：密钥派生 × 可否认加密 × 密码盘联动', () {
    test('统一密码源驱动三条加密通道（NIST SP 800-108 密钥分离冒烟）', () async {
      const masterPassword = 'one-source-three-channels';

      // 通道 1：EncryptionService 密钥链。
      final (k1, k2, k3) = await encryption.deriveKeyChain(
        password: masterPassword,
        salt: Uint8List.fromList(List.filled(16, 0x11)),
      );
      final chainKeys = [
        await k1.extractBytes(),
        await k2.extractBytes(),
        await k3.extractBytes(),
      ];
      for (final k in chainKeys) {
        expect(k.length, 32);
      }

      // 通道 2：可否认加密双槽密钥。
      final deniable = DeniableEncryptionService();
      final (primaryKey, coercionKey) = deniable.deriveDualKeys(
        primaryPassword: masterPassword,
        coercionPassword: '$masterPassword-coercion',
      );
      expect(primaryKey.length, 32);
      expect(coercionKey.length, 32);

      // 通道 3：密码盘密钥。
      final diskKey = PasswordDiskFile.generateKey();
      expect(diskKey.length, 32);

      // 五把密钥两两互不相同（用途分离——防密钥重用）。
      final allKeys = [
        ...chainKeys,
        primaryKey.toList(),
        diskKey.toList(),
      ];
      for (var i = 0; i < allKeys.length; i++) {
        for (var j = i + 1; j < allKeys.length; j++) {
          expect(
            allKeys[i],
            isNot(equals(allKeys[j])),
            reason: '通道 $i 与通道 $j 密钥必须独立',
          );
        }
      }
    });
  });
}
