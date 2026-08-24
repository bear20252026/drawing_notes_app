// editor_core——ThreeLayerEncryption 三层封装加密测试（2026-08-24）。
//
// 覆盖三层加密/解密闭环、ECDSA签名/验签、随机填充、信封加密、
// 签名篡改检测、告警回调、密钥轮换、性能基准。
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:editor_core/src/domain/three_layer_encryption.dart';
import 'package:editor_core/src/domain/crypto_utils.dart';
import 'package:editor_core/src/domain/envelope_encryption.dart';
import 'package:pointycastle/export.dart';
import 'package:test/test.dart';

/// 生成 32 字节安全随机密钥。
Uint8List generateSecureKey() {
  final secureRandom = FortunaRandom();
  final random = Random.secure();
  final seeds = List.generate(32, (_) => random.nextInt(256));
  secureRandom.seed(KeyParameter(Uint8List.fromList(seeds)));
  final key = Uint8List(32);
  for (var i = 0; i < 32; i++) {
    key[i] = secureRandom.nextUint8();
  }
  return key;
}

void main() {
  group('SigningKeyPair', () {
    test('创建密钥对不可变', () {
      final pair = SigningKeyPair(
        publicKey: List.filled(65, 1),
        privateKey: List.filled(32, 2),
        createdAt: DateTime(2026, 8, 24),
      );

      expect(pair.publicKey.length, equals(65));
      expect(pair.privateKey.length, equals(32));
      expect(pair.algorithm, equals('ecdsa-p256'));
    });

    test('copyWith 修改字段', () {
      final pair = SigningKeyPair(
        publicKey: List.filled(65, 1),
        privateKey: List.filled(32, 2),
        createdAt: DateTime(2026, 8, 24),
      );

      final modified = pair.copyWith(publicKey: List.filled(65, 9));
      expect(modified.publicKey, equals(List.filled(65, 9)));
      expect(modified.privateKey, equals(List.filled(32, 2)));
    });
  });

  group('SignatureResult', () {
    test('创建签名结果不可变', () {
      final sig = SignatureResult(
        signature: List.filled(70, 0xAB),
        dataHash: List.filled(32, 0xCD),
        signedAt: DateTime(2026, 8, 24),
        metadata: {'version': 1},
      );

      expect(sig.signature.length, equals(70));
      expect(sig.dataHash.length, equals(32));
      expect(sig.algorithm, equals('ecdsa-p256'));
    });
  });

  group('SignatureService', () {
    late SignatureService service;

    setUp(() {
      service = const SignatureService();
    });

    test('生成密钥对', () {
      final pair = service.generateKeyPair();

      expect(pair.publicKey.length, equals(65));
      expect(pair.privateKey.length, equals(32));
      expect(pair.createdAt, isNotNull);
      expect(pair.algorithm, equals('ecdsa-p256'));
    });

    test('签名+验签闭环', () {
      final pair = service.generateKeyPair();
      final data = utf8.encode('Hello, ECDSA!');

      final sig = service.sign(
        data: data,
        keyPair: pair,
        metadata: {'test': true},
      );

      expect(sig.signature.length, greaterThan(0));
      expect(sig.dataHash.length, equals(32));
      expect(sig.metadata['test'], equals(true));

      final valid = service.verify(
        data: data,
        sig: sig,
        publicKey: pair.publicKey,
      );

      expect(valid, isTrue);
    });

    test('篡改数据导致验签失败', () {
      final pair = service.generateKeyPair();
      final data = utf8.encode('Original data');

      final sig = service.sign(data: data, keyPair: pair);

      // 篡改数据。
      final tamperedData = utf8.encode('Tampered data');
      var alertCalled = false;
      String? alertContext;

      final valid = service.verify(
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
      expect(alertContext, contains('SHA-256'));
    });

    test('篡改签名导致验签失败', () {
      final pair = service.generateKeyPair();
      final data = utf8.encode('Test data');

      final sig = service.sign(data: data, keyPair: pair);

      // 篡改签名（翻转第一个字节）。
      final tamperedSig = sig.copyWith(
        signature: List.from(sig.signature)..[0] ^= 0xFF,
      );
      var alertCalled = false;

      final valid = service.verify(
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

    test('错误公钥导致验签失败', () {
      final pair1 = service.generateKeyPair();
      final pair2 = service.generateKeyPair();
      final data = utf8.encode('Test data');

      final sig = service.sign(data: data, keyPair: pair1);

      final valid = service.verify(
        data: data,
        sig: sig,
        publicKey: pair2.publicKey, // 错误公钥。
      );

      expect(valid, isFalse);
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

    test('三层加密解密闭环', () {
      final k1 = generateSecureKey();
      final k2 = generateSecureKey();
      final k3 = generateSecureKey();
      final kek = generateSecureKey();
      final signingKeyPair = signatureService.generateKeyPair();

      final plaintext = utf8.encode('三层加密测试数据——军工级安全');

      final result = service.encrypt(
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
      expect(result.signature.signature.length, greaterThan(0));
      expect(result.signature.metadata['layers'], equals(3));

      // 验证信封。
      expect(result.envelope.keyId, equals('test-key-001'));

      // 解密。
      final decrypted = service.decrypt(
        result: result,
        k1: k1,
        k2: k2,
        kek: kek,
        signingPublicKey: signingKeyPair.publicKey,
      );

      expect(decrypted, equals(plaintext));
    });

    test('空数据三层加密解密', () {
      final k1 = generateSecureKey();
      final k2 = generateSecureKey();
      final k3 = generateSecureKey();
      final kek = generateSecureKey();
      final signingKeyPair = signatureService.generateKeyPair();

      final result = service.encrypt(
        plaintext: Uint8List(0),
        k1: k1,
        k2: k2,
        k3: k3,
        signingKeyPair: signingKeyPair,
        kek: kek,
      );

      final decrypted = service.decrypt(
        result: result,
        k1: k1,
        k2: k2,
        kek: kek,
        signingPublicKey: signingKeyPair.publicKey,
      );

      expect(decrypted, isEmpty);
    });

    test('大数据三层加密解密（1MB）', () {
      final k1 = generateSecureKey();
      final k2 = generateSecureKey();
      final k3 = generateSecureKey();
      final kek = generateSecureKey();
      final signingKeyPair = signatureService.generateKeyPair();

      // 1MB 测试数据。
      final plaintext = Uint8List(1024 * 1024);
      for (var i = 0; i < plaintext.length; i++) {
        plaintext[i] = i % 256;
      }

      final result = service.encrypt(
        plaintext: plaintext,
        k1: k1,
        k2: k2,
        k3: k3,
        signingKeyPair: signingKeyPair,
        kek: kek,
      );

      final decrypted = service.decrypt(
        result: result,
        k1: k1,
        k2: k2,
        kek: kek,
        signingPublicKey: signingKeyPair.publicKey,
      );

      expect(decrypted, equals(plaintext));
    });

    test('签名篡改导致解密失败', () {
      final k1 = generateSecureKey();
      final k2 = generateSecureKey();
      final k3 = generateSecureKey();
      final kek = generateSecureKey();
      final signingKeyPair = signatureService.generateKeyPair();

      final result = service.encrypt(
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

    test('错误 KEK 导致解密失败', () {
      final k1 = generateSecureKey();
      final k2 = generateSecureKey();
      final k3 = generateSecureKey();
      final kek = generateSecureKey();
      final wrongKek = generateSecureKey();
      final signingKeyPair = signatureService.generateKeyPair();

      final result = service.encrypt(
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

    test('随机填充长度范围正确', () {
      final k1 = generateSecureKey();
      final k2 = generateSecureKey();
      final k3 = generateSecureKey();
      final kek = generateSecureKey();
      final signingKeyPair = signatureService.generateKeyPair();

      // 多次加密验证填充范围。
      for (var i = 0; i < 10; i++) {
        final result = service.encrypt(
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

    test('信封加密支持密钥轮换', () {
      final k1 = generateSecureKey();
      final k2 = generateSecureKey();
      final k3 = generateSecureKey();
      final kek1 = generateSecureKey(); // 旧 KEK。
      final kek2 = generateSecureKey(); // 新 KEK。
      final signingKeyPair = signatureService.generateKeyPair();

      // 用旧 KEK 加密。
      final result = service.encrypt(
        plaintext: utf8.encode('密钥轮换测试'),
        k1: k1,
        k2: k2,
        k3: k3,
        signingKeyPair: signingKeyPair,
        kek: kek1,
        keyId: 'v1',
      );

      // 用旧 KEK 解密。
      final decrypted1 = service.decrypt(
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
      final decrypted2 = service.decrypt(
        result: rotatedResult,
        k1: k1,
        k2: k2,
        kek: kek2,
        signingPublicKey: signingKeyPair.publicKey,
      );
      expect(decrypted2, equals(utf8.encode('密钥轮换测试')));
    });

    test('版本号向前兼容', () {
      final k1 = generateSecureKey();
      final k2 = generateSecureKey();
      final k3 = generateSecureKey();
      final kek = generateSecureKey();
      final signingKeyPair = signatureService.generateKeyPair();

      final result = service.encrypt(
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

    test('性能基准——1MB 数据', () {
      final k1 = generateSecureKey();
      final k2 = generateSecureKey();
      final k3 = generateSecureKey();
      final kek = generateSecureKey();
      final signingKeyPair = signatureService.generateKeyPair();

      final plaintext = Uint8List(1024 * 1024);
      for (var i = 0; i < plaintext.length; i++) {
        plaintext[i] = i % 256;
      }

      final stopwatch = Stopwatch()..start();

      final result = service.encrypt(
        plaintext: plaintext,
        k1: k1,
        k2: k2,
        k3: k3,
        signingKeyPair: signingKeyPair,
        kek: kek,
      );

      stopwatch.stop();
      final encryptMs = stopwatch.elapsedMilliseconds;

      // 解密计时。
      final decryptStopwatch = Stopwatch()..start();
      service.decrypt(
        result: result,
        k1: k1,
        k2: k2,
        kek: kek,
        signingPublicKey: signingKeyPair.publicKey,
      );
      decryptStopwatch.stop();
      final decryptMs = decryptStopwatch.elapsedMilliseconds;

      // 打印性能结果。
      print('三层加密 1MB: ${encryptMs}ms');
      print('三层解密 1MB: ${decryptMs}ms');

      // 性能要求：<100ms/MB（宽松检查——CI 环境可能较慢）。
      expect(encryptMs, lessThan(1000));
      expect(decryptMs, lessThan(1000));
    });
  });

  group('SignatureVerificationException', () {
    test('异常消息包含上下文', () {
      final exception = SignatureVerificationException(
        '签名验证失败',
        context: 'L3 外层验签',
        metadata: {'key': 'value'},
      );

      expect(exception.toString(), contains('签名验证失败'));
      expect(exception.toString(), contains('L3 外层验签'));
      expect(exception.message, equals('签名验证失败'));
      expect(exception.context, equals('L3 外层验签'));
      expect(exception.metadata['key'], equals('value'));
    });
  });
}
