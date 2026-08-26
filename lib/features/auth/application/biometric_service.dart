import '../domain/value_objects/auth_result.dart';

/// 生物识别服务接口 — Application 层。
///
/// 定义生物识别操作的抽象接口。
abstract class BiometricService {
  /// 生物识别是否可用
  Future<bool> isAvailable();

  /// 获取可用的生物识别类型
  Future<List<BiometricType>> getAvailableBiometrics();

  /// 执行生物识别认证
  Future<AuthResult> authenticate({required String reason});
}

/// 生物识别类型
enum BiometricType {
  fingerprint,
  face,
  iris,
}

/// 默认生物识别服务实现（不可用）。
///
/// 当平台不支持生物识别时使用。
class UnsupportedBiometricService implements BiometricService {
  const UnsupportedBiometricService();

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<List<BiometricType>> getAvailableBiometrics() async => [];

  @override
  Future<AuthResult> authenticate({required String reason}) async {
    return const AuthFailure(reason: AuthFailureReason.biometricUnavailable);
  }
}
