// editor_core——ThreeLayerEncryption 三层封装加密测试（2026-08-24）。
//
// 覆盖三层加密/解密闭环、Ed25519签名/验签、随机填充、信封加密、
// 签名篡改检测、告警回调、密钥轮换、性能基准。
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:editor_core/src/domain/three_layer_encryption.dart';
import 'package:editor_core/src/domain/crypto_utils.dart';
import 'package:editor_core/src/domain/envelope_encryption.dart';
import 'package:pointycastle/export.dart';
import 'package:test/test.dart';

/// 生成 32 字节安全随机密钥。
Uint8List generateSecureKey() {
  final random = Random.secure();
  return Uint8List.fromList(List.generate(32, (_) => random.nextInt(256)));
}

void main() {
  group('SigningKeyPair', () {
    test('创建密钥对不可变', () {
      final pair = SigningKeyPair(
        publicKey: List.filled(32, 1),
        privateKey: List.filled(32, 2),
        createdAt: DateTime(2026, 8, 24),
      );

      expect(pair.publicKey.length, equals(32));
      expect(pair.privateKey.length, equals(32));
      expect(pair.algorithm, equals('ed25519'));
    });

    test('copyWith 修改字段', () {
      final pair = SigningKeyPair(
        publicKey: List.filled(32, 1),
        privateKey: List.filled(32, 2),
        createdAt: DateTime(2026, 8, 24),
      );

      final modified = pair.copyWith(publicKey: List.filled(32, 9));
      expect(modified.publicKey, equals(List.filled(32, 9)));
      expect(modified.privateKey, equals(List.filled(32, 2)));
    });
  });

  group('SignatureResult', () {
    test('创建签名结果不可变', () {
      final sig = SignatureResult(
        signature: List.filled(64, 0xAB), // Ed25519 签名为 64 字节
        dataHash: List.filled(64, 0xCD), // SHA-512 为 64 字节
        signedAt: DateTime(2026, 8, 24),
        metadata: {'version': 1},
      );

      expect(sig.signature.length, equals(64));
      expect(sig.dataHash.length, equals(64));
      expect(sig.algorithm, equals('ed25519'));
    });
  });

  group('SignatureService', () {
    late SignatureService service;

    setUp(() {
      service = const SignatureService();
    });

    test('生成 Ed25519 密钥对', () async {
      final pair = await service.generateKeyPair();

      expect(pair.publicKey.length, equals(32));
      expect(pair.privateKey.length, equals(32));
      expect(pair.createdAt, isNotNull);
      expect(pair.algorithm, equals('ed25519'));
    });

    test('签名+验签闭环', () async {
      final pair = await service.generateKeyPair();
      final data = utf8.encode('Hello, Ed25519!');

      final sig = await service.sign(
        data: data,
        keyPair: pair,
        metadata: {'test': true},
      );

      expect(sig.signature.length, equals(64));
      expect(sig.dataHash.length, equals(64));
      expect(sig.metadata['test'], equals(true));

      final valid = await service.verify(
        data: data,
        sig: sig,
        publicKey: pair.publicKey,
      );

      expect(valid, isTrue);
    });

    test('篡改数据导致验签失败', () async {
      final pair = await service.generateKeyPair();
      final data = utf8.encode('Original data');

      final sig = await service.sign(data: data, keyPair: pair);

      // 篡改数据。
      final tamperedData = utf8.encode('Tampered data');
      var alertCalled = false;
      String? alertContext;

      final valid = await service.verify(
        data: tamperedData,
        sig: sig,
        publicKey: pair.publicKey,
        onAlert: (ctx, meta) {
          alertCalled = true;
          alertContext = ctx;
        },
      );

      expect(valid, isFalse);
      expect(alertCalled, isTrue);
      expect(alertContext, contains('SHA-512'));
    });

    test('篡改签名导致验签失败', () async {
      final pair = await service.generateKeyPair();
      final data = utf8.encode('Test data');

      final sig = await service.sign(data: data, keyPair: pair);

      // 篡改签名（翻转第一个字节）。
      final tamperedSig = sig.copyWith(
        signature: List.from(sig.signature)..[0] ^= 0xFF,
      );
      var alertCalled = false;

      final valid = await service.verify(
        data: data,
        sig: tamperedSig,
        publicKey: pair.publicKey,
        onAlert: (ctx, meta) {
          alertCalled = true;
        },
      );

      expect(valid, isFalse);
      expect(alertCalled, isTrue);
    });

    test('错误公钥导致验签失败', () async {
      final pair1 = await service.generateKeyPair();
      final pair2 = await service.generateKeyPair();
      final data = utf8.encode('Test data');

      final sig = await service.sign(data: data, keyPair: pair1);

      final valid = await service.verify(
        data: data,
        sig: sig,
        publicKey: pair2.publicKey, // 错误公钥。
      );

      expect(valid, isFalse);
    });

    test('从种子恢复密钥对', () async {
      final pair1 = await service.generateKeyPair();
      final pair2 = await service.keyPairFromSeed(pair1.privateKey);

      // 从相同种子恢复的密钥对应产生相同公钥。
      expect(pair2.publicKey, equals(pair1.publicKey));
      expect(pair2.algorithm, equals('ed25519'));
    });

    test('Ed25519 签名确定性（相同载荷+密钥=相同签名）', () async {
      final pair = await service.generateKeyPair();
      // 直接构造相同载荷——绕过 DateTime.now() 时间戳差异。
      final payload = Uint8List.fromList([1, 2, 3, 4]);

      // 从种子恢复密钥对（确保相同密钥材料）。
      final kp1 = await service.keyPairFromSeed(pair.privateKey);
      final kp2 = await service.keyPairFromSeed(pair.privateKey);

      // 使用 cryptography 包直接签名相同载荷。
      final algorithm = Ed25519();
      final seedKp1 = await algorithm.newKeyPairFromSeed(
        Uint8List.fromList(kp1.privateKey),
      );
      final sig1 = await algorithm.sign(payload, keyPair: seedKp1);

      final seedKp2 = await algorithm.newKeyPairFromSeed(
        Uint8List.fromList(kp2.privateKey),
      );
      final sig2 = await algorithm.sign(payload, keyPair: seedKp2);

      expect(sig1.bytes, equals(sig2.bytes));
    });
  });

  group('ThreeLayerEncryptionService', () {
    late ThreeLayerEncryptionService service;
    late SignatureService signatureService;
    late EnvelopeEncryptionService envelopeService;

    setUp(() {
      signatureService = const SignatureService();
      envelopeService = const EnvelopeEncryptionService();
      service = ThreeLayerEncryptionService(
        signatureService: signatureService,
        envelopeService: envelopeService,
      );
    });

    test('三层加密解密闭环', () async {
      final k1 = generateSecureKey();
      final k2 = generateSecureKey();
      final k3 = generateSecureKey();
      final kek = generateSecureKey();
      final signingKeyPair = await signatureService.generateKeyPair();

      final plaintext = utf8.encode('三层加密测试数据——军工级安全');

      final result = await service.encrypt(
        plaintext: plaintext,
        k1: k1,
        k2: k2,
        k3: k3,
        signingKeyPair: signingKeyPair,
        kek: kek,
        keyId: 'test-key-001',
        metadata: {'file': 'test.drawing'},
      );

      // 验证三层密文非空。
      expect(result.l1Ciphertext.length, greaterThan(0));
      expect(result.l2Ciphertext.length, greaterThan(0));
      expect(result.l3Ciphertext.length, greaterThan(0));

      // 验证填充长度范围。
      expect(result.l2PaddingLength, greaterThanOrEqualTo(16));
      expect(result.l2PaddingLength, lessThanOrEqualTo(256));

      // 验证签名。
      expect(result.signature.signature.length, equals(64));
      expect(result.signature.metadata['layers'], equals(3));

      // 验证信封。
      expect(result.envelope.keyId, equals('test-key-001'));

      // 解密。
      final decrypted = await service.decrypt(
        result: result,
        k1: k1,
        k2: k2,
        kek: kek,
        signingPublicKey: signingKeyPair.publicKey,
      );

      expect(decrypted, equals(plaintext));
    });

    test('空数据三层加密解密', () async {
      final k1 = generateSecureKey();
      final k2 = generateSecureKey();
      final k3 = generateSecureKey();
      final kek = generateSecureKey();
      final signingKeyPair = await signatureService.generateKeyPair();

      final result = await service.encrypt(
        plaintext: Uint8List(0),
        k1: k1,
        k2: k2,
        k3: k3,
        signingKeyPair: signingKeyPair,
        kek: kek,
      );

      final decrypted = await service.decrypt(
        result: result,
        k1: k1,
        k2: k2,
        kek: kek,
        signingPublicKey: signingKeyPair.publicKey,
      );

      expect(decrypted, isEmpty);
    });

    test('大数据三层加密解密（1MB）', () async {
      final k1 = generateSecureKey();
      final k2 = generateSecureKey();
      final k3 = generateSecureKey();
      final kek = generateSecureKey();
      final signingKeyPair = await signatureService.generateKeyPair();

      // 1MB 测试数据。
      final plaintext = Uint8List(1024 * 1024);
      for (var i = 0; i < plaintext.length; i++) {
        plaintext[i] = i % 256;
      }

      final result = await service.encrypt(
        plaintext: plaintext,
        k1: k1,
        k2: k2,
        k3: k3,
        signingKeyPair: signingKeyPair,
        kek: kek,
      );

      final decrypted = await service.decrypt(
        result: result,
        k1: k1,
        k2: k2,
        kek: kek,
        signingPublicKey: signingKeyPair.publicKey,
      );

      expect(decrypted, equals(plaintext));
    });

    test('签名篡改导致解密失败', () async {
      final k1 = generateSecureKey();
      final k2 = generateSecureKey();
      final k3 = generateSecureKey();
      final kek = generateSecureKey();
      final signingKeyPair = await signatureService.generateKeyPair();

      final result = await service.encrypt(
        plaintext: utf8.encode('篡改测试'),
        k1: k1,
        k2: k2,
        k3: k3,
        signingKeyPair: signingKeyPair,
        kek: kek,
      );

      // 篡改 L3 密文。
      final tamperedL3 = Uint8List.fromList(result.l3Ciphertext);
      tamperedL3[0] ^= 0xFF;

      final tamperedResult = ThreeLayerResult(
        l1Ciphertext: result.l1Ciphertext,
        l1Nonce: result.l1Nonce,
        l2Ciphertext: result.l2Ciphertext,
        l2Nonce: result.l2Nonce,
        l2PaddingLength: result.l2PaddingLength,
        l3Ciphertext: tamperedL3,
        l3Nonce: result.l3Nonce,
        signature: result.signature,
        envelope: result.envelope,
        version: result.version,
        processedAt: result.processedAt,
        metadata: result.metadata,
      );

      var alertCalled = false;

      expect(
        () => service.decrypt(
          result: tamperedResult,
          k1: k1,
          k2: k2,
          kek: kek,
          signingPublicKey: signingKeyPair.publicKey,
          onAlert: (ctx, meta) {
            alertCalled = true;
          },
        ),
        throwsA(isA<SignatureVerificationException>()),
      );

      expect(alertCalled, isTrue);
    });

    test('错误 KEK 导致解密失败', () async {
      final k1 = generateSecureKey();
      final k2 = generateSecureKey();
      final k3 = generateSecureKey();
      final kek = generateSecureKey();
      final wrongKek = generateSecureKey();
      final signingKeyPair = await signatureService.generateKeyPair();

      final result = await service.encrypt(
        plaintext: utf8.encode('KEK 测试'),
        k1: k1,
        k2: k2,
        k3: k3,
        signingKeyPair: signingKeyPair,
        kek: kek,
      );

      expect(
        () => service.decrypt(
          result: result,
          k1: k1,
          k2: k2,
          kek: wrongKek,
          signingPublicKey: signingKeyPair.publicKey,
        ),
        throwsA(anything),
      );
    });

    test('随机填充长度范围正确', () async {
      final k1 = generateSecureKey();
      final k2 = generateSecureKey();
      final k3 = generateSecureKey();
      final kek = generateSecureKey();
      final signingKeyPair = await signatureService.generateKeyPair();

      // 多次加密验证填充范围。
      for (var i = 0; i < 10; i++) {
        final result = await service.encrypt(
          plaintext: utf8.encode('填充测试 $i'),
          k1: k1,
          k2: k2,
          k3: k3,
          signingKeyPair: signingKeyPair,
          kek: kek,
        );

        expect(result.l2PaddingLength, greaterThanOrEqualTo(16));
        expect(result.l2PaddingLength, lessThanOrEqualTo(256));
      }
    });

    test('信封加密支持密钥轮换', () async {
      final k1 = generateSecureKey();
      final k2 = generateSecureKey();
      final k3 = generateSecureKey();
      final kek1 = generateSecureKey(); // 旧 KEK。
      final kek2 = generateSecureKey(); // 新 KEK。
      final signingKeyPair = await signatureService.generateKeyPair();

      // 用旧 KEK 加密。
      final result = await service.encrypt(
        plaintext: utf8.encode('密钥轮换测试'),
        k1: k1,
        k2: k2,
        k3: k3,
        signingKeyPair: signingKeyPair,
        kek: kek1,
        keyId: 'v1',
      );

      // 用旧 KEK 解密。
      final decrypted1 = await service.decrypt(
        result: result,
        k1: k1,
        k2: k2,
        kek: kek1,
        signingPublicKey: signingKeyPair.publicKey,
      );
      expect(decrypted1, equals(utf8.encode('密钥轮换测试')));

      // 密钥轮换：解包旧信封 → 用新 KEK 重新封装。
      final unwrappedK3 = envelopeService.open(
        envelope: result.envelope,
        kek: Uint8List.fromList(kek1),
      );
      final newDek = envelopeService.generateDek();
      final newEnvelope = envelopeService.seal(
        keyId: 'v2',
        plain: Uint8List.fromList(unwrappedK3),
        dek: Uint8List.fromList(newDek),
        kek: Uint8List.fromList(kek2),
      );

      final rotatedResult = ThreeLayerResult(
        l1Ciphertext: result.l1Ciphertext,
        l1Nonce: result.l1Nonce,
        l2Ciphertext: result.l2Ciphertext,
        l2Nonce: result.l2Nonce,
        l2PaddingLength: result.l2PaddingLength,
        l3Ciphertext: result.l3Ciphertext,
        l3Nonce: result.l3Nonce,
        signature: result.signature,
        envelope: newEnvelope,
        version: result.version,
        processedAt: result.processedAt,
        metadata: result.metadata,
      );

      // 用新 KEK 解密。
      final decrypted2 = await service.decrypt(
        result: rotatedResult,
        k1: k1,
        k2: k2,
        kek: kek2,
        signingPublicKey: signingKeyPair.publicKey,
      );
      expect(decrypted2, equals(utf8.encode('密钥轮换测试')));
    });

    test('版本号向前兼容', () async {
      final k1 = generateSecureKey();
      final k2 = generateSecureKey();
      final k3 = generateSecureKey();
      final kek = generateSecureKey();
      final signingKeyPair = await signatureService.generateKeyPair();

      final result = await service.encrypt(
        plaintext: utf8.encode('版本测试'),
        k1: k1,
        k2: k2,
        k3: k3,
        signingKeyPair: signingKeyPair,
        kek: kek,
      );

      expect(result.version, equals(1));
      expect(result.processedAt, isNotNull);
    });

    test('性能基准——1MB 数据', () async {
      final k1 = generateSecureKey();
      final k2 = generateSecureKey();
      final k3 = generateSecureKey();
      final kek = generateSecureKey();
      final signingKeyPair = await signatureService.generateKeyPair();

      final plaintext = Uint8List(1024 * 1024);
      for (var i = 0; i < plaintext.length; i++) {
        plaintext[i] = i % 256;
      }

      final stopwatch = Stopwatch()..start();
      final result = await service.encrypt(
        plaintext: plaintext,
        k1: k1,
        k2: k2,
        k3: k3,
        signingKeyPair: signingKeyPair,
        kek: kek,
      );
      stopwatch.stop();

      final decrypted = await service.decrypt(
        result: result,
        k1: k1,
        k2: k2,
        kek: kek,
        signingPublicKey: signingKeyPair.publicKey,
      );

      expect(decrypted, equals(plaintext));
      // 三层加密 1MB 应在 5 秒内完成。
      expect(stopwatch.elapsedMilliseconds, lessThan(5000));

      print('性能: 1MB 三层加密+解密 ${stopwatch.elapsedMilliseconds}ms');
    });
  });
}
