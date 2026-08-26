import '../domain/entities/auth_credentials.dart';
import '../domain/entities/auth_session.dart';
import '../domain/repositories/auth_repository.dart';
import '../domain/value_objects/auth_result.dart';

/// 认证服务 — Application 层。
///
/// 封装认证相关的业务用例，仅依赖 Domain 层。
class AuthService {
  final AuthRepository _repository;

  const AuthService(this._repository);

  /// 当前认证会话
  AuthSession get session => _repository.session;

  /// 是否已配置认证
  bool get isConfigured => _repository.isConfigured;

  /// 是否需要认证
  bool get requiresAuth => _repository.isConfigured && !_repository.session.isAuthenticated;

  /// 设置初始密码
  Future<AuthResult> setPassword(String password) {
    return _repository.setCredentials(PasswordCredentials(password));
  }

  /// 验证密码
  Future<AuthResult> verifyPassword(String password) {
    return _repository.verifyCredentials(PasswordCredentials(password));
  }

  /// 修改密码
  Future<AuthResult> changePassword({
    required String oldPassword,
    required String newPassword,
  }) {
    return _repository.changeCredentials(
      oldCredentials: PasswordCredentials(oldPassword),
      newCredentials: PasswordCredentials(newPassword),
    );
  }

  /// 移除密码
  Future<AuthResult> removePassword(String password) {
    return _repository.removeCredentials(PasswordCredentials(password));
  }

  /// 重置会话
  void resetSession() => _repository.resetSession();

  /// 生物识别验证通过
  void markBiometricAuthenticated() => _repository.markBiometricAuthenticated();
}
