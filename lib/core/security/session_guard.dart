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
  bool _filePickerActive = false;

  bool get isLocked => _locked;

  /// 文件选择器状态（导入/导出期间 inactive 不触发锁定——防误锁）。
  void setFilePickerActive(bool active) => _filePickerActive = active;

  /// onInactive：失去输入焦点（切后台/锁屏）——文件选择器运行中豁免——
  /// 否则立即锁定（密钥即刻清除——private_notes_light 模式）。
  void onInactive() {
    if (_filePickerActive) return;
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
  void unlock() => _locked = false;

  void dispose() => _listener.dispose();
}
