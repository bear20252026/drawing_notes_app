import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/storage/password_disk.dart';

/// 红蓝攻防 D-5 修复（2026-08-15）：key.frogkey 可选 PIN 自加密核心机制。
/// v2 格式用 PIN 派生 KEK 包裹主密钥（OWASP KEK 模式），v1 明文格式兼容保留。
void main() {
  test('PasswordDiskFile v2：PIN 包裹/解包往返还原主密钥', () async {
    final key = PasswordDiskFile.generateKey();
    final encoded = await PasswordDiskFile.encodeWithPin(
      key: key,
      pin: '123456',
    );
    expect(encoded[4], 0x02, reason: 'v2 版本标记');
    final decoded = await PasswordDiskFile.decodeWithPin(encoded, '123456');
    expect(decoded, key);
  });

  test('PasswordDiskFile v2：错误 PIN 返回 null（KEK 认证失败）', () async {
    final key = PasswordDiskFile.generateKey();
    final encoded = await PasswordDiskFile.encodeWithPin(
      key: key,
      pin: '123456',
    );
    expect(
      await PasswordDiskFile.decodeWithPin(encoded, 'wrong-pin'),
      isNull,
    );
  });

  test('PasswordDiskFile v2：损坏/非 v2 输入返回 null', () async {
    expect(await PasswordDiskFile.decodeWithPin(const [1, 2, 3], '123456'), isNull);
  });
}
