import 'package:flutter/widgets.dart';

/// 会话守卫（专家审计最优先③——SessionGuard + PolicyEngine + Capability，
/// 2026-08-16 落地）。
///
/// 自动锁定/再认证（Flutter 官方 AppLifecycleListener + private_notes_light
/// SessionLifecycleObserver 权威模式）：onInactive（失去焦点——切后台/锁屏）
/// 立即锁定（清除媒体密钥）；文件选择器运行期间豁免（防导入/导出误锁——
/// private_notes_light filePickerRunning 模式）；onResume 若已锁定则触发
/// 再认证回调（导航回解锁页）。安全检查集中单一服务（Flutter 安全指南
/// "Centralize your checks"）。
class SessionGuard {
  SessionGuard({this.onLock, this.onReauthenticateRequired}) {
    _listener = AppLifecycleListener(
      onInactive: onInactive,
      onResume: onResume,
    );
  }

  /// 锁定回调（调用方清除媒体密钥——MediaCryptoService.clearSessionKey——
  /// 并标记 UI 锁定状态）。
  final VoidCallback? onLock;

  /// 再认证回调（onResume 时已锁定——导航回解锁/密码输入页）。
  final VoidCallback? onReauthenticateRequired;

  late final AppLifecycleListener _listener;

  bool _locked = false;

  /// P0 安全修复（审计 N-H7）：豁免由裸 bool 改为计数 + TTL。
  /// - 计数：嵌套选择器可配对开关，不会因一次 false 提前关闭他人豁免；
  /// - TTL（5 分钟）：`setFilePickerActive(true)` 后若调用方崩溃/抛异常
  ///   忘记复位，豁免自动过期，不会永久关闭后台锁定。
  int _exemptions = 0;
  DateTime? _exemptionUntil;
  static const _exemptionTtl = Duration(minutes: 5);

  bool get isLocked => _locked;

  bool get _exempted {
    if (_exemptions <= 0) return false;
    final until = _exemptionUntil;
    if (until == null || DateTime.now().isAfter(until)) {
      _exemptions = 0;
      _exemptionUntil = null;
      return false;
    }
    return true;
  }

  /// 文件选择器状态（导入/导出期间 inactive 不触发锁定——防误锁）。
  /// 新代码优先用 [runWithExemption]（try/finally 自动配对）；本方法保留
  /// 做兼容，true 会刷新 5 分钟 TTL。
  void setFilePickerActive(bool active) {
    if (active) {
      _exemptions++;
      _exemptionUntil = DateTime.now().add(_exemptionTtl);
    } else if (_exemptions > 0) {
      _exemptions--;
      if (_exemptions == 0) _exemptionUntil = null;
    }
  }

  /// 作用域式豁免：[fn] 执行期间 inactive 不锁定，结束（或抛异常）自动
  /// 复位——调用方无需手写 try/finally，也不会因异常泄漏永久豁免。
  Future<T> runWithExemption<T>(Future<T> Function() fn) async {
    setFilePickerActive(true);
    try {
      return await fn();
    } finally {
      setFilePickerActive(false);
    }
  }

  /// onInactive：失去输入焦点（切后台/锁屏）——文件选择器运行中豁免——
  /// 否则立即锁定（密钥即刻清除——private_notes_light 模式）。
  void onInactive() {
    if (_exempted) return;
    _lock();
  }

  void _lock() {
    if (_locked) return;
    _locked = true;
    onLock?.call();
  }

  /// onResume：回到前台——已锁定则触发再认证（环境可能已变化——不盲目
  /// 信任之前状态——Flutter 安全指南）。
  void onResume() {
    if (_locked) onReauthenticateRequired?.call();
  }

  /// 解锁成功（重新认证后——重置锁定状态）。
  ///
  /// 约束（审计 N-H7）：仅允许在调用方自有再认证流程成功完成后调用
  /// （PIN/系统验证通过后）；禁止在 deep-link、通知、测试钩子等未认证
  /// 路径调用——本类不持有认证证明，证明责任在调用方。
  void unlock() => _locked = false;

  void dispose() => _listener.dispose();
}
