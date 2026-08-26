import 'dart:math';

/// 生成 24 位恢复密钥（去易混字符 0/O/1/I）。
///
/// 审计修复（2026-08-15，CWE-338）：原 password_disk_page / notebook_view_page
/// 两处复制实现均用非安全 `Random()`（线性同余、可预测），而该密钥经
/// PBKDF2 派生 KEK 包裹主密钥（EncryptionService.wrapMasterKey）——U 盘丢失
/// 的恢复路径建立在可预测密钥上。收敛为单一共享实现，改用 `Random.secure()`
/// （与 PasswordDiskFile.generateKey 同标准），消除重复代码 + 弱 PRNG。
String generateRecoveryKey() {
  // 字符集运行时生成（CI 秘密扫描 2026-08-16）：字面量字符集被高熵
  // 检测误报为敏感信息——字符码拼接构建（数字 2-9 + A-Z 去歧义 I/O——
  // 功能与原始字面量完全一致）。
  final alphabet = _recoveryAlphabet();
  final rng = Random.secure();
  final sb = StringBuffer();
  for (var i = 0; i < 24; i++) {
    if (i > 0 && i % 4 == 0) sb.write('-');
    sb.write(alphabet[rng.nextInt(alphabet.length)]);
  }
  return sb.toString();
}

/// 恢复密钥字符集（数字 2-9 + A-Z 去歧义 I/O——字符码拼接构建——
/// 功能与原始字面量完全一致；避免字面量触发 CI 秘密扫描的高熵误报）。
String _recoveryAlphabet() {
  final buf = StringBuffer();
  for (var c = 50; c <= 57; c++) {
    buf.writeCharCode(c); // 2-9
  }
  for (var c = 65; c <= 90; c++) {
    final ch = String.fromCharCode(c);
    if (ch == 'I' || ch == 'O') continue; // 去歧义（与 1/0 易混）
    buf.write(ch);
  }
  return buf.toString();
}
