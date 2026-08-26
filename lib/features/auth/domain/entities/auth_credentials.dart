/// 认证凭证实体 — 零依赖。
///
/// 封装认证所需的凭证信息。
sealed class AuthCredentials {
  const AuthCredentials();
}

/// PIN 码凭证
class PinCredentials extends AuthCredentials {
  final String pin;

  const PinCredentials(this.pin);
}

/// 密码凭证
class PasswordCredentials extends AuthCredentials {
  final String password;

  const PasswordCredentials(this.password);
}

/// 生物识别凭证
class BiometricCredentials extends AuthCredentials {
  final String reason;

  const BiometricCredentials({required this.reason});
}
