import '../value_objects/auth_result.dart';

/// 认证会话实体 — 零依赖。
///
/// 表示当前认证状态。
sealed class AuthSession {
  const AuthSession();

  bool get isAuthenticated => this is AuthenticatedSession;
  bool get isLocked => this is LockedSession;
  bool get isUnauthenticated => this is UnauthenticatedSession;
}

/// 已认证会话
class AuthenticatedSession extends AuthSession {
  const AuthenticatedSession();
}

/// 锁定会话（连续失败次数过多）
class LockedSession extends AuthSession {
  /// 锁定到期时间（毫秒时间戳）
  final int? lockedUntilMs;

  const LockedSession({this.lockedUntilMs});

  /// 剩余锁定秒数
  int? get remainingSeconds {
    if (lockedUntilMs == null) return null;
    final remaining = lockedUntilMs! - DateTime.now().millisecondsSinceEpoch;
    return remaining > 0 ? remaining ~/ 1000 : 0;
  }
}

/// 未认证会话
class UnauthenticatedSession extends AuthSession {
  /// 已失败次数
  final int failedAttempts;

  const UnauthenticatedSession({this.failedAttempts = 0});
}
