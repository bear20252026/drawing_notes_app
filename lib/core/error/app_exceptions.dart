/// 统一异常层级。
///
/// 所有业务异常继承自 [AppException]，便于上层统一捕获、分类处理。
/// 每个子类代表一类错误场景，可携带额外的上下文信息。
library;

/// 应用异常基类。
///
/// 所有自定义异常的根类，提供统一的错误消息和可选的底层原因。
abstract class AppException implements Exception {
  const AppException(this.message, {this.cause, this.stackTrace});

  /// 用户友好的错误描述（可本地化）。
  final String message;

  /// 底层原始异常（如有）。
  final Object? cause;

  /// 堆栈跟踪（如有）。
  final StackTrace? stackTrace;

  /// 错误分类标识（用于日志和崩溃上报）。
  String get type => runtimeType.toString();

  /// 是否可恢复（用户可通过重试等操作恢复）。
  bool get isRecoverable => false;

  @override
  String toString() => '$type: $message';
}

// =============================================================================
// 网络异常
// =============================================================================

/// 网络相关异常。
class NetworkException extends AppException {
  const NetworkException(
    super.message, {
    super.cause,
    super.stackTrace,
    this.statusCode,
  });

  /// HTTP 状态码（如有）。
  final int? statusCode;

  @override
  bool get isRecoverable => true;
}

// =============================================================================
// 存储异常
// =============================================================================

/// 存储/文件操作异常。
class StorageException extends AppException {
  const StorageException(
    super.message, {
    super.cause,
    super.stackTrace,
    this.path,
  });

  /// 相关文件路径（如有）。
  final String? path;

  @override
  bool get isRecoverable => true;
}

/// 数据损坏异常。
class CorruptedDataException extends StorageException {
  const CorruptedDataException(
    super.message, {
    super.cause,
    super.stackTrace,
    super.path,
  });
}

// =============================================================================
// 加密异常
// =============================================================================

/// 加密/解密操作异常。
class CryptoException extends AppException {
  const CryptoException(
    super.message, {
    super.cause,
    super.stackTrace,
  });

  @override
  bool get isRecoverable => false;
}

/// 认证失败异常（密码错误、验签失败等）。
class AuthenticationException extends CryptoException {
  const AuthenticationException(
    super.message, {
    super.cause,
    super.stackTrace,
  });
}

// =============================================================================
// UI 异常
// =============================================================================

/// UI 渲染或交互异常。
class UIException extends AppException {
  const UIException(
    super.message, {
    super.cause,
    super.stackTrace,
  });
}

/// 导航异常（路由未找到、参数错误等）。
class NavigationException extends UIException {
  const NavigationException(
    super.message, {
    super.cause,
    super.stackTrace,
  });
}

// =============================================================================
// 验证异常
// =============================================================================

/// 输入验证异常。
class ValidationException extends AppException {
  const ValidationException(
    super.message, {
    super.cause,
    super.stackTrace,
    this.field,
  });

  /// 验证失败的字段名（如有）。
  final String? field;

  @override
  bool get isRecoverable => true;
}

// =============================================================================
// 平台异常
// =============================================================================

/// 平台特定异常（权限、API 不可用等）。
class PlatformException extends AppException {
  const PlatformException(
    super.message, {
    super.cause,
    super.stackTrace,
    this.platform,
  });

  /// 相关平台标识。
  final String? platform;

  @override
  bool get isRecoverable => false;
}
