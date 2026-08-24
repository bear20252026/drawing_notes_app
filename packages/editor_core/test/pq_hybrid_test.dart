import 'package:test/test.dart';

import 'package:editor_core/editor_core.dart';

/// SAFE 2026/AgePony 借鉴——PQHybridService 后量子混合测试（纯逻辑——不搞崩）。
void main() {
  test('PqHybridConfig：默认值', () {
    const config = PqHybridConfig();
    expect(config.enabled, true);
    expect(config.kemAlgorithm, 'ml-kem-768');
    expect(config.classicalKem, 'x25519');
    expect(config.kdf, 'hkdf-sha256');
    expect(config.aead, 'aes-256-gcm');
  });

  test('deriveSession：X25519 + ML-KEM → HKDF 组合密钥', () {
    const service = PqHybridService();
    // X25519 共享秘密（32 字节）+ ML-KEM 共享秘密（32 字节）。
    final x25519Secret = List.generate(32, (i) => i * 3 % 256);
    final mlkemSecret = List.generate(32, (i) => i * 5 % 256);
    final session = service.deriveSession(
      sessionId: 's1',
      x25519Secret: x25519Secret,
      mlkemSecret: mlkemSecret,
    );
    expect(session.sessionId, 's1');
    expect(session.derivedKey.length, 32); // AES-256 密钥。
    expect(session.config.kemAlgorithm, 'ml-kem-768');
  });

  test('deriveAeadKey：返回派生密钥（AES-256-GCM 用）', () {
    const service = PqHybridService();
    final session = service.deriveSession(
      sessionId: 's1',
      x25519Secret: List.generate(32, (i) => i),
      mlkemSecret: List.generate(32, (i) => i + 1),
    );
    final aeadKey = service.deriveAeadKey(session);
    expect(aeadKey, session.derivedKey);
    expect(aeadKey.length, 32);
  });

  test('deriveSession：不同秘密 → 不同派生密钥', () {
    const service = PqHybridService();
    final s1 = service.deriveSession(
      sessionId: 's1',
      x25519Secret: List.generate(32, (i) => i),
      mlkemSecret: List.generate(32, (i) => i),
    );
    final s2 = service.deriveSession(
      sessionId: 's2',
      x25519Secret: List.generate(32, (i) => i + 1),
      mlkemSecret: List.generate(32, (i) => i + 1),
    );
    expect(s1.derivedKey, isNot(equals(s2.derivedKey)));
  });

  test('validateSecrets：密钥长度验证（≥32 字节）', () {
    const service = PqHybridService();
    expect(
      service.validateSecrets(List.filled(32, 0), List.filled(32, 0)),
      true,
    );
    expect(
      service.validateSecrets(List.filled(16, 0), List.filled(32, 0)),
      false, // X25519 不足 32。
    );
    expect(
      service.validateSecrets(List.filled(32, 0), List.filled(16, 0)),
      false, // ML-KEM 不足 32。
    );
  });

  test('PqHybridConfig：copyWith 不可变', () {
    const config = PqHybridConfig();
    final updated = config.copyWith(enabled: false);
    expect(config.enabled, true); // 原实例不变。
    expect(updated.enabled, false);
  });

  test('PqHybridSession：copyWith + 相等性', () {
    const session = PqHybridSession(
      sessionId: 's1',
      x25519Secret: [1],
      mlkemSecret: [2],
      derivedKey: [3],
      config: PqHybridConfig(),
    );
    final updated = session.copyWith(derivedKey: [9]);
    expect(session.derivedKey, [3]); // 原实例不变。
    expect(updated.derivedKey, [9]);
    const other = PqHybridSession(
      sessionId: 's1',
      x25519Secret: [9],
      mlkemSecret: [9],
      derivedKey: [9],
      config: PqHybridConfig(),
    );
    expect(session, other); // 按 sessionId 相等。
  });
}
