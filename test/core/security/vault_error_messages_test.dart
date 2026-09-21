import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/core/security/vault_key_service.dart';
import 'package:drawing_notes_app/core/security/vault_error_messages.dart';
import 'package:drawing_notes_app/core/storage/vault_file_codec.dart';

void main() {
  test('describeVaultError 映射锁定/密码/解锁失败为非空人话', () {
    expect(
      describeVaultError(const VaultFileLockException(), null),
      isNotEmpty,
    );
    expect(
      describeVaultError(const VaultFilePasswordLockException(), null),
      isNotEmpty,
    );
    expect(
      describeVaultError(const VaultUnlockException('PIN 错误或密钥载荷被篡改'), null),
      contains('PIN'),
    );
    expect(
      describeVaultError(const VaultFileException('密钥不匹配或密文被篡改'), null),
      isNotEmpty,
    );
    expect(describeVaultError(FormatException('x'), null), isNotEmpty);
    expect(describeVaultError(null, null), isNotEmpty);
  });

  test('未知异常不透出实现细节前缀', () {
    final msg = describeVaultError(Exception('internal secret'), null);
    expect(msg, isNot(contains('secret')));
  });
}
