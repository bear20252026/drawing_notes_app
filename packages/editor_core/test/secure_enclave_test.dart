import 'package:test/test.dart';

import 'package:editor_core/editor_core.dart';

/// 中文平台 TEE 调研借鉴——SecureEnclaveService 测试（纯逻辑——不搞崩）。
void main() {
  test('generateKey：TEE 内生成密钥（硬件备份——不可导出）', () {
    const service = SecureEnclaveService();
    final key = service.generateKey('key-1');
    expect(key.keyId, 'key-1');
    expect(key.hardwareBacked, true); // 硬件备份。
    expect(key.exportable, false);     // 不可导出（最强保护）。
    expect(key.attestation, isNotEmpty); // 远程证明。
  });

  test('importKey：外部密钥包裹后存入 TEE', () {
    const service = SecureEnclaveService();
    final keyMaterial = List.generate(32, (i) => i * 3 % 256);
    final kek = List.generate(32, (i) => i * 5 % 256);
    final key = service.importKey(
      keyId: 'imported-1',
      keyMaterial: keyMaterial,
      kek: kek,
    );
    expect(key.hardwareBacked, true);
    expect(key.wrappedKey.length, 32); // 已包裹。
    expect(key.wrappedKey, isNot(equals(keyMaterial))); // 与明文不同。
  });

  test('isHardwareBacked：硬件备份检查', () {
    const service = SecureEnclaveService();
    final key = service.generateKey('key-1');
    expect(service.isHardwareBacked(key), true);
  });

  test('canExport：不可导出 = 最强保护', () {
    const service = SecureEnclaveService();
    final key = service.generateKey('key-1');
    expect(service.canExport(key), false); // 默认不可导出。

    final exportable = key.copyWith(exportable: true);
    expect(service.canExport(exportable), true);
  });

  test('SecureEnclaveKey：copyWith + 相等性', () {
    const key = SecureEnclaveKey(keyId: 'k1');
    final updated = key.copyWith(exportable: true, attestation: 'attest-x');
    expect(key.exportable, false); // 原实例不变。
    expect(updated.exportable, true);
    expect(updated.attestation, 'attest-x');
    const other = SecureEnclaveKey(keyId: 'k1');
    expect(key, other); // 按 keyId 相等。
  });

  test('SecureEnclaveKey：默认值', () {
    const key = SecureEnclaveKey(keyId: 'k1');
    expect(key.hardwareBacked, true);
    expect(key.exportable, false);
    expect(key.attestation, '');
    expect(key.wrappedKey, isEmpty);
  });
}
