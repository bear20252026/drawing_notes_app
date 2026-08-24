import 'package:test/test.dart';

import 'package:editor_core/editor_core.dart';

/// 后量子迁移借鉴——EnvelopeEncryptionService 信封加密测试（纯逻辑——不搞崩）。
void main() {
  test('generateDek：生成 32 字节 DEK', () {
    const service = EnvelopeEncryptionService();
    final dek = service.generateDek();
    expect(dek.length, 32);
  });

  test('generateNonce：生成 12 字节 nonce', () {
    const service = EnvelopeEncryptionService();
    final nonce = service.generateNonce();
    expect(nonce.length, 12);
  });

  test('wrapDek/unwrapDek：AES-256 Key Wrap 往返', () {
    const service = EnvelopeEncryptionService();
    final dek = List.generate(32, (i) => i * 3 % 256);
    final kek = List.generate(32, (i) => i * 5 % 256);
    final wrapped = service.wrapDek(dek, kek);
    // RFC 3394：wrappedDek 长度 = dek.length + 8 = 40 字节。
    expect(wrapped.length, 40);
    final unwrapped = service.unwrapDek(wrapped, kek);
    expect(unwrapped, dek); // 往返一致。
  });

  test('seal/open：AES-256-GCM 信封加密流程', () {
    const service = EnvelopeEncryptionService();
    final dek = service.generateDek();
    final kek = List.generate(32, (i) => i * 7 % 256);
    final plain = List.generate(64, (i) => i * 11 % 256);

    final envelope = service.seal(
      keyId: 'kek-1',
      plain: plain,
      dek: dek,
      kek: kek,
    );
    expect(envelope.keyId, 'kek-1');
    // RFC 3394：wrappedDek 长度 = 32 + 8 = 40 字节。
    expect(envelope.wrappedDek.length, 40);
    // AES-256-GCM：密文 = 明文长度 + 16 字节认证标签。
    expect(envelope.ciphertext.length, 64 + 16);
    expect(envelope.version, 1);

    final opened = service.open(envelope: envelope, kek: kek);
    expect(opened, plain); // 解密往返一致。
  });

  test('seal：不同 DEK 产生不同密文（每对象独立密钥）', () {
    const service = EnvelopeEncryptionService();
    final kek = List.generate(32, (i) => i * 7 % 256);
    final plain = List.generate(32, (i) => i);

    final envelope1 = service.seal(keyId: 'kek-1', plain: plain, dek: service.generateDek(), kek: kek);
    final envelope2 = service.seal(keyId: 'kek-1', plain: plain, dek: service.generateDek(), kek: kek);
    // 不同 DEK → 不同密文（信封加密价值：每对象独立密钥）。
    expect(envelope1.ciphertext, isNot(equals(envelope2.ciphertext)));
  });

  test('wrapDek：KEK 长度不匹配抛异常', () {
    const service = EnvelopeEncryptionService();
    final dek = List.generate(32, (i) => i);
    final shortKek = List.generate(16, (i) => i); // AES-256 需要 32 字节。
    expect(() => service.wrapDek(dek, shortKek), throwsA(isA<AssertionError>()));
  });

  test('DataEnvelope：copyWith + 相等性', () {
    const envelope = DataEnvelope(
      keyId: 'k1',
      wrappedDek: [1, 2],
      ciphertext: [3, 4],
      nonce: [5, 6],
    );
    final updated = envelope.copyWith(version: 2);
    expect(envelope.version, 1); // 原实例不变。
    expect(updated.version, 2);
    const other = DataEnvelope(keyId: 'k1', wrappedDek: [9], ciphertext: [8], nonce: [7]);
    expect(envelope, other); // 按 keyId 相等。
  });

  test('KeyVersion：copyWith + 相等性', () {
    final now = DateTime.now();
    final version = KeyVersion(id: 'k1', createdAt: now, status: true);
    final retired = version.copyWith(status: false);
    expect(version.status, true); // 原实例不变。
    expect(retired.status, false);
    final other = KeyVersion(id: 'k1', createdAt: now, status: true);
    expect(version, other);
  });
}
