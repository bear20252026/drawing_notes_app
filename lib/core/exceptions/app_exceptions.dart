/// 统一异常体系（P2 #33 + P2 #34）
///
/// 所有自定义异常继承 [AppException]，提供统一的错误码和用户友好消息。
library;

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
    super.code = 'NETWORK_ERROR',
    super.message = '网络连接失败，请检查网络设置',
    super.cause,
    super.stackTrace,
  });

  const NetworkException.timeout({
    super.message = '网络请求超时，请稍后重试',
    super.cause,
    super.stackTrace,
  }) : super(code: 'NETWORK_TIMEOUT');

  const NetworkException.noConnection({
    super.message = '无网络连接，请检查网络设置',
    super.cause,
    super.stackTrace,
  }) : super(code: 'NETWORK_NO_CONNECTION');

  const NetworkException.serverError({
    int? statusCode,
    super.message = '服务器错误，请稍后重试',
    super.cause,
    super.stackTrace,
  }) : super(
          code: 'NETWORK_SERVER_ERROR_${statusCode ?? 500}',
        );
}

// ============================================================================
// 存储异常
// ============================================================================

class StorageException extends AppException {
  const StorageException({
    super.code = 'STORAGE_ERROR',
    super.message = '存储操作失败',
    super.cause,
    super.stackTrace,
  });

  const StorageException.notFound({
    String? path,
    super.message = '文件未找到',
    super.cause,
    super.stackTrace,
  }) : super(code: 'STORAGE_NOT_FOUND');

  const StorageException.writeFailed({
    String? path,
    super.message = '文件写入失败',
    super.cause,
    super.stackTrace,
  }) : super(code: 'STORAGE_WRITE_FAILED');

  const StorageException.readFailed({
    String? path,
    super.message = '文件读取失败',
    super.cause,
    super.stackTrace,
  }) : super(code: 'STORAGE_READ_FAILED');

  const StorageException.permissionDenied({
    String? path,
    super.message = '存储权限不足',
    super.cause,
    super.stackTrace,
  }) : super(code: 'STORAGE_PERMISSION_DENIED');

  const StorageException.insufficientSpace({
    super.message = '存储空间不足',
    super.cause,
    super.stackTrace,
  }) : super(code: 'STORAGE_INSUFFICIENT_SPACE');
}

// ============================================================================
// 加密异常
// ============================================================================

class CryptoException extends AppException {
  const CryptoException({
    super.code = 'CRYPTO_ERROR',
    super.message = '加密操作失败',
    super.cause,
    super.stackTrace,
  });

  const CryptoException.invalidKey({
    super.message = '密钥无效或已损坏',
    super.cause,
    super.stackTrace,
  }) : super(code: 'CRYPTO_INVALID_KEY');

  const CryptoException.wrongPassword({
    super.message = '密码错误',
    super.cause,
    super.stackTrace,
  }) : super(code: 'CRYPTO_WRONG_PASSWORD');

  const CryptoException.dataCorrupted({
    super.message = '数据已损坏，无法解密',
    super.cause,
    super.stackTrace,
  }) : super(code: 'CRYPTO_DATA_CORRUPTED');

  const CryptoException.decryptionFailed({
    super.message = '解密失败',
    super.cause,
    super.stackTrace,
  }) : super(code: 'CRYPTO_DECRYPTION_FAILED');

  const CryptoException.encryptionFailed({
    super.message = '加密失败',
    super.cause,
    super.stackTrace,
  }) : super(code: 'CRYPTO_ENCRYPTION_FAILED');
}

// ============================================================================
// UI 异常
// ============================================================================

class UIException extends AppException {
  const UIException({
    super.code = 'UI_ERROR',
    super.message = '界面操作失败',
    super.cause,
    super.stackTrace,
  });

  const UIException.renderFailed({
    super.message = '渲染失败',
    super.cause,
    super.stackTrace,
  }) : super(code: 'UI_RENDER_FAILED');

  UIException.exportFailed({
    String format = '',
    super.message = '导出失败',
    super.cause,
    super.stackTrace,
  }) : super(
          code: 'UI_EXPORT_FAILED${format.isNotEmpty ? '_${format.toUpperCase()}' : ''}',
        );

  UIException.importFailed({
    String format = '',
    super.message = '导入失败',
    super.cause,
    super.stackTrace,
  }) : super(
          code: 'UI_IMPORT_FAILED${format.isNotEmpty ? '_${format.toUpperCase()}' : ''}',
        );

  const UIException.imageInsertFailed({
    super.message = '图片插入失败',
    super.cause,
    super.stackTrace,
  }) : super(code: 'UI_IMAGE_INSERT_FAILED');
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
