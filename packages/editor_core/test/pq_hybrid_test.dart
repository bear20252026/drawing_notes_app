import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:editor_core/editor_core.dart';

/// PQC 后量子混合加密测试（纯逻辑——不搞崩）。
void main() {
  group('PqAlgorithmVersion', () {
    test('常量定义正确', () {
      expect(PqAlgorithmVersion.current, '1.0');
      expect(PqAlgorithmVersion.minCompatible, '1.0');
      expect(PqAlgorithmVersion.kemX25519, 'x25519');
      expect(PqAlgorithmVersion.kemMlKem768, 'ml-kem-768');
      expect(PqAlgorithmVersion.sigEcdsaP256, 'ecdsa-p256');
      expect(PqAlgorithmVersion.sigMlDsa65, 'ml-dsa-65');
    });
  });

  group('PqHybridHeader', () {
    test('默认头创建成功', () {
      final header = PqHybridHeader.defaultHeader();
      expect(header.version, '1.0');
      expect(header.kemAlgorithm, 'x25519+ml-kem-768');
      expect(header.signatureAlgorithm, 'ecdsa-p256+ml-dsa-65');
      expect(header.kdfAlgorithm, 'hkdf-sha256');
      expect(header.aeadAlgorithm, 'aes-256-gcm');
      expect(header.salt.length, 32);
      expect(header.nonce.length, 12);
      expect(header.flags, 0x03);
      expect(header.isPqcEnabled, true);
      expect(header.isDualSignature, true);
    });

    test('序列化/反序列化往返', () {
      final original = PqHybridHeader.defaultHeader();
      final bytes = original.toBytes();
      final restored = PqHybridHeader.fromBytes(bytes);

      expect(restored.version, original.version);
      expect(restored.kemAlgorithm, original.kemAlgorithm);
      expect(restored.signatureAlgorithm, original.signatureAlgorithm);
      expect(restored.kdfAlgorithm, original.kdfAlgorithm);
      expect(restored.aeadAlgorithm, original.aeadAlgorithm);
      expect(restored.salt, original.salt);
      expect(restored.nonce, original.nonce);
      expect(restored.flags, original.flags);
    });

    test('魔数验证', () {
      final header = PqHybridHeader.defaultHeader();
      final bytes = header.toBytes();
      expect(bytes.sublist(0, 4), PqHybridHeader.magic);
    });

    test('版本兼容性检查', () {
      final header = PqHybridHeader.defaultHeader();
      expect(header.isCompatible(), true);

      final oldHeader = header.copyWith(version: '0.9');
      expect(oldHeader.isCompatible(), false);
    });

    test('flags 解析', () {
      final header1 = PqHybridHeader.defaultHeader();
      expect(header1.isPqcEnabled, true);
      expect(header1.isDualSignature, true);

      final header2 = header1.copyWith(flags: 0x00);
      expect(header2.isPqcEnabled, false);
      expect(header2.isDualSignature, false);

      final header3 = header1.copyWith(flags: 0x01);
      expect(header3.isPqcEnabled, true);
      expect(header3.isDualSignature, false);
    });

    test('太短的数据抛出异常', () {
      expect(
        () => PqHybridHeader.fromBytes(Uint8List(10)),
        throwsArgumentError,
      );
    });

    test('无效魔数抛出异常', () {
      final data = Uint8List(30);
      data[0] = 0xFF;
      expect(
        () => PqHybridHeader.fromBytes(data),
        throwsArgumentError,
      );
    });
  });

  group('PqHybridConfig', () {
    test('默认值', () {
      const config = PqHybridConfig();
      expect(config.enabled, true);
      expect(config.kemAlgorithm, 'ml-kem-768');
      expect(config.classicalKem, 'x25519');
      expect(config.signatureAlgorithm, 'ml-dsa-65');
      expect(config.classicalSignature, 'ecdsa-p256');
      expect(config.kdf, 'hkdf-sha256');
      expect(config.aead, 'aes-256-gcm');
    });

    test('copyWith 不可变', () {
      const config = PqHybridConfig();
      final updated = config.copyWith(enabled: false);
      expect(config.enabled, true);
      expect(updated.enabled, false);
    });

    test('toJson 序列化', () {
      const config = PqHybridConfig();
      final json = config.toJson();
      expect(json['enabled'], true);
      expect(json['kemAlgorithm'], 'ml-kem-768');
      expect(json['classicalKem'], 'x25519');
    });
  });

  group('PqHybridSession', () {
    test('copyWith + 相等性', () {
      final session = PqHybridSession(
        sessionId: 's1',
        x25519Secret: Uint8List.fromList([1]),
        mlkemSecret: Uint8List.fromList([2]),
        derivedKey: Uint8List.fromList([3]),
      );
      final updated = session.copyWith(derivedKey: Uint8List.fromList([9]));
      expect(session.derivedKey, Uint8List.fromList([3]));
      expect(updated.derivedKey, Uint8List.fromList([9]));

      final other = PqHybridSession(
        sessionId: 's1',
        x25519Secret: Uint8List.fromList([9]),
        mlkemSecret: Uint8List.fromList([9]),
        derivedKey: Uint8List.fromList([9]),
      );
      expect(session, other); // 按 sessionId 相等。
    });

    test('header 关联', () {
      final header = PqHybridHeader.defaultHeader();
      final session = PqHybridSession(
        sessionId: 's1',
        x25519Secret: Uint8List(32),
        mlkemSecret: Uint8List(32),
        derivedKey: Uint8List(32),
        header: header,
      );
      expect(session.header, isNotNull);
      expect(session.header!.version, '1.0');
    });
  });

  group('MlKem768', () {
    test('密钥对生成', () {
      final keyPair = MlKem768.generateKeyPair();
      expect(keyPair.publicKey.isNotEmpty, true);
      expect(keyPair.secretKey.isNotEmpty, true);
    });

    test('封装/解封往返', () {
      final keyPair = MlKem768.generateKeyPair();
      final encapsulation = MlKem768.encapsulate(keyPair.publicKey);

      expect(encapsulation.ciphertext.isNotEmpty, true);
      expect(encapsulation.sharedSecret.length, 32);

      final decapsulated = MlKem768.decapsulate(
        ciphertext: encapsulation.ciphertext,
        secretKey: keyPair.secretKey,
      );
      expect(decapsulated, encapsulation.sharedSecret);
    });

    test('不同密钥对产生不同共享秘密', () {
      final keyPair1 = MlKem768.generateKeyPair();
      final keyPair2 = MlKem768.generateKeyPair();

      final enc1 = MlKem768.encapsulate(keyPair1.publicKey);
      final enc2 = MlKem768.encapsulate(keyPair2.publicKey);

      expect(enc1.sharedSecret, isNot(equals(enc2.sharedSecret)));
    });
  });

  group('MlDsa65', () {
    test('密钥对生成', () {
      final keyPair = MlDsa65.generateKeyPair();
      expect(keyPair.publicKey.isNotEmpty, true);
      expect(keyPair.secretKey.isNotEmpty, true);
    });

    test('签名/验签往返', () {
      final keyPair = MlDsa65.generateKeyPair();
      final message = Uint8List.fromList(utf8.encode('test message'));

      final signature = MlDsa65.sign(
        message: message,
        secretKey: keyPair.secretKey,
      );

      expect(signature.isNotEmpty, true);

      final isValid = MlDsa65.verify(
        signature: signature,
        message: message,
        publicKey: keyPair.publicKey,
      );
      expect(isValid, true);
    });

    test('篡改消息验签失败', () {
      final keyPair = MlDsa65.generateKeyPair();
      final message = Uint8List.fromList(utf8.encode('original'));
      final tampered = Uint8List.fromList(utf8.encode('tampered'));

      final signature = MlDsa65.sign(
        message: message,
        secretKey: keyPair.secretKey,
      );

      final isValid = MlDsa65.verify(
        signature: signature,
        message: tampered,
        publicKey: keyPair.publicKey,
      );
      expect(isValid, false);
    });
  });

  group('PqHybridKem', () {
    test('封装/解封往返', () {
      final alice = PqHybridKem();
      final bob = PqHybridKem();

      final classicalShared = Uint8List.fromList(List.generate(32, (i) => i));
      final result = alice.encapsulate(
        peerMlkemPublicKey: bob.mlkemPublicKey,
        classicalSharedSecret: classicalShared,
      );

      expect(result.classicalShared, classicalShared);
      expect(result.pqShared.length, 32);
      expect(result.mlkemCiphertext.isNotEmpty, true);
      expect(result.combinedKey.length, 32);

      // Bob 解封装。
      final bobKey = bob.decapsulate(
        mlkemCiphertext: result.mlkemCiphertext,
        classicalSharedSecret: classicalShared,
      );
      expect(bobKey, result.combinedKey);
    });

    test('不同共享秘密产生不同合并密钥', () {
      final alice = PqHybridKem();
      final bob = PqHybridKem();

      final shared1 = Uint8List.fromList(List.generate(32, (i) => i));
      final shared2 = Uint8List.fromList(List.generate(32, (i) => i + 1));

      final result1 = alice.encapsulate(
        peerMlkemPublicKey: bob.mlkemPublicKey,
        classicalSharedSecret: shared1,
      );
      final result2 = alice.encapsulate(
        peerMlkemPublicKey: bob.mlkemPublicKey,
        classicalSharedSecret: shared2,
      );

      expect(result1.combinedKey, isNot(equals(result2.combinedKey)));
    });

    test('密钥长度不足抛出异常', () {
      final alice = PqHybridKem();
      final bob = PqHybridKem();

      expect(
        () => alice.encapsulate(
          peerMlkemPublicKey: bob.mlkemPublicKey,
          classicalSharedSecret: Uint8List(16),
        ),
        throwsArgumentError,
      );
    });
  });

  group('PqHybridSigner', () {
    test('签名/验签往返', () {
      final signer = PqHybridSigner();
      final message = Uint8List.fromList(utf8.encode('important document'));

      final result = signer.sign(message);

      expect(result.classicalSignature.isNotEmpty, true);
      expect(result.pqSignature.isNotEmpty, true);
      expect(result.combinedSignature.isNotEmpty, true);

      // 验证合并签名。
      final isValid = PqHybridSigner.verify(
        combinedSignature: result.combinedSignature,
        message: message,
        ecdsaPublicKey: signer.ecdsaPublicKey,
        mldsaPublicKey: signer.mldsaPublicKey,
      );
      expect(isValid, true);
    });

    test('篡改消息验签失败', () {
      final signer = PqHybridSigner();
      final message = Uint8List.fromList(utf8.encode('original'));
      final tampered = Uint8List.fromList(utf8.encode('tampered'));

      final result = signer.sign(message);

      final isValid = PqHybridSigner.verify(
        combinedSignature: result.combinedSignature,
        message: tampered,
        ecdsaPublicKey: signer.ecdsaPublicKey,
        mldsaPublicKey: signer.mldsaPublicKey,
      );
      expect(isValid, false);
    });

    test('提取子签名', () {
      final signer = PqHybridSigner();
      final message = Uint8List.fromList(utf8.encode('test'));

      final result = signer.sign(message);

      final ecdsaSig = PqHybridSigner.extractEcdsaSignature(result.combinedSignature);
      expect(ecdsaSig, result.classicalSignature);

      final mldsaSig = PqHybridSigner.extractMldsaSignature(result.combinedSignature);
      expect(mldsaSig, result.pqSignature);
    });
  });

  group('PqHybridService', () {
    test('deriveSession：X25519 + ML-KEM → HKDF 组合密钥', () {
      const service = PqHybridService();
      final x25519Secret = Uint8List.fromList(List.generate(32, (i) => i * 3 % 256));
      final mlkemSecret = Uint8List.fromList(List.generate(32, (i) => i * 5 % 256));
      final session = service.deriveSession(
        sessionId: 's1',
        x25519Secret: x25519Secret,
        mlkemSecret: mlkemSecret,
      );
      expect(session.sessionId, 's1');
      expect(session.derivedKey.length, 32);
      expect(session.config.kemAlgorithm, 'ml-kem-768');
    });

    test('deriveAeadKey：返回派生密钥', () {
      const service = PqHybridService();
      final session = service.deriveSession(
        sessionId: 's1',
        x25519Secret: Uint8List.fromList(List.generate(32, (i) => i)),
        mlkemSecret: Uint8List.fromList(List.generate(32, (i) => i + 1)),
      );
      final aeadKey = service.deriveAeadKey(session);
      expect(aeadKey, session.derivedKey);
      expect(aeadKey.length, 32);
    });

    test('不同秘密 → 不同派生密钥', () {
      const service = PqHybridService();
      final s1 = service.deriveSession(
        sessionId: 's1',
        x25519Secret: Uint8List.fromList(List.generate(32, (i) => i)),
        mlkemSecret: Uint8List.fromList(List.generate(32, (i) => i)),
      );
      final s2 = service.deriveSession(
        sessionId: 's2',
        x25519Secret: Uint8List.fromList(List.generate(32, (i) => i + 1)),
        mlkemSecret: Uint8List.fromList(List.generate(32, (i) => i + 1)),
      );
      expect(s1.derivedKey, isNot(equals(s2.derivedKey)));
    });

    test('validateSecrets：密钥长度验证', () {
      const service = PqHybridService();
      expect(
        service.validateSecrets(Uint8List(32), Uint8List(32)),
        true,
      );
      expect(
        service.validateSecrets(Uint8List(16), Uint8List(32)),
        false,
      );
      expect(
        service.validateSecrets(Uint8List(32), Uint8List(16)),
        false,
      );
    });

    test('加密/解密带文件头往返', () {
      const service = PqHybridService();
      final session = service.deriveSession(
        sessionId: 'test-session',
        x25519Secret: Uint8List.fromList(List.generate(32, (i) => i)),
        mlkemSecret: Uint8List.fromList(List.generate(32, (i) => i + 100)),
      );

      final plaintext = utf8.encode('Hello, PQC World!');
      final encrypted = service.encryptWithHeader(
        session: session,
        plaintext: plaintext,
      );

      // 验证包含 PQEH 魔数。
      expect(encrypted.sublist(0, 4), PqHybridHeader.magic);

      final decrypted = service.decryptWithHeader(
        session: session,
        data: encrypted,
      );
      expect(decrypted, plaintext);
    });
  });
}
