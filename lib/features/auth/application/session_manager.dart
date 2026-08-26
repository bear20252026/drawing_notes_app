import '../domain/entities/auth_session.dart';
import '../domain/repositories/auth_repository.dart';

/// 会话管理器 — Application 层。
///
/// 管理认证会话的生命周期。
class SessionManager {
  final AuthRepository _repository;

  const SessionManager(this._repository);

  /// 当前会话
  AuthSession get session => _repository.session;

  /// 是否已认证
  bool get isAuthenticated => _repository.session.isAuthenticated;

  /// 是否已锁定
  bool get isLocked => _repository.session.isLocked;

  /// 剩余锁定秒数
  int? get remainingLockSeconds {
    final s = _repository.session;
    if (s is LockedSession) return s.remainingSeconds;
    return null;
  }

  /// 应用进入后台时调用：重置会话
  void onAppPaused() {
    _repository.resetSession();
  }

  /// 应用回到前台时调用
  void onAppResumed() {
    // 可以在这里添加额外的恢复逻辑
  }
}
