/// 认证服务抽象接口 — 统一认证操作的契约。
///
/// 定义认证相关的核心操作，由 features/auth/ 或 features/security/ 实现。
///
/// 实现类：
/// - AuthGuard（路由级认证状态管理）
/// - SessionGuard（生命周期级会话管理）
library;

/// 认证状态。
enum AuthState {
  /// 未设置密码盘（首次使用）。
  uninitialized,

  /// 已设置密码盘，需要解锁。
  locked,

  /// 已认证（已解锁）。
  authenticated,

  /// 用户选择跳过加密。
  skipped,
}

/// 认证服务抽象接口。
///
/// 统一管理认证状态，提供认证操作的统一入口。
abstract class AuthService {
  /// 当前认证状态。
  AuthState get state;

  /// 是否需要认证（有密码盘且未跳过）。
  bool get requiresAuth;

  /// 当前会话是否已认证。
  bool get isAuthenticated;

  /// 认证状态变更事件流。
  Stream<AuthState> get onStateChange;

  /// 初始化认证服务。
  Future<void> initialize();

  /// 认证（密码盘验证通过）。
  void authenticate();

  /// 锁定会话。
  void deauthenticate();

  /// 跳过加密（用户选择不设置密码盘）。
  Future<void> skipEncryption();

  /// 恢复加密要求（用户从设置中重新启用加密）。
  Future<void> enableEncryption();
}
