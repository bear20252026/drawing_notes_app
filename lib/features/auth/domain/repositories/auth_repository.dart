import '../entities/auth_credentials.dart';
import '../entities/auth_session.dart';
import '../value_objects/auth_result.dart';

/// 认证仓库接口 — 零依赖。
///
/// 定义认证操作的抽象接口，由 infrastructure 层实现。
abstract class AuthRepository {
  /// 当前认证会话
  AuthSession get session;

  /// 是否已配置认证（已设置密码/PIN）
  bool get isConfigured;

  /// 设置初始密码/PIN
  Future<AuthResult> setCredentials(AuthCredentials credentials);

  /// 验证凭证
  Future<AuthResult> verifyCredentials(AuthCredentials credentials);

  /// 修改密码/PIN（需验证旧凭证）
  Future<AuthResult> changeCredentials({
    required AuthCredentials oldCredentials,
    required AuthCredentials newCredentials,
  });

  /// 移除认证（需验证当前凭证）
  Future<AuthResult> removeCredentials(AuthCredentials credentials);

  /// 重置会话（应用回到前台等场景）
  void resetSession();

  /// 标记生物识别验证通过
  void markBiometricAuthenticated();
}
