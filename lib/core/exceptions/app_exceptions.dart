/// 统一异常体系（P2 #33 + P2 #34）
///
/// 所有自定义异常继承 [AppException]，提供统一的错误码和用户友好消息。

import 'package:flutter/foundation.dart';

/// 应用异常基类
@immutable
abstract class AppException implements Exception {
  const AppException({
    required this.code,
    required this.message,
    this.cause,
    this.stackTrace,
  });

  final String code;
  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() => '$runtimeType($code): $message'
      '${cause != null ? '\nCaused by: $cause' : ''}';

  String toLocalizedMessage() => message;
}

// ============================================================================
// 网络异常
// ============================================================================

class NetworkException extends AppException {
  const NetworkException({
    String code = 'NETWORK_ERROR',
    String message = '网络连接失败，请检查网络设置',
    super.cause,
    super.stackTrace,
  }) : super(code: code, message: message);

  const NetworkException.timeout({
    String message = '网络请求超时，请稍后重试',
    super.cause,
    super.stackTrace,
  }) : super(code: 'NETWORK_TIMEOUT', message: message);

  const NetworkException.noConnection({
    String message = '无网络连接，请检查网络设置',
    super.cause,
    super.stackTrace,
  }) : super(code: 'NETWORK_NO_CONNECTION', message: message);

  const NetworkException.serverError({
    int? statusCode,
    String message = '服务器错误，请稍后重试',
    super.cause,
    super.stackTrace,
  }) : super(
          code: 'NETWORK_SERVER_ERROR_${statusCode ?? 500}',
          message: message,
        );
}

// ============================================================================
// 存储异常
// ============================================================================

class StorageException extends AppException {
  const StorageException({
    String code = 'STORAGE_ERROR',
    String message = '存储操作失败',
    super.cause,
    super.stackTrace,
  }) : super(code: code, message: message);

  const StorageException.notFound({
    String? path,
    String message = '文件未找到',
    super.cause,
    super.stackTrace,
  }) : super(code: 'STORAGE_NOT_FOUND', message: message);

  const StorageException.writeFailed({
    String? path,
    String message = '文件写入失败',
    super.cause,
    super.stackTrace,
  }) : super(code: 'STORAGE_WRITE_FAILED', message: message);

  const StorageException.readFailed({
    String? path,
    String message = '文件读取失败',
    super.cause,
    super.stackTrace,
  }) : super(code: 'STORAGE_READ_FAILED', message: message);

  const StorageException.permissionDenied({
    String? path,
    String message = '存储权限不足',
    super.cause,
    super.stackTrace,
  }) : super(code: 'STORAGE_PERMISSION_DENIED', message: message);

  const StorageException.insufficientSpace({
    String message = '存储空间不足',
    super.cause,
    super.stackTrace,
  }) : super(code: 'STORAGE_INSUFFICIENT_SPACE', message: message);
}

// ============================================================================
// 加密异常
// ============================================================================

class CryptoException extends AppException {
  const CryptoException({
    String code = 'CRYPTO_ERROR',
    String message = '加密操作失败',
    super.cause,
    super.stackTrace,
  }) : super(code: code, message: message);

  const CryptoException.invalidKey({
    String message = '密钥无效或已损坏',
    super.cause,
    super.stackTrace,
  }) : super(code: 'CRYPTO_INVALID_KEY', message: message);

  const CryptoException.wrongPassword({
    String message = '密码错误',
    super.cause,
    super.stackTrace,
  }) : super(code: 'CRYPTO_WRONG_PASSWORD', message: message);

  const CryptoException.dataCorrupted({
    String message = '数据已损坏，无法解密',
    super.cause,
    super.stackTrace,
  }) : super(code: 'CRYPTO_DATA_CORRUPTED', message: message);

  const CryptoException.decryptionFailed({
    String message = '解密失败',
    super.cause,
    super.stackTrace,
  }) : super(code: 'CRYPTO_DECRYPTION_FAILED', message: message);

  const CryptoException.encryptionFailed({
    String message = '加密失败',
    super.cause,
    super.stackTrace,
  }) : super(code: 'CRYPTO_ENCRYPTION_FAILED', message: message);
}

// ============================================================================
// UI 异常
// ============================================================================

class UIException extends AppException {
  const UIException({
    String code = 'UI_ERROR',
    String message = '界面操作失败',
    super.cause,
    super.stackTrace,
  }) : super(code: code, message: message);

  const UIException.renderFailed({
    String message = '渲染失败',
    super.cause,
    super.stackTrace,
  }) : super(code: 'UI_RENDER_FAILED', message: message);

  UIException.exportFailed({
    String format = '',
    String message = '导出失败',
    super.cause,
    super.stackTrace,
  }) : super(
          code: 'UI_EXPORT_FAILED${format.isNotEmpty ? '_${format.toUpperCase()}' : ''}',
          message: message,
        );

  UIException.importFailed({
    String format = '',
    String message = '导入失败',
    super.cause,
    super.stackTrace,
  }) : super(
          code: 'UI_IMPORT_FAILED${format.isNotEmpty ? '_${format.toUpperCase()}' : ''}',
          message: message,
        );

  const UIException.imageInsertFailed({
    String message = '图片插入失败',
    super.cause,
    super.stackTrace,
  }) : super(code: 'UI_IMAGE_INSERT_FAILED', message: message);
}

// ============================================================================
// 异常工具
// ============================================================================

class ExceptionUtils {
  ExceptionUtils._();

  /// 将任意异常包装为 [AppException]
  static AppException wrap(Object error, [StackTrace? stackTrace]) {
    if (error is AppException) return error;
    final errorStr = error.toString().toLowerCase();

    if (errorStr.contains('socket') ||
        errorStr.contains('network') ||
        errorStr.contains('connection')) {
      return NetworkException(cause: error, stackTrace: stackTrace);
    }

    if (errorStr.contains('file') ||
        errorStr.contains('path') ||
        errorStr.contains('directory')) {
      return StorageException(cause: error, stackTrace: stackTrace);
    }

    if (errorStr.contains('encrypt') ||
        errorStr.contains('decrypt') ||
        errorStr.contains('cipher')) {
      return CryptoException(cause: error, stackTrace: stackTrace);
    }

    return UIException(
      code: 'UNKNOWN_ERROR',
      message: error.toString(),
      cause: error,
      stackTrace: stackTrace,
    );
  }

  static String getUserMessage(Object error) {
    if (error is AppException) return error.message;
    return '发生未知错误';
  }

  static String getErrorCode(Object error) {
    if (error is AppException) return error.code;
    return 'UNKNOWN';
  }
}
