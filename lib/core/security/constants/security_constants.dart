/// 安全常量 — 统一的安全相关配置值。
///
/// 集中管理所有安全相关的常量，避免散落在各文件中。
library;

/// 安全相关常量。
class SecurityConstants {
  SecurityConstants._();

  // ── 密钥派生 ──────────────────────────────────────────────

  /// Argon2id 默认内存参数（KB）。
  static const int argon2MemoryKb = 65536; // 64 MB

  /// Argon2id 默认迭代次数。
  static const int argon2Iterations = 3;

  /// Argon2id 默认并行度。
  static const int argon2Parallelism = 2;

  /// Argon2id 默认输出长度（字节）。
  static const int argon2HashLength = 32;

  /// 默认盐长度（字节）。
  static const int saltLength = 32;

  /// HKDF 默认输出长度（字节）。
  static const int hkdfOutputLength = 32;

  // ── 会话管理 ──────────────────────────────────────────────

  /// 默认会话超时时间（毫秒）— 5 分钟。
  static const int defaultSessionTimeoutMs = 5 * 60 * 1000;

  /// 后台自动锁定延迟（毫秒）— 立即锁定。
  static const int backgroundLockDelayMs = 0;

  /// 最大连续认证失败次数。
  static const int maxAuthFailures = 5;

  /// 认证失败锁定时间（毫秒）— 30 秒。
  static const int authFailureLockoutMs = 30 * 1000;

  // ── 审计日志 ──────────────────────────────────────────────

  /// 审计日志最大内存条目数。
  static const int auditLogMaxEntries = 1000;

  /// 审计日志分片最大条目数。
  static const int auditLogMaxEntriesPerShard = 1000;

  /// 审计日志分片文件前缀。
  static const String auditLogShardPrefix = 'audit.';

  /// 审计日志分片文件后缀。
  static const String auditLogShardSuffix = '.log.enc';

  /// 审计日志元数据文件名。
  static const String auditLogMetaFileName = 'audit.meta.json';

  // ── 存储键名 ──────────────────────────────────────────────

  /// flutter_secure_storage KEK 盐键名。
  static const String kekSaltKey = 'vault.kek.salt';

  /// flutter_secure_storage KEK 验证哈希键名。
  static const String kekHashKey = 'vault.kek.hash';

  /// flutter_secure_storage Vault 版本键名。
  static const String vaultVersionKey = 'vault.version';

  /// PM码 Slot B 存储键名。
  static const String pmCodeSlotBKey = 'pm_slot_b';

  /// PM码 Slot A 存储键名。
  static const String pmCodeSlotAKey = 'pm_slot_a';

  // ── 加密算法标识 ──────────────────────────────────────────

  /// AES-GCM 算法标识。
  static const String algorithmAesGcm = 'AES-256-GCM';

  /// ChaCha20-Poly1305 算法标识。
  static const String algorithmChaCha20 = 'ChaCha20-Poly1305';

  /// HKDF-SHA256 算法标识。
  static const String algorithmHkdfSha256 = 'HKDF-SHA256';

  /// Argon2id 算法标识。
  static const String algorithmArgon2id = 'Argon2id';

  // ── 版本号 ────────────────────────────────────────────────

  /// Vault 格式版本。
  static const int vaultVersion = 1;

  /// PM码 格式版本。
  static const int pmCodeVersion = 1;

  /// 加密服务格式版本。
  static const int encryptionFormatVersion = 5;
}
