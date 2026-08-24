// editor_core——EncryptionVault 加密保险库（Cryptomator 借鉴——2026-08-21）。
//
// Cryptomator Vault 架构本地化——简化加密 UI 状态机。
// 纯 Dart 不可变模型——可独立测试——不搞崩。
//
// Cryptomator 原版参考：
// - Vault（保险库）概念：一个加密容器 = 一个笔记本
// - 状态：Locked → Unlocked → AutoLock
// - 简洁 UI：锁图标 + 密码输入 + 自动锁定
// - 安全设计：内存清零 + 自动锁定 + 生物识别
library;

/// 加密保险库状态（Cryptomator Vault 借鉴——简化状态机）。
enum VaultState {
  /// 未初始化（首次使用——需设置密码）。
  uninitialized,

  /// 已锁定（需要密码解锁）。
  locked,

  /// 已解锁（可读写加密数据）。
  unlocked,

  /// 自动锁定（超时/失去焦点后自动锁定）。
  autoLocked,

  /// 迁移中（V1 → V2 格式转换）。
  migrating,

  /// 错误（密码错误/密钥损坏）。
  error,
}

/// 保险库配置（Cryptomator Vault Config 借鉴——不可变）。
class VaultConfig {
  const VaultConfig({
    this.id = '',
    this.name = '',
    this.autoLockDuration = const Duration(minutes: 5),
    this.requireBiometric = false,
    this.pbkdf2Iterations = 600000,
    this.version = 3,
  });

  final String id;
  final String name;
  final Duration autoLockDuration;
  final bool requireBiometric;
  final int pbkdf2Iterations;
  final int version;

  VaultConfig copyWith({
    String? name,
    Duration? autoLockDuration,
    bool? requireBiometric,
  }) {
    return VaultConfig(
      id: id,
      name: name ?? this.name,
      autoLockDuration: autoLockDuration ?? this.autoLockDuration,
      requireBiometric: requireBiometric ?? this.requireBiometric,
      pbkdf2Iterations: pbkdf2Iterations,
      version: version,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is VaultConfig && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// 加密操作结果（Cryptomator Operation Result 借鉴——不可变）。
enum VaultOperation {
  /// 设置密码（首次）。
  setPassword,

  /// 解锁（输入密码）。
  unlock,

  /// 锁定（手动/自动）。
  lock,

  /// 修改密码。
  changePassword,

  /// 导出密钥备份。
  exportKeyBackup,
}

/// 加密操作结果（不可变）。
class VaultResult {
  const VaultResult({
    required this.success,
    this.message = '',
    this.state = VaultState.locked,
    this.errorCode = '',
  });

  final bool success;
  final String message;
  final VaultState state;
  final String errorCode;

  static const VaultResult locked = VaultResult(
    success: true,
    message: 'Vault locked',
    state: VaultState.locked,
  );

  static const VaultResult unlocked = VaultResult(
    success: true,
    message: 'Vault unlocked',
    state: VaultState.unlocked,
  );

  static VaultResult error(String message, [String code = '']) => VaultResult(
    success: false,
    message: message,
    state: VaultState.error,
    errorCode: code,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is VaultResult && success == other.success && message == other.message;

  @override
  int get hashCode => Object.hash(success, message);
}

/// 加密保险库管理器（Cryptomator Vault Manager 本地化——积木式纯 Dart）。
///
/// 简化加密 UI 状态机——用户只需：
/// 1. 首次：设置密码 → 自动加密
/// 2. 日常：打开笔记本 → 输入密码 → 使用 → 自动锁定
/// 3. 安全：修改密码 / 导出密钥备份 / 自动锁定
class EncryptionVaultManager {
  EncryptionVaultManager({
    this.config = const VaultConfig(),
    this.state = VaultState.uninitialized,
  });

  VaultConfig config;
  VaultState state;
  DateTime? _lastActivity;

  /// 当前状态。
  VaultState get currentState => state;

  /// 是否已解锁。
  bool get isUnlocked => state == VaultState.unlocked;

  /// 是否已锁定。
  bool get isLocked => state == VaultState.locked || state == VaultState.autoLocked;

  /// 是否需要设置密码（首次使用）。
  bool get needsSetup => state == VaultState.uninitialized;

  /// 检查自动锁定（调用方定期调用）。
  bool checkAutoLock() {
    if (state != VaultState.unlocked) return false;
    if (_lastActivity == null) return false;
    if (DateTime.now().difference(_lastActivity!) > config.autoLockDuration) {
      state = VaultState.autoLocked;
      return true;
    }
    return false;
  }

  /// 设置密码（首次使用——uninitialized → unlocked）。
  VaultResult setPassword(String password) {
    if (state != VaultState.uninitialized) {
      return VaultResult.error('Vault already initialized', 'ALREADY_INIT');
    }
    if (password.length < 8) {
      return VaultResult.error('Password too short (min 8 chars)', 'WEAK_PASSWORD');
    }
    // 实际加密逻辑由 infrastructure 层处理。
    state = VaultState.unlocked;
    _lastActivity = DateTime.now();
    return VaultResult.unlocked;
  }

  /// 解锁（locked → unlocked）。
  VaultResult unlock(String password) {
    if (state != VaultState.locked && state != VaultState.autoLocked) {
      return VaultResult.error('Vault not locked', 'NOT_LOCKED');
    }
    // 实际密码验证由 infrastructure 层处理。
    state = VaultState.unlocked;
    _lastActivity = DateTime.now();
    return VaultResult.unlocked;
  }

  /// 锁定（unlocked → locked）。
  VaultResult lock() {
    if (state != VaultState.unlocked) {
      return VaultResult.error('Vault not unlocked', 'NOT_UNLOCKED');
    }
    state = VaultState.locked;
    _lastActivity = null;
    return VaultResult.locked;
  }

  /// 记录活动（防止自动锁定）。
  void recordActivity() {
    _lastActivity = DateTime.now();
  }

  /// 修改密码（unlocked 状态下）。
  VaultResult changePassword(String oldPassword, String newPassword) {
    if (state != VaultState.unlocked) {
      return VaultResult.error('Vault must be unlocked', 'NOT_UNLOCKED');
    }
    if (newPassword.length < 8) {
      return VaultResult.error('New password too weak', 'WEAK_PASSWORD');
    }
    // 实际密码修改由 infrastructure 层处理。
    return const VaultResult(success: true, message: 'Password changed');
  }
}
