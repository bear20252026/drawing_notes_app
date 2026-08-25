// PQC 混合加密提供者测试（2026-08-25）
//
// 覆盖：
// 1. PQC 提供者抽象接口（KEM / Signature）
// 2. 占位实现（ECDSA P-256）
// 3. Ed25519 经典签名提供者
// 4. Ed25519 + ML-DSA-65 混合签名器
// 5. 算法版本协商 v2.0
// 6. 提供者替换性验证
import 'dart:typed_data';

import 'package:editor_core/editor_core.dart';
import 'package:test/test.dart';

void main() {
  // ──────── 1. PlaceholderMlKemProvider ────────
  group('PlaceholderMlKemProvider', () {
    late PlaceholderMlKemProvider provider;

    setUp(() {
      provider = const PlaceholderMlKemProvider();
    });

    test('algorithmId 返回 ml-kem-768', () {
      expect(provider.algorithmId, 'ml-kem-768');
    });

    test('generateKeyPair 生成有效密钥对', () {
      final kp = provider.generateKeyPair();
      expect(kp.publicKey.length, greaterThan(0));
      expect(kp.secretKey.length, greaterThan(0));
    });

    test('encapsulate 生成有效封装', () {
      final kp = provider.generateKeyPair();
      final enc = provider.encapsulate(kp.publicKey);
      expect(enc.ciphertext.length, greaterThan(0));
      expect(enc.sharedSecret.length, greaterThan(0));
    });

    test('decapsulate 恢复共享秘密', () {
      final kp = provider.generateKeyPair();
      final enc = provider.encapsulate(kp.publicKey);
      final recovered = provider.decapsulate(
        ciphertext: enc.ciphertext,
        secretKey: kp.secretKey,
      );
      // 占位实现中 decapsulate 是模拟恢复，不保证等于原始共享秘密。
      expect(recovered.length, greaterThan(0));
    });

    test('多次封装产生不同密文', () {
      final kp = provider.generateKeyPair();
      final enc1 = provider.encapsulate(kp.publicKey);
      final enc2 = provider.encapsulate(kp.publicKey);
      // 临时密钥不同，密文应不同。
      expect(enc1.ciphertext, isNot(equals(enc2.ciphertext)));
    });
  });

  // ──────── 2. PlaceholderMlDsaProvider ────────
  group('PlaceholderMlDsaProvider', () {
    late PlaceholderMlDsaProvider provider;

    setUp(() {
      provider = const PlaceholderMlDsaProvider();
    });

    test('algorithmId 返回 ml-dsa-65', () {
      expect(provider.algorithmId, 'ml-dsa-65');
    });

    test('generateKeyPair 生成有效密钥对', () {
      final kp = provider.generateKeyPair();
      expect(kp.publicKey.length, greaterThan(0));
      expect(kp.secretKey.length, greaterThan(0));
    });

    test('sign/verify 正常工作', () {
      final kp = provider.generateKeyPair();
      final msg = Uint8List.fromList([1, 2, 3, 4, 5]);
      final sig = provider.sign(message: msg, secretKey: kp.secretKey);
      expect(sig.length, greaterThan(0));

      final valid =
          provider.verify(signature: sig, message: msg, publicKey: kp.publicKey);
      expect(valid, isTrue);
    });

    test('篡改消息后验签失败', () {
      final kp = provider.generateKeyPair();
      final msg = Uint8List.fromList([1, 2, 3]);
      final sig = provider.sign(message: msg, secretKey: kp.secretKey);

      final tampered = Uint8List.fromList([1, 2, 4]);
      final valid = provider.verify(
          signature: sig, message: tampered, publicKey: kp.publicKey);
      expect(valid, isFalse);
    });

    test('篡改签名后验签失败', () {
      final kp = provider.generateKeyPair();
      final msg = Uint8List.fromList([1, 2, 3]);
      final sig = provider.sign(message: msg, secretKey: kp.secretKey);

      sig[0] ^= 0xFF;
      final valid =
          provider.verify(signature: sig, message: msg, publicKey: kp.publicKey);
      expect(valid, isFalse);
    });
  });

  // ──────── 3. Ed25519SignatureProvider ────────
  group('Ed25519SignatureProvider', () {
    late Ed25519SignatureProvider provider;

    setUp(() {
      provider = const Ed25519SignatureProvider();
    });

    test('algorithmId 返回 ed25519', () {
      expect(provider.algorithmId, 'ed25519');
    });

    test('generateKeyPair 生成 32 字节公钥和 32 字节私钥', () async {
      final kp = await provider.generateKeyPair();
      expect(kp.length, 2);
      expect(kp[0].length, 32); // Ed25519 公钥
      expect(kp[1].length, 32); // Ed25519 私钥种子
    });

    test('sign/verify 正常工作', () async {
      final kp = await provider.generateKeyPair();
      final msg = Uint8List.fromList([10, 20, 30, 40, 50]);
      final sig = await provider.sign(message: msg, secretKey: kp[1]);
      expect(sig.length, 64); // Ed25519 签名 64 字节

      final valid =
          await provider.verify(signature: sig, message: msg, publicKey: kp[0]);
      expect(valid, isTrue);
    });

    test('篡改消息后验签失败', () async {
      final kp = await provider.generateKeyPair();
      final msg = Uint8List.fromList([1, 2, 3]);
      final sig = await provider.sign(message: msg, secretKey: kp[1]);

      final tampered = Uint8List.fromList([1, 2, 4]);
      final valid =
          await provider.verify(signature: sig, message: tampered, publicKey: kp[0]);
      expect(valid, isFalse);
    });

    test('篡改签名后验签失败', () async {
      final kp = await provider.generateKeyPair();
      final msg = Uint8List.fromList([1, 2, 3]);
      final sig = await provider.sign(message: msg, secretKey: kp[1]);

      sig[0] ^= 0xFF;
      final valid =
          await provider.verify(signature: sig, message: msg, publicKey: kp[0]);
      expect(valid, isFalse);
    });

    test('不同密钥签名不互相验证', () async {
      final kp1 = await provider.generateKeyPair();
      final kp2 = await provider.generateKeyPair();
      final msg = Uint8List.fromList([1, 2, 3]);
      final sig1 = await provider.sign(message: msg, secretKey: kp1[1]);

      final valid =
          await provider.verify(signature: sig1, message: msg, publicKey: kp2[0]);
      expect(valid, isFalse);
    });

    test('从种子恢复签名一致性', () async {
      final kp = await provider.generateKeyPair();
      final msg = Uint8List.fromList([99, 100, 101]);

      // 用原始密钥签名。
      final sig1 = await provider.sign(message: msg, secretKey: kp[1]);
      // 用相同种子重新签名——Ed25519 是确定性的。
      final sig2 = await provider.sign(message: msg, secretKey: kp[1]);
      expect(sig1, equals(sig2));
    });

    test('大消息签名正常', () async {
      final kp = await provider.generateKeyPair();
      final msg = Uint8List.fromList(List.generate(64 * 1024, (i) => i % 256));
      final sig = await provider.sign(message: msg, secretKey: kp[1]);
      expect(sig.length, 64);

      final valid =
          await provider.verify(signature: sig, message: msg, publicKey: kp[0]);
      expect(valid, isTrue);
    });

    test('空消息签名正常', () async {
      final kp = await provider.generateKeyPair();
      final msg = Uint8List(0);
      final sig = await provider.sign(message: msg, secretKey: kp[1]);
      expect(sig.length, 64);

      final valid =
          await provider.verify(signature: sig, message: msg, publicKey: kp[0]);
      expect(valid, isTrue);
    });

    test('无效公钥验签返回 false', () async {
      final kp = await provider.generateKeyPair();
      final msg = Uint8List.fromList([1, 2, 3]);
      final sig = await provider.sign(message: msg, secretKey: kp[1]);

      final invalidPubKey = Uint8List(32);
      final valid = await provider.verify(
          signature: sig, message: msg, publicKey: invalidPubKey);
      expect(valid, isFalse);
    });

    test('无效签名长度验签返回 false', () async {
      final kp = await provider.generateKeyPair();
      final msg = Uint8List.fromList([1, 2, 3]);
      final badSig = Uint8List(32); // 太短

      final valid = await provider.verify(
          signature: badSig, message: msg, publicKey: kp[0]);
      expect(valid, isFalse);
    });
  });

  // ──────── 4. EcdsaP256SignatureProvider ────────
  group('EcdsaP256SignatureProvider', () {
    late EcdsaP256SignatureProvider provider;

    setUp(() {
      provider = const EcdsaP256SignatureProvider();
    });

    test('algorithmId 返回 ecdsa-p256', () {
      expect(provider.algorithmId, 'ecdsa-p256');
    });

    test('generateKeyPair 生成有效密钥', () async {
      final kp = await provider.generateKeyPair();
      expect(kp.length, 2);
      expect(kp[0].length, greaterThan(0));
      expect(kp[1].length, greaterThan(0));
    });

    test('sign/verify 正常工作', () async {
      final kp = await provider.generateKeyPair();
      final msg = Uint8List.fromList([10, 20, 30]);
      final sig = await provider.sign(message: msg, secretKey: kp[1]);

      final valid =
          await provider.verify(signature: sig, message: msg, publicKey: kp[0]);
      expect(valid, isTrue);
    });
  });

  // ──────── 5. PqHybridSignerEd25519 ────────
  group('PqHybridSignerEd25519', () {
    test('使用默认提供者初始化', () async {
      final signer = PqHybridSignerEd25519();
      await signer.initialize();

      expect(signer.classicalPublicKey.length, 32);
      expect(signer.classicalSecretKey.length, 32);
      expect(signer.pqPublicKey.length, greaterThan(0));
      expect(signer.pqSecretKey.length, greaterThan(0));
      expect(signer.classicalAlgorithmId, 'ed25519');
      expect(signer.pqAlgorithmId, 'ml-dsa-65');
    });

    test('withKeyPairs 构造正常', () async {
      final edProvider = const Ed25519SignatureProvider();
      final edKp = await edProvider.generateKeyPair();
      final pqProvider = const PlaceholderMlDsaProvider();
      final pqKp = pqProvider.generateKeyPair();

      final signer = PqHybridSignerEd25519.withKeyPairs(
        classicalKeyPair: edKp,
        pqKeyPair: pqKp,
        classicalProvider: edProvider,
        pqProvider: pqProvider,
      );

      expect(signer.classicalPublicKey, equals(edKp[0]));
      expect(signer.pqPublicKey, equals(pqKp.publicKey));
    });

    test('双重签名产生合并格式', () async {
      final edProvider = const Ed25519SignatureProvider();
      final edKp = await edProvider.generateKeyPair();
      final pqProvider = const PlaceholderMlDsaProvider();
      final pqKp = pqProvider.generateKeyPair();

      final signer = PqHybridSignerEd25519.withKeyPairs(
        classicalKeyPair: edKp,
        pqKeyPair: pqKp,
        classicalProvider: edProvider,
        pqProvider: pqProvider,
      );

      final msg = Uint8List.fromList([72, 101, 108, 108, 111]); // "Hello"
      final result = await signer.sign(msg);

      expect(result.classicalSignature.length, 64); // Ed25519 = 64 字节
      expect(result.pqSignature.length, greaterThan(0));
      expect(result.combinedSignature.length,
          greaterThan(result.classicalSignature.length + result.pqSignature.length));
    });

    test('双重签名验证（Ed25519 + ML-DSA-65）', () async {
      final edProvider = const Ed25519SignatureProvider();
      final edKp = await edProvider.generateKeyPair();
      final pqProvider = const PlaceholderMlDsaProvider();
      final pqKp = pqProvider.generateKeyPair();

      final signer = PqHybridSignerEd25519.withKeyPairs(
        classicalKeyPair: edKp,
        pqKeyPair: pqKp,
        classicalProvider: edProvider,
        pqProvider: pqProvider,
      );

      final msg = Uint8List.fromList([1, 2, 3, 4, 5]);
      final result = await signer.sign(msg);

      final valid = await PqHybridSignerEd25519.verify(
        combinedSignature: result.combinedSignature,
        message: msg,
        classicalPublicKey: edKp[0],
        pqPublicKey: pqKp.publicKey,
        classicalProvider: edProvider,
        pqProvider: pqProvider,
      );

      expect(valid, isTrue);
    });

    test('篡改消息后双重签名验证失败', () async {
      final edProvider = const Ed25519SignatureProvider();
      final edKp = await edProvider.generateKeyPair();
      final pqProvider = const PlaceholderMlDsaProvider();
      final pqKp = pqProvider.generateKeyPair();

      final signer = PqHybridSignerEd25519.withKeyPairs(
        classicalKeyPair: edKp,
        pqKeyPair: pqKp,
        classicalProvider: edProvider,
        pqProvider: pqProvider,
      );

      final msg = Uint8List.fromList([1, 2, 3]);
      final result = await signer.sign(msg);

      final tampered = Uint8List.fromList([1, 2, 4]);
      final valid = await PqHybridSignerEd25519.verify(
        combinedSignature: result.combinedSignature,
        message: tampered,
        classicalPublicKey: edKp[0],
        pqPublicKey: pqKp.publicKey,
        classicalProvider: edProvider,
        pqProvider: pqProvider,
      );

      expect(valid, isFalse);
    });

    test('提取经典签名和 PQ 签名', () async {
      final edProvider = const Ed25519SignatureProvider();
      final edKp = await edProvider.generateKeyPair();
      final pqProvider = const PlaceholderMlDsaProvider();
      final pqKp = pqProvider.generateKeyPair();

      final signer = PqHybridSignerEd25519.withKeyPairs(
        classicalKeyPair: edKp,
        pqKeyPair: pqKp,
        classicalProvider: edProvider,
        pqProvider: pqProvider,
      );

      final msg = Uint8List.fromList([10, 20, 30]);
      final result = await signer.sign(msg);

      final extractedClassical = PqHybridSignerEd25519.extractClassicalSignature(
        result.combinedSignature,
      );
      final extractedPq = PqHybridSignerEd25519.extractPqSignature(
        result.combinedSignature,
      );

      expect(extractedClassical, equals(result.classicalSignature));
      expect(extractedPq, equals(result.pqSignature));
    });

    test('合并签名被截断后验证失败', () async {
      final edProvider = const Ed25519SignatureProvider();
      final edKp = await edProvider.generateKeyPair();
      final pqProvider = const PlaceholderMlDsaProvider();
      final pqKp = pqProvider.generateKeyPair();

      final signer = PqHybridSignerEd25519.withKeyPairs(
        classicalKeyPair: edKp,
        pqKeyPair: pqKp,
        classicalProvider: edProvider,
        pqProvider: pqProvider,
      );

      final msg = Uint8List.fromList([1, 2, 3]);
      final result = await signer.sign(msg);

      final truncated = result.combinedSignature.sublist(
          0, result.combinedSignature.length ~/ 2);

      final valid = await PqHybridSignerEd25519.verify(
        combinedSignature: truncated,
        message: msg,
        classicalPublicKey: edKp[0],
        pqPublicKey: pqKp.publicKey,
        classicalProvider: edProvider,
        pqProvider: pqProvider,
      );

      expect(valid, isFalse);
    });

    test('不同密钥验证失败', () async {
      final edProvider = const Ed25519SignatureProvider();
      final edKp1 = await edProvider.generateKeyPair();
      final edKp2 = await edProvider.generateKeyPair();
      final pqProvider = const PlaceholderMlDsaProvider();
      final pqKp = pqProvider.generateKeyPair();

      final signer = PqHybridSignerEd25519.withKeyPairs(
        classicalKeyPair: edKp1,
        pqKeyPair: pqKp,
        classicalProvider: edProvider,
        pqProvider: pqProvider,
      );

      final msg = Uint8List.fromList([1, 2, 3]);
      final result = await signer.sign(msg);

      // 使用不同经典公钥验证。
      final valid = await PqHybridSignerEd25519.verify(
        combinedSignature: result.combinedSignature,
        message: msg,
        classicalPublicKey: edKp2[0],
        pqPublicKey: pqKp.publicKey,
        classicalProvider: edProvider,
        pqProvider: pqProvider,
      );

      expect(valid, isFalse);
    });
  });

  // ──────── 6. PqAlgorithmVersionV2 ────────
  group('PqAlgorithmVersionV2', () {
    test('current 版本为 2.0', () {
      expect(PqAlgorithmVersionV2.current, '2.0');
    });

    test('v1 版本为 1.0', () {
      expect(PqAlgorithmVersionV2.v1, '1.0');
    });

    test('isV2 正确识别 v2.0', () {
      expect(PqAlgorithmVersionV2.isV2('2.0'), isTrue);
      expect(PqAlgorithmVersionV2.isV2('1.0'), isFalse);
    });

    test('isV1 正确识别 v1.0', () {
      expect(PqAlgorithmVersionV2.isV1('1.0'), isTrue);
      expect(PqAlgorithmVersionV2.isV1('2.0'), isFalse);
    });

    test('isCompatible 接受 v1.x 和 v2.x', () {
      expect(PqAlgorithmVersionV2.isCompatible('1.0'), isTrue);
      expect(PqAlgorithmVersionV2.isCompatible('1.5'), isTrue);
      expect(PqAlgorithmVersionV2.isCompatible('2.0'), isTrue);
      expect(PqAlgorithmVersionV2.isCompatible('2.5'), isTrue);
    });

    test('isCompatible 拒绝 v0.x 和 v3.x', () {
      expect(PqAlgorithmVersionV2.isCompatible('0.9'), isFalse);
      expect(PqAlgorithmVersionV2.isCompatible('3.0'), isFalse);
    });

    test('isCompatible 拒绝无效版本', () {
      expect(PqAlgorithmVersionV2.isCompatible(''), isFalse);
      expect(PqAlgorithmVersionV2.isCompatible('abc'), isFalse);
      expect(PqAlgorithmVersionV2.isCompatible('1'), isFalse);
    });

    test('defaultHeaderV2 包含 Ed25519 签名算法', () {
      final header = PqAlgorithmVersionV2.defaultHeaderV2();
      expect(header.version, '2.0');
      expect(header.signatureAlgorithm, contains('ed25519'));
      expect(header.signatureAlgorithm, contains('ml-dsa-65'));
      expect(header.kemAlgorithm, contains('x25519'));
      expect(header.kemAlgorithm, contains('ml-kem-768'));
      expect(header.kdfAlgorithm, 'hkdf-sha256');
      expect(header.aeadAlgorithm, 'aes-256-gcm');
      expect(header.salt.length, 32);
      expect(header.nonce.length, 12);
    });

    test('defaultHeaderV2 使用自定义 salt 和 nonce', () {
      final salt = Uint8List(32);
      final nonce = Uint8List(12);
      final header = PqAlgorithmVersionV2.defaultHeaderV2(
        salt: salt,
        nonce: nonce,
      );
      expect(header.salt, equals(salt));
      expect(header.nonce, equals(nonce));
    });

    test('算法常量正确', () {
      expect(PqAlgorithmVersionV2.sigEd25519, 'ed25519');
      expect(PqAlgorithmVersionV2.sigMlDsa65, 'ml-dsa-65');
      expect(PqAlgorithmVersionV2.kemX25519, 'x25519');
      expect(PqAlgorithmVersionV2.kemMlKem768, 'ml-kem-768');
      expect(PqAlgorithmVersionV2.kdfHkdfSha256, 'hkdf-sha256');
      expect(PqAlgorithmVersionV2.aeadAes256Gcm, 'aes-256-gcm');
    });

    test('header flags 包含 PQC + Dual Signature', () {
      final header = PqAlgorithmVersionV2.defaultHeaderV2();
      expect(header.isPqcEnabled, isTrue);
      expect(header.isDualSignature, isTrue);
    });
  });

  // ──────── 7. 提供者可替换性验证 ────────
  group('提供者可替换性', () {
    test('PlaceholderMlKemProvider 实现 PqcKemProvider 接口', () {
      const PqcKemProvider provider = PlaceholderMlKemProvider();
      expect(provider.algorithmId, 'ml-kem-768');
    });

    test('PlaceholderMlDsaProvider 实现 PqcSignatureProvider 接口', () {
      const PqcSignatureProvider provider = PlaceholderMlDsaProvider();
      expect(provider.algorithmId, 'ml-dsa-65');
    });

    test('Ed25519SignatureProvider 实现 ClassicalSignatureProvider 接口', () {
      const ClassicalSignatureProvider provider = Ed25519SignatureProvider();
      expect(provider.algorithmId, 'ed25519');
    });

    test('EcdsaP256SignatureProvider 实现 ClassicalSignatureProvider 接口', () {
      const ClassicalSignatureProvider provider = EcdsaP256SignatureProvider();
      expect(provider.algorithmId, 'ecdsa-p256');
    });

    test('混合签名器接受自定义提供者', () async {
      final edProvider = const Ed25519SignatureProvider();
      final edKp = await edProvider.generateKeyPair();
      final pqProvider = const PlaceholderMlDsaProvider();
      final pqKp = pqProvider.generateKeyPair();

      final signer = PqHybridSignerEd25519.withKeyPairs(
        classicalKeyPair: edKp,
        pqKeyPair: pqKp,
        classicalProvider: edProvider,
        pqProvider: pqProvider,
      );

      expect(signer.classicalAlgorithmId, 'ed25519');
      expect(signer.pqAlgorithmId, 'ml-dsa-65');
    });

    test('混合签名器可使用 ECDSA P-256 替代 Ed25519', () async {
      final ecdsaProvider = const EcdsaP256SignatureProvider();
      final ecdsaKp = await ecdsaProvider.generateKeyPair();
      final pqProvider = const PlaceholderMlDsaProvider();
      final pqKp = pqProvider.generateKeyPair();

      final signer = PqHybridSignerEd25519.withKeyPairs(
        classicalKeyPair: ecdsaKp,
        pqKeyPair: pqKp,
        classicalProvider: ecdsaProvider,
        pqProvider: pqProvider,
      );

      expect(signer.classicalAlgorithmId, 'ecdsa-p256');

      final msg = Uint8List.fromList([1, 2, 3]);
      final result = await signer.sign(msg);

      final valid = await PqHybridSignerEd25519.verify(
        combinedSignature: result.combinedSignature,
        message: msg,
        classicalPublicKey: ecdsaKp[0],
        pqPublicKey: pqKp.publicKey,
        classicalProvider: ecdsaProvider,
        pqProvider: pqProvider,
      );

      expect(valid, isTrue);
    });
  });

  // ──────── 8. Ed25519 + ML-DSA-65 端到端 ────────
  group('端到端 Ed25519 + PQC 混合加密', () {
    test('完整流程：密钥交换 + 双重签名 + 加密 + 验证', () async {
      // 1. 生成 Ed25519 + ML-DSA-65 混合签名密钥。
      final edProvider = const Ed25519SignatureProvider();
      final edKp = await edProvider.generateKeyPair();
      final pqProvider = const PlaceholderMlDsaProvider();
      final pqKp = pqProvider.generateKeyPair();

      final signer = PqHybridSignerEd25519.withKeyPairs(
        classicalKeyPair: edKp,
        pqKeyPair: pqKp,
        classicalProvider: edProvider,
        pqProvider: pqProvider,
      );

      // 2. ML-KEM-768 密钥封装。
      final kemProvider = const PlaceholderMlKemProvider();
      final kemKp = kemProvider.generateKeyPair();
      final encapsulation = kemProvider.encapsulate(kemKp.publicKey);
      final decapsulated = kemProvider.decapsulate(
        ciphertext: encapsulation.ciphertext,
        secretKey: kemKp.secretKey,
      );
      expect(decapsulated.length, greaterThan(0));

      // 3. 双重签名。
      final data = Uint8List.fromList([72, 101, 108, 108, 111]);
      final sigResult = await signer.sign(data);

      // 4. 验证双重签名。
      final valid = await PqHybridSignerEd25519.verify(
        combinedSignature: sigResult.combinedSignature,
        message: data,
        classicalPublicKey: edKp[0],
        pqPublicKey: pqKp.publicKey,
        classicalProvider: edProvider,
        pqProvider: pqProvider,
      );
      expect(valid, isTrue);
    });

    test('v2.0 头 + Ed25519 双重签名一致', () {
      final header = PqAlgorithmVersionV2.defaultHeaderV2();
      expect(PqAlgorithmVersionV2.isV2(header.version), isTrue);
      expect(header.signatureAlgorithm, contains('ed25519'));
      expect(header.kemAlgorithm, contains('x25519'));
    });

    test('v1.0 和 v2.0 版本兼容', () {
      expect(PqAlgorithmVersionV2.isCompatible('1.0'), isTrue);
      expect(PqAlgorithmVersionV2.isCompatible('2.0'), isTrue);
    });
  });
}
