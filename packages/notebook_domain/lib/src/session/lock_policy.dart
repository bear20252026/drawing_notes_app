// notebook_domain——LockPolicy（批次 D——2026-08-18）。
//
// 锁定策略——定义自动锁定超时、手动锁定规则等。
// 纯 Dart——禁 Widget/BuildContext/Platform/File（R-02）。
library;

/// LockPolicy（锁定策略）。
///
/// 遵循专家方案：
/// - 自动锁定超时（失去焦点/后台/超时）
/// - 手动锁定（用户主动）
/// - 文件选择器豁免期间不自动锁定（防导入/导出误锁——SessionGuard 模式）
class LockPolicy {
  const LockPolicy({
    this.autoLockDuration = const Duration(minutes: 5),
    this.allowManualLock = true,
  });

  /// 自动锁定超时时间（默认 5 分钟）。
  final Duration autoLockDuration;

  /// 是否允许手动锁定。
  final bool allowManualLock;

  /// 检查是否过期（相对于解锁时间）。
  /// 使用毫秒比较避免 Duration 比较问题。
  bool isExpired(DateTime unlockedAt) {
    final elapsed = DateTime.now().millisecondsSinceEpoch - unlockedAt.millisecondsSinceEpoch;
    return elapsed > autoLockDuration.inMilliseconds;
  }

  /// 创建短超时策略（测试/安全场景——1 分钟）。
  static const LockPolicy shortTimeout = LockPolicy(
    autoLockDuration: Duration(minutes: 1),
  );

  /// 创建长超时策略（日常使用——30 分钟）。
  static const LockPolicy longTimeout = LockPolicy(
    autoLockDuration: Duration(minutes: 30),
  );
}
