/// 会话守卫（专家审计最优先③——SessionGuard + PolicyEngine + Capability，
/// 2026-08-16 落地）。
///
/// 自动锁定/再认证（Flutter 官方 AppLifecycleListener + private_notes_light
/// SessionLifecycleObserver 权威模式）：onInactive（失去焦点——切后台/锁屏）
/// 立即锁定（清除媒体密钥）；文件选择器运行期间豁免（防导入/导出误锁——
/// private_notes_light filePickerRunning 模式）；onResume 若已锁定则触发
/// 再认证回调（导航回解锁页）。安全检查集中单一服务（Flutter 安全指南
/// "Centralize your checks"）。
///
/// 实现 [SessionService] 接口，统一会话管理操作契约。
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import 'interfaces/auth_service.dart';
import 'interfaces/session_service.dart';

/// 会话守卫 — 应用生命周期级别的会话管理。
///
/// 实现 [SessionService] 接口，负责：
/// - 监听应用前后台切换
/// - 根据策略自动锁定
/// - 会话超时管理
class SessionGuard implements SessionService {
  SessionGuard({
    this.onLock,
    this.onReauthenticateRequired,
    AuthService? authService,
  }) : _authService = authService {
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

  /// 认证服务引用（可选，用于联动锁定）。
  final AuthService? _authService;

  late final AppLifecycleListener _listener;
  final _sessionController = StreamController<SessionEvent>.broadcast();

  bool _locked = false;
  bool _filePickerActive = false;
  int? _lastActiveAt;

  // ─── SessionService 接口实现 ──────────────────────────────

  @override
  AuthService get authService =>
      _authService ?? _DefaultAuthServicePlaceholder();

  @override
  bool get isActive => !_locked;

  @override
  int? get lastActiveAt => _lastActiveAt;

  @override
  Stream<SessionEvent> get onSessionEvent => _sessionController.stream;

  @override
  void initialize() {
    _lastActiveAt = DateTime.now().millisecondsSinceEpoch;
  }

  @override
  void dispose() {
    _listener.dispose();
    _sessionController.close();
  }

  @override
  void markActive() {
    _lastActiveAt = DateTime.now().millisecondsSinceEpoch;
  }

  @override
  void handleAppLifecycleState(String state) {
    switch (state) {
      case 'inactive':
      case 'paused':
        onInactive();
      case 'resumed':
        onResume();
      case 'detached':
        _sessionController.add(SessionEvent.terminated);
    }
  }

  // ─── 原有功能（保持不变） ──────────────────────────────────

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
    _sessionController.add(SessionEvent.paused);
    onLock?.call();
  }

  /// onResume：回到前台——已锁定则触发再认证（环境可能已变化——不盲目
  /// 信任之前状态——Flutter 安全指南）。
  void onResume() {
    _sessionController.add(SessionEvent.resumed);
    if (_locked) onReauthenticateRequired?.call();
  }

  /// 解锁成功（重新认证后——重置锁定状态）。
  void unlock() => _locked = false;
}

/// 默认认证服务占位（当未提供 AuthService 时使用）。
class _DefaultAuthServicePlaceholder implements AuthService {
  @override
  AuthState get state => AuthState.uninitialized;
  @override
  bool get isAuthenticated => false;
  @override
  bool get requiresAuth => false;
  @override
  Stream<AuthState> get onStateChange => const Stream.empty();
  @override
  Future<void> initialize() async {}
  @override
  void authenticate() {}
  @override
  void deauthenticate() {}
  @override
  Future<void> skipEncryption() async {}
  @override
  Future<void> enableEncryption() async {}
}
