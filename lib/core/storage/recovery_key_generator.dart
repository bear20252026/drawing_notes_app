import 'dart:math';

/// 生成 24 位恢复密钥（去易混字符 0/O/1/I）。
///
/// 审计修复（2026-08-15，CWE-338）：原 password_disk_page / notebook_view_page
/// 两处复制实现均用非安全 `Random()`（线性同余、可预测），而该密钥经
/// PBKDF2 派生 KEK 包裹主密钥（EncryptionService.wrapMasterKey）——U 盘丢失
/// 的恢复路径建立在可预测密钥上。收敛为单一共享实现，改用 `Random.secure()`
/// （与 PasswordDiskFile.generateKey 同标准），消除重复代码 + 弱 PRNG。
String generateRecoveryKey() {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final rng = Random.secure();
  final sb = StringBuffer();
  for (var i = 0; i < 24; i++) {
    if (i > 0 && i % 4 == 0) sb.write('-');
    sb.write(alphabet[rng.nextInt(alphabet.length)]);
  }
  return sb.toString();
}
