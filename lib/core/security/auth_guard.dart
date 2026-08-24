/// 认证守卫（P2 #34 路由守卫核心）
///
/// 管理全局会话认证状态：
/// - 密码盘是否已设置
/// - 当前会话是否已认证
/// - 解锁/锁定状态变更通知
///
/// 注意：此文件与 [SessionGuard]（生命周期观察者）互补。
/// [AuthGuard] 管理路由级别的认证状态；
/// [SessionGuard] 管理 App 生命周期级别的锁定/解锁。

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 认证守卫
///
/// 全局单例，管理密码盘认证状态。
/// 在 GoRouter redirect 中检查，未认证则重定向到密码盘页。
class AuthGuard extends ChangeNotifier {
  AuthGuard._();

  static final AuthGuard _instance = AuthGuard._();

  /// 获取单例
  static AuthGuard get instance => _instance;

  bool _authenticated = false;
  bool _passwordDiskExists = false;

  /// 当前会话是否已认证（已解锁密码盘）
  bool get isAuthenticated => _authenticated;

  /// 密码盘是否已设置（存在密码盘文件）
  bool get passwordDiskExists => _passwordDiskExists;

  /// 认证状态变更事件流
  final _authController = StreamController<bool>.broadcast();
  Stream<bool> get onAuthChange => _authController.stream;

  /// 密码盘验证通过后调用
  void authenticate() {
    _authenticated = true;
    _authController.add(true);
    notifyListeners();
  }

  /// 锁定会话
  void deauthenticate() {
    _authenticated = false;
    _authController.add(false);
    notifyListeners();
  }

  /// 初始化：检查密码盘是否存在
  Future<void> initialize() async {
    _passwordDiskExists = await _checkPasswordDiskExists();
    // 如果密码盘不存在，直接通过（不需要认证）
    if (!_passwordDiskExists) {
      _authenticated = true;
    }
    notifyListeners();
  }

  /// 检查密码盘文件是否存在
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
    _authController.close();
    super.dispose();
  }
}
