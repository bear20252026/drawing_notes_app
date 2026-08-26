/// 生物识别服务抽象接口 — 统一生物识别认证操作。
///
/// 职责：
/// - 检查设备是否支持生物识别
/// - 执行生物识别认证
/// - 管理生物识别启用状态
library;

/// 生物识别类型。
enum BiometricType {
  /// 指纹识别。
  fingerprint,

  /// 面部识别。
  face,

  /// 虹膜识别。
  iris,

  /// 未知类型。
  unknown,
}

/// 生物识别认证结果。
enum BiometricResult {
  /// 认证成功。
  success,

  /// 用户取消。
  cancelled,

  /// 认证失败（不匹配）。
  failed,

  /// 设备不支持。
  notAvailable,

  /// 未注册生物识别。
  notEnrolled,

  /// 其他错误。
  error,
}

/// 生物识别服务抽象接口。
abstract class BiometricService {
  /// 设备是否支持生物识别。
  Future<bool> isAvailable();

  /// 获取可用的生物识别类型列表。
  Future<List<BiometricType>> getAvailableTypes();

  /// 执行生物识别认证。
  ///
  /// [reason] — 显示给用户的认证原因。
  Future<BiometricResult> authenticate({required String reason});

  /// 生物识别是否已启用（用户设置）。
  Future<bool> isEnabled();

  /// 启用/禁用生物识别。
  Future<void> setEnabled(bool enabled);
}
