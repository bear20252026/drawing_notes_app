import 'package:drawing_notes_app/core/security/quick_unlock_service.dart';
import 'package:drawing_notes_app/core/security/vault_key_service.dart';
import 'package:drawing_notes_app/core/storage/vault_file_codec.dart';
import 'package:drawing_notes_app/l10n/app_localizations.dart';

/// UI 边界：vault / encryption 技术异常 → 本地化人话（E1 存量）。
///
/// **domain 保留技术 reason**（toString / 日志 / 测试）；**展示层禁止
/// 直接透出 `e.reason` / `e.toString()`**。未知类型回退通用文案，避免
/// 把内部实现细节（信封版本、字段名）写进 SnackBar。
///
/// 落盘位置 `core/security/`（非 `core/utils/`）：本文件依赖 security/
/// storage 异常类型 + l10n，若放在 utils 会把 Martin I 顶过 0.4 稳定层
/// 基线（architecture_test 规则 3b）。
String describeVaultError(Object? error, AppLocalizations? l10n) {
  if (error == null) return l10n?.vaultErrUnknown ?? '发生未知错误';
  if (error is VaultFileLockException) {
    return l10n?.vaultErrLocked ?? '保险库已锁定，加密文件不可读';
  }
  if (error is VaultFilePasswordLockException) {
    return l10n?.vaultErrFilePassword ?? '文件受独立密码保护';
  }
  if (error is VaultUnlockException) {
    return _mapUnlockReason(error.reason, l10n);
  }
  if (error is QuickUnlockException) {
    return _mapUnlockReason(error.reason, l10n);
  }
  if (error is VaultFileException) {
    return _mapFileReason(error.reason, l10n);
  }
  if (error is FormatException) {
    return l10n?.vaultErrCorrupt ?? '数据格式异常或已损坏';
  }
  return l10n?.vaultErrUnknown ?? '发生未知错误';
}

String _mapUnlockReason(String reason, AppLocalizations? l10n) {
  if (reason.contains('不存在')) {
    return l10n?.vaultErrNoVault ?? '保险库不存在（尚未设置密码）';
  }
  if (reason.contains('为空')) {
    return l10n?.vaultErrEmptyPin ?? 'PIN 不能为空';
  }
  if (reason.contains('槽位')) {
    return l10n?.vaultErrMissingSlot ?? '保险库缺少 PIN 槽位';
  }
  if (reason.contains('错误') || reason.contains('篡改') || reason.contains('损坏')) {
    return l10n?.vaultErrWrongPin ?? 'PIN 错误或密钥载荷被篡改';
  }
  if (reason.contains('U 盘') || reason.contains('USB')) {
    return l10n?.vaultErrFileCrypto ?? '加密文件无法读取';
  }
  return l10n?.vaultErrUnlockFail ?? '保险库解锁失败';
}

String _mapFileReason(String reason, AppLocalizations? l10n) {
  if (reason.contains('独立密码') || reason.contains('decryptWithPassword')) {
    return l10n?.vaultErrFilePassword ?? '文件受独立密码保护';
  }
  if (reason.contains('DNV') || reason.contains('信封')) {
    return l10n?.vaultErrNotEnvelope ?? '不是有效的加密信封';
  }
  if (reason.contains('不匹配') || reason.contains('篡改')) {
    return l10n?.vaultErrKeyMismatch ?? '密钥不匹配或密文被篡改';
  }
  if (reason.contains('版本')) {
    return l10n?.vaultErrUnsupportedVersion ?? '不支持的加密信封版本';
  }
  return l10n?.vaultErrFileCrypto ?? '加密文件无法读取';
}
