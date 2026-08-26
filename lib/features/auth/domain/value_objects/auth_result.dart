/// 认证结果值对象 — 零依赖。
///
/// 封装认证操作的结果，避免使用异常控制流。
sealed class AuthResult {
  const AuthResult();

  bool get isSuccess => this is AuthSuccess;
  bool get isFailure => this is AuthFailure;
}

/// 认证成功
class AuthSuccess extends AuthResult {
  const AuthSuccess();
}

/// 认证失败
class AuthFailure extends AuthResult {
  final AuthFailureReason reason;
  final int? remainingAttempts;

  const AuthFailure({
    required this.reason,
    this.remainingAttempts,
  });
}

/// 认证失败原因
enum AuthFailureReason {
  /// 密码/PIN 错误
  invalidCredentials,

  /// 已锁定（连续失败次数过多）
  locked,

  /// 生物识别不可用
  biometricUnavailable,

  /// 生物识别失败
  biometricFailed,

  /// 未设置密码
  notConfigured,

  /// 已设置密码（无法重复设置）
  alreadyConfigured,

  /// 未知错误
  unknown,
}
