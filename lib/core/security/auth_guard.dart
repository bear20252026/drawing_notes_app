/// 认证守卫（P2 #34 路由守卫核心）
///
/// 管理全局会话认证状态：
/// - 密码盘是否已设置
/// - 当前会话是否已认证
/// - 解锁/锁定状态变更通知
///
/// 实现 [AuthService] 接口，统一认证操作契约。
///
/// 注意：此文件与 [SessionGuard]（生命周期观察者）互补。
/// [AuthGuard] 管理路由级别的认证状态；
/// [SessionGuard] 管理 App 生命周期级别的锁定/解锁。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_lock_service.dart';
import 'interfaces/auth_service.dart';

/// 认证守卫
///
/// 全局单例，管理密码盘认证状态。
/// 在 GoRouter redirect 中检查，未认证则重定向到密码盘页。
///
/// 支持三种模式：
/// 1. 未设置密码盘 → 直接通过（首次使用）
/// 2. 已设置密码盘 → 需要解锁才能使用
/// 3. 用户选择跳过加密 → 永久跳过，不再询问
class AuthGuard extends ChangeNotifier implements AuthService {
  AuthGuard._();

  static final AuthGuard _instance = AuthGuard._();

  /// 获取单例
  static AuthGuard get instance => _instance;

  /// SharedPreferences key for encryption skipped flag
  static const _kEncryptionSkipped = 'auth_encryption_skipped';

  bool _authenticated = false;
  bool _passwordDiskExists = false;
  bool _encryptionSkipped = false;

  /// 认证状态变更事件流（AuthService 接口）。
  final _authStateController = StreamController<AuthState>.broadcast();

  // ─── AuthService 接口实现 ──────────────────────────────────

  @override
  AuthState get state {
    if (_encryptionSkipped) return AuthState.skipped;
    if (!_passwordDiskExists) return AuthState.uninitialized;
    if (_authenticated) return AuthState.authenticated;
    return AuthState.locked;
  }

  @override
  bool get isAuthenticated => _authenticated;

  @override
  bool get passwordDiskExists => _passwordDiskExists;

  @override
  bool get encryptionSkipped => _encryptionSkipped;

  @override
  bool get requiresAuth => _passwordDiskExists && !_encryptionSkipped;

  @override
  Stream<AuthState> get onStateChange => _authStateController.stream;

  @override
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _encryptionSkipped = prefs.getBool(_kEncryptionSkipped) ?? false;
    _passwordDiskExists = await _checkPasswordDiskExists();

    // 初始化应用锁服务
    await AppLockService.instance.initialize();

    // 监听应用锁状态变化，触发路由重新评估
    AppLockService.instance.addListener(_onAppLockChanged);

    if (_encryptionSkipped) {
      _authenticated = true;
    } else if (!_passwordDiskExists) {
      _authenticated = true;
    }

    _authStateController.add(state);
    notifyListeners();
  }

  @override
  void authenticate() {
    _authenticated = true;
    _authController.add(true);
    _authStateController.add(AuthState.authenticated);
    notifyListeners();
  }

  @override
  void deauthenticate() {
    _authenticated = false;
    _authController.add(false);
    _authStateController.add(AuthState.locked);
    notifyListeners();
  }

  @override
  Future<void> skipEncryption() async {
    _encryptionSkipped = true;
    _authenticated = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEncryptionSkipped, true);
    _authController.add(true);
    _authStateController.add(AuthState.skipped);
    notifyListeners();
  }

  @override
  Future<void> enableEncryption() async {
    _encryptionSkipped = false;
    _authenticated = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kEncryptionSkipped);
    _authController.add(false);
    _authStateController.add(AuthState.locked);
    notifyListeners();
  }

  // ─── 应用锁集成 ──────────────────────────────────────────

  /// 是否需要应用锁验证（应用锁已启用且当前会话未验证）。
  bool get requiresAppLock => AppLockService.instance.requiresAuth;

  /// 应用锁是否已启用。
  bool get appLockEnabled => AppLockService.instance.enabled;

  /// 是否需要任何形式的认证（密码盘或应用锁）。
  bool get requiresAnyAuth => requiresAuth || requiresAppLock;

  /// 认证状态变更事件流（向后兼容）。
  final _authController = StreamController<bool>.broadcast();
  Stream<bool> get onAuthChange => _authController.stream;

  /// 应用锁状态变更回调 — 通知路由重新评估 redirect。
  void _onAppLockChanged() {
    _authStateController.add(state);
    notifyListeners();
  }

  /// 检查密码盘文件是否存在。
  Future<bool> _checkPasswordDiskExists() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final passwordFile = File(
        '${appDir.path}${Platform.pathSeparator}password_disk.json',
      );
      return passwordFile.existsSync();
    } catch (e) {
      debugPrint('[AuthGuard] 检查密码盘文件失败: $e');
      return false;
    }
  }

  @override
  void dispose() {
    AppLockService.instance.removeListener(_onAppLockChanged);
    _authController.close();
    _authStateController.close();
    super.dispose();
  }
}
