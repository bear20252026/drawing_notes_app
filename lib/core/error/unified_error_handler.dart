import 'dart:async' as async;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'error_log_service.dart';

// ============================================================================
// 错误严重程度枚举
// ============================================================================

/// 错误严重程度级别
enum ErrorSeverity {
  /// 信息级别 - 一般提示
  INFO,

  /// 警告级别 - 可能影响功能
  WARNING,

  /// 错误级别 - 严重错误
  ERROR,
}

// ============================================================================
// 统一错误基类 AppException
// ============================================================================

/// 统一错误异常基类
///
/// 所有应用内异常都应继承此基类，提供统一的错误处理接口
class AppException implements Exception {
  /// 创建 AppException
  ///
  /// [message] 用户友好的错误消息（中文）
  /// [code] 错误代码，用于程序化处理
  /// [severity] 错误严重程度
  /// [originalError] 原始异常（如果有）
  /// [stack] 原始堆栈追踪
  /// [context] 错误发生的位置/上下文
  /// [metadata] 附加的元数据信息
  AppException({
    required this.message,
    required this.code,
    this.severity = ErrorSeverity.ERROR,
    this.originalError,
    this.stack,
    this.context,
    this.metadata,
  });

  /// 用户友好的错误消息（中文）
  final String message;

  /// 错误代码，例如 'AUTH_FAILED', 'NETWORK_ERROR'
  final String code;

  /// 错误严重程度
  final ErrorSeverity severity;

  /// 原始捕获的异常
  final Object? originalError;

  /// 原始堆栈追踪
  final StackTrace? stack;

  /// 错误发生的位置/上下文
  final String? context;

  /// 附加的元数据信息
  final Map<String, dynamic>? metadata;

  /// 获取格式化的错误信息
  String get formattedMessage {
    final buffer = StringBuffer();
    buffer.writeln('[$code] $message');
    if (context != null) {
      buffer.writeln('位置: $context');
    }
    if (originalError != null) {
      buffer.writeln('原始错误: $originalError');
    }
    return buffer.toString();
  }

  @override
  String toString() {
    return 'AppException($code): $message';
  }
}

// ============================================================================
// 特定异常子类
// ============================================================================

/// 网络相关异常
///
/// HTTP 错误、超时、DNS 解析失败、连接失败等
class NetworkException extends AppException {
  /// 创建网络异常
  ///
  /// [message] 错误消息
  /// [statusCode] HTTP 状态码（可选）
  /// [originalError] 原始异常
  /// [stack] 堆栈追踪
  /// [context] 错误上下文
  /// [metadata] 附加数据
  NetworkException({
    required String message,
    this.statusCode,
    Object? originalError,
    StackTrace? stack,
    String? context,
    Map<String, dynamic>? metadata,
  }) : super(
          message: message,
          code: 'NETWORK_ERROR',
          severity: ErrorSeverity.ERROR,
          originalError: originalError,
          stack: stack,
          context: context,
          metadata: metadata,
        );

  /// HTTP 状态码
  final int? statusCode;

  @override
  String toString() {
    if (statusCode != null) {
      return 'NetworkException($statusCode): $message';
    }
    return 'NetworkException: $message';
  }
}

/// 存储相关异常
///
/// 文件 I/O 错误、数据库操作错误等
class StorageException extends AppException {
  /// 创建存储异常
  StorageException({
    required String message,
    this.operation,
    this.path,
    Object? originalError,
    StackTrace? stack,
    String? context,
    Map<String, dynamic>? metadata,
  }) : super(
          message: message,
          code: 'STORAGE_ERROR',
          severity: ErrorSeverity.ERROR,
          originalError: originalError,
          stack: stack,
          context: context,
          metadata: metadata,
        );

  /// 存储操作类型（读取、写入、删除等）
  final String? operation;

  /// 操作的文件路径
  final String? path;

  @override
  String toString() {
    final parts = ['StorageException'];
    if (operation != null) parts.add('($operation)');
    if (path != null) parts.add(': $path');
    return '${parts.join(' ')} - $message';
  }
}

/// 认证/授权异常
///
/// 登录失败、token 过期、权限不足等
class AuthException extends AppException {
  /// 创建认证异常
  AuthException({
    required String message,
    this.authType,
    Object? originalError,
    StackTrace? stack,
    String? context,
    Map<String, dynamic>? metadata,
  }) : super(
          message: message,
          code: 'AUTH_FAILED',
          severity: ErrorSeverity.ERROR,
          originalError: originalError,
          stack: stack,
          context: context,
          metadata: metadata,
        );

  /// 认证类型（登录、注册、token 刷新等）
  final String? authType;

  @override
  String toString() {
    if (authType != null) {
      return 'AuthException($authType): $message';
    }
    return 'AuthException: $message';
  }
}

/// 输入验证异常
///
/// 用户输入不合法、格式错误等
class ValidationException extends AppException {
  /// 创建验证异常
  ValidationException({
    required String message,
    this.field,
    this.value,
    Object? originalError,
    StackTrace? stack,
    String? context,
    Map<String, dynamic>? metadata,
  }) : super(
          message: message,
          code: 'VALIDATION_ERROR',
          severity: ErrorSeverity.WARNING,
          originalError: originalError,
          stack: stack,
          context: context,
          metadata: metadata,
        );

  /// 验证失败的字段名
  final String? field;

  /// 用户提供的无效值
  final dynamic value;

  @override
  String toString() {
    if (field != null) {
      return 'ValidationException($field): $message';
    }
    return 'ValidationException: $message';
  }
}

/// 数据格式异常
///
/// 数据解析、序列化/反序列化错误
class DataFormatException extends AppException {
  /// 创建数据格式异常
  DataFormatException({
    required String message,
    this.expectedFormat,
    this.actualData,
    Object? originalError,
    StackTrace? stack,
    String? context,
    Map<String, dynamic>? metadata,
  }) : super(
          message: message,
          code: 'FORMAT_ERROR',
          severity: ErrorSeverity.ERROR,
          originalError: originalError,
          stack: stack,
          context: context,
          metadata: metadata,
        );

  /// 期望的格式
  final String? expectedFormat;

  /// 实际接收到的数据
  final String? actualData;

  @override
  String toString() {
    if (expectedFormat != null) {
      return 'DataFormatException(expected: $expectedFormat): $message';
    }
    return 'DataFormatException: $message';
  }
}

/// 用户取消操作异常
///
/// 用户主动取消正在进行的操作
class CancellationException extends AppException {
  /// 创建取消异常
  CancellationException({
    String message = '操作已取消',
    this.operation,
    StackTrace? stack,
    String? context,
    Map<String, dynamic>? metadata,
  }) : super(
          message: message,
          code: 'OPERATION_CANCELLED',
          severity: ErrorSeverity.INFO,
          stack: stack,
          context: context,
          metadata: metadata,
        );

  /// 被取消的操作名称
  final String? operation;

  @override
  String toString() {
    if (operation != null) {
      return 'CancellationException($operation): $message';
    }
    return 'CancellationException: $message';
  }
}

/// 操作超时异常
///
/// 异步操作执行时间超过限制
class TimeoutException extends AppException {
  /// 创建超时异常
  TimeoutException({
    required String message,
    this.timeout,
    this.operation,
    Object? originalError,
    StackTrace? stack,
    String? context,
    Map<String, dynamic>? metadata,
  }) : super(
          message: message,
          code: 'TIMEOUT_ERROR',
          severity: ErrorSeverity.ERROR,
          originalError: originalError,
          stack: stack,
          context: context,
          metadata: metadata,
        );

  /// 超时时长（毫秒）
  final int? timeout;

  /// 超时的操作名称
  final String? operation;

  @override
  String toString() {
    final parts = ['TimeoutException'];
    if (operation != null) parts.add('($operation)');
    if (timeout != null) parts.add(' [${timeout}ms]');
    return '${parts.join(' ')}: $message';
  }
}

/// 权限异常
///
/// 系统权限被拒绝
class PermissionException extends AppException {
  /// 创建权限异常
  PermissionException({
    required String message,
    this.permission,
    Object? originalError,
    StackTrace? stack,
    String? context,
    Map<String, dynamic>? metadata,
  }) : super(
          message: message,
          code: 'PERMISSION_DENIED',
          severity: ErrorSeverity.WARNING,
          originalError: originalError,
          stack: stack,
          context: context,
          metadata: metadata,
        );

  /// 被拒绝的权限名称
  final String? permission;

  @override
  String toString() {
    if (permission != null) {
      return 'PermissionException($permission): $message';
    }
    return 'PermissionException: $message';
  }
}

/// 加密/解密异常
///
/// 加密、解密、哈希等操作失败
class EncryptionException extends AppException {
  /// 创建加密异常
  EncryptionException({
    required String message,
    this.operation,
    Object? originalError,
    StackTrace? stack,
    String? context,
    Map<String, dynamic>? metadata,
  }) : super(
          message: message,
          code: 'ENCRYPTION_ERROR',
          severity: ErrorSeverity.ERROR,
          originalError: originalError,
          stack: stack,
          context: context,
          metadata: metadata,
        );

  /// 加密操作类型（加密、解密、哈希等）
  final String? operation;

  @override
  String toString() {
    if (operation != null) {
      return 'EncryptionException($operation): $message';
    }
    return 'EncryptionException: $message';
  }
}

// ============================================================================
// 统一错误处理器
// ============================================================================

/// 统一错误处理器（单例）
///
/// 提供集中的错误处理、分类和分发功能
class UnifiedErrorHandler {
  UnifiedErrorHandler._();

  static final UnifiedErrorHandler _instance = UnifiedErrorHandler._();
  static UnifiedErrorHandler get instance => _instance;

  /// 错误流 - 供 UI 监听
  final async.StreamController<AppException> _errorController =
      async.StreamController<AppException>.broadcast();

  /// 当前待处理的错误数量
  int _pendingErrors = 0;

  /// 获取错误流
  Stream<AppException> get errors => _errorController.stream;

  /// 获取当前待处理的错误数量
  int get pendingErrors => _pendingErrors;

  /// 中央错误处理方法
  ///
  /// 处理捕获的异常，将其分类为 AppException 子类，
  /// 并路由到各处理服务
  ///
  /// [error] 捕获的异常
  /// [stack] 堆栈追踪
  /// [context] 错误发生的上下文位置
  static void handle(Object error, StackTrace stack, {String? context}) {
    final instance = UnifiedErrorHandler.instance;
    instance._processError(error, stack, context);
  }

  /// 异步操作守护方法
  ///
  /// 包装异步操作，捕获异常并处理
  ///
  /// [operation] 要执行的异步操作
  /// [context] 操作的上下文描述
  /// [fallback] 异常时返回的备用值
  /// 返回操作结果或备用值
  static Future<T> guard<T>(
    Future<T> Function() operation, {
    String? context,
    T? fallback,
  }) async {
    try {
      return await operation();
    } catch (error, stack) {
      UnifiedErrorHandler.handle(error, stack, context: context);
      if (fallback != null) {
        return fallback;
      }
      rethrow;
    }
  }

  /// 处理错误的内部方法
  void _processError(Object error, StackTrace stack, String? context) {
    try {
      _pendingErrors++;

      // 如果已经是 AppException，直接使用
      AppException appException;
      if (error is AppException) {
        appException = error;
      } else {
        // 否则，将原始异常分类为 AppException 子类
        appException = _classifyException(error, stack, context);
      }

      // 更新错误的上下文（如果未设置）
      if (appException.context == null && context != null) {
        appException = _updateContext(appException, context);
      }

      // 路由错误到各处理服务
      _routeError(appException);
    } catch (e) {
      // 错误处理本身的异常
      _pendingErrors--;
      debugPrint('错误处理器异常: $e');
    }
  }

  /// 分类原始异常为 AppException 子类
  AppException _classifyException(
    Object error,
    StackTrace stack,
    String? context,
  ) {
    // 网络异常
    if (error is SocketException) {
      return NetworkException(
        message: '网络连接失败: ${error.message}',
        originalError: error,
        stack: stack,
        context: context,
      );
    }

    if (error is HttpException) {
      return NetworkException(
        message: 'HTTP 请求失败: ${error.message}',
        originalError: error,
        stack: stack,
        context: context,
      );
    }

    if (error is async.TimeoutException) {
      return TimeoutException(
        message: '操作超时，请检查网络连接后重试',
        timeout: error.duration?.inMilliseconds,
        originalError: error,
        stack: stack,
        context: context,
      );
    }

    // 格式异常
    if (error is FormatException) {
      return DataFormatException(
        message: '数据格式错误: ${error.message}',
        actualData: error.source?.toString(),
        originalError: error,
        stack: stack,
        context: context,
      );
    }

    // 平台异常（Flutter）
    if (error is PlatformException) {
      return _classifyPlatformException(error, stack, context);
    }

    // 方法通道异常
    if (error is MissingPluginException) {
      return AppException(
        message: '平台插件缺失: ${error.message ?? "未知插件"}',
        code: 'PLUGIN_MISSING',
        severity: ErrorSeverity.ERROR,
        originalError: error,
        stack: stack,
        context: context,
      );
    }

    // 默认：通用异常
    return AppException(
      message: '未知错误: ${error.toString()}',
      code: 'UNKNOWN_ERROR',
      severity: ErrorSeverity.ERROR,
      originalError: error,
      stack: stack,
      context: context,
    );
  }

  /// 分类平台异常
  AppException _classifyPlatformException(
    PlatformException error,
    StackTrace stack,
    String? context,
  ) {
    final code = error.code.toLowerCase();

    // 权限相关
    if (code.contains('permission') || code.contains('denied')) {
      return PermissionException(
        message: '权限被拒绝: ${error.message}',
        originalError: error,
        stack: stack,
        context: context,
      );
    }

    // 认证相关
    if (code.contains('auth') || code.contains('sign')) {
      return AuthException(
        message: '认证失败: ${error.message}',
        originalError: error,
        stack: stack,
        context: context,
      );
    }

    // 存储相关
    if (code.contains('file') || code.contains('storage') || code.contains('database')) {
      return StorageException(
        message: '存储操作失败: ${error.message}',
        originalError: error,
        stack: stack,
        context: context,
      );
    }

    // 网络相关
    if (code.contains('network') || code.contains('http') || code.contains('connection')) {
      return NetworkException(
        message: '网络错误: ${error.message}',
        originalError: error,
        stack: stack,
        context: context,
      );
    }

    // 通用平台异常
    return AppException(
      message: '平台错误: ${error.message}',
      code: 'PLATFORM_ERROR',
      severity: ErrorSeverity.ERROR,
      originalError: error,
      stack: stack,
      context: context,
      metadata: {'platformCode': error.code},
    );
  }

  /// 更新错误的上下文
  AppException _updateContext(AppException error, String context) {
    // 根据错误类型创建新实例并设置上下文
    return AppException(
      message: error.message,
      code: error.code,
      severity: error.severity,
      originalError: error.originalError,
      stack: error.stack,
      context: context,
      metadata: error.metadata,
    );
  }

  /// 路由错误到各处理服务
  void _routeError(AppException error) {
    try {
      // 1. 记录到错误日志服务
      ErrorLogService.log(error, StackTrace.current);

      // 2. 发送到错误流（供 UI 监听）
      _errorController.add(error);

      // 3. 如果是严重错误，还可以发送到崩溃报告服务
      if (error.severity == ErrorSeverity.ERROR) {
        _reportToCrashService(error);
      }
    } finally {
      _pendingErrors--;
    }
  }

  /// 上报到崩溃报告服务
  void _reportToCrashService(AppException error) {
    try {
      // TODO: 集成实际的崩溃报告服务（如 Firebase Crashlytics）
      debugPrint('崩溃报告: ${error.formattedMessage}');
    } catch (e) {
      debugPrint('崩溃上报失败: $e');
    }
  }

  /// 释放资源
  void dispose() {
    _errorController.close();
  }
}

// ============================================================================
// SnackBar 服务
// ============================================================================

/// SnackBar 样式配置
class SnackBarStyle {
  const SnackBarStyle({
    required this.backgroundColor,
    required this.icon,
    this.iconColor = Colors.white,
    this.textColor = Colors.white,
    this.borderColor,
  });

  /// 背景颜色
  final Color backgroundColor;

  /// 图标
  final IconData icon;

  /// 图标颜色
  final Color iconColor;

  /// 文本颜色
  final Color textColor;

  /// 边框颜色
  final Color? borderColor;

  /// 错误样式（红色）
  static const SnackBarStyle error = SnackBarStyle(
    backgroundColor: Color(0xFFD32F2F),
    icon: Icons.error_outline,
    borderColor: Color(0xFFB71C1C),
  );

  /// 警告样式（橙色）
  static const SnackBarStyle warning = SnackBarStyle(
    backgroundColor: Color(0xFFFF9800),
    icon: Icons.warning_amber_rounded,
    borderColor: Color(0xFFF57C00),
  );

  /// 成功样式（绿色）
  static const SnackBarStyle success = SnackBarStyle(
    backgroundColor: Color(0xFF4CAF50),
    icon: Icons.check_circle_outline,
    borderColor: Color(0xFF388E3C),
  );

  /// 信息样式（蓝色）
  static const SnackBarStyle info = SnackBarStyle(
    backgroundColor: Color(0xFF2196F3),
    icon: Icons.info_outline,
    borderColor: Color(0xFF1976D2),
  );
}

/// 错误 SnackBar 服务
///
/// 提供统一的 SnackBar 显示和队列管理功能
class ErrorSnackBarService {
  ErrorSnackBarService._();

  /// 最大同时显示的 SnackBar 数量
  static const int maxVisible = 3;

  /// 当前显示的 SnackBar 列表
  static final List<_SnackBarEntry> _queue = [];

  /// 显示错误 SnackBar
  ///
  /// [context] 构建上下文
  /// [error] 应用异常
  static void showError(BuildContext context, AppException error) {
    _showSnackBar(
      context,
      message: error.message,
      style: SnackBarStyle.error,
      duration: const Duration(seconds: 5),
      action: SnackBarAction(
        label: '关闭',
        textColor: Colors.white,
        onPressed: () {},
      ),
    );
  }

  /// 显示警告 SnackBar
  ///
  /// [context] 构建上下文
  /// [message] 警告消息
  static void showWarning(BuildContext context, String message) {
    _showSnackBar(
      context,
      message: message,
      style: SnackBarStyle.warning,
      duration: const Duration(seconds: 4),
    );
  }

  /// 显示成功 SnackBar
  ///
  /// [context] 构建上下文
  /// [message] 成功消息
  static void showSuccess(BuildContext context, String message) {
    _showSnackBar(
      context,
      message: message,
      style: SnackBarStyle.success,
      duration: const Duration(seconds: 2),
    );
  }

  /// 显示信息 SnackBar
  ///
  /// [context] 构建上下文
  /// [message] 信息消息
  static void showInfo(BuildContext context, String message) {
    _showSnackBar(
      context,
      message: message,
      style: SnackBarStyle.info,
      duration: const Duration(seconds: 3),
    );
  }

  /// 显示自定义 SnackBar
  ///
  /// [context] 构建上下文
  /// [message] 消息内容
  /// [style] 样式配置
  /// [duration] 显示时长
  /// [action] 操作按钮
  static void _showSnackBar(
    BuildContext context, {
    required String message,
    required SnackBarStyle style,
    required Duration duration,
    SnackBarAction? action,
  }) {
    // 移除队列中最旧的 SnackBar（如果超过最大数量）
    while (_queue.length >= maxVisible) {
      final oldest = _queue.removeAt(0);
      oldest.currentState?.removeCurrentSnackBar();
    }

    // 创建 SnackBar
    final snackBar = SnackBar(
      content: _SnackBarContent(
        message: message,
        style: style,
      ),
      backgroundColor: style.backgroundColor,
      duration: duration,
      action: action,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: style.borderColor != null
            ? BorderSide(color: style.borderColor!, width: 1)
            : BorderSide.none,
      ),
      margin: const EdgeInsets.all(16),
    );

    // 显示 SnackBar 并保存引用
    final snackBarKey = GlobalKey<ScaffoldMessengerState>();
    final entry = _SnackBarEntry(key: snackBarKey);
    _queue.add(entry);

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(snackBar).closed.then((_) {
        _queue.removeWhere((e) => e.key == snackBarKey);
      });
  }

  /// 清除所有 SnackBar
  static void clearAll() {
    for (final entry in _queue) {
      entry.currentState?.removeCurrentSnackBar();
    }
    _queue.clear();
  }
}

/// SnackBar 条目记录
class _SnackBarEntry {
  _SnackBarEntry({required this.key});

  final GlobalKey key;

  ScaffoldMessengerState? get currentState =>
      key.currentState as ScaffoldMessengerState?;
}

/// SnackBar 内容组件
class _SnackBarContent extends StatelessWidget {
  const _SnackBarContent({
    required this.message,
    required this.style,
  });

  final String message;
  final SnackBarStyle style;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          style.icon,
          color: style.iconColor,
          size: 24,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            message,
            style: TextStyle(
              color: style.textColor,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// 错误边界组件
// ============================================================================

/// 错误边界组件
///
/// 捕获子组件的构建错误并显示友好的错误 UI
class ErrorBoundary extends StatefulWidget {
  /// 创建错误边界
  const ErrorBoundary({
    super.key,
    required this.child,
    this.onError,
    this.fallbackBuilder,
    this.showErrorDetails = false,
  });

  /// 子组件
  final Widget child;

  /// 错误回调
  final void Function(Object error, StackTrace stack)? onError;

  /// 自定义错误 UI 构建器
  final Widget Function(
    BuildContext context,
    Object error,
    StackTrace stack,
    VoidCallback retry,
  )? fallbackBuilder;

  /// 是否显示错误详情（调试用）
  final bool showErrorDetails;

  @override
  State<ErrorBoundary> createState() => _ErrorBoundaryState();
}

class _ErrorBoundaryState extends State<ErrorBoundary> {
  Object? _error;
  StackTrace? _stack;

  /// 重试操作
  void _retry() {
    setState(() {
      _error = null;
      _stack = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _buildErrorUI(context, _error!, _stack!);
    }

    return widget.child;
  }

  /// 构建错误 UI
  Widget _buildErrorUI(BuildContext context, Object error, StackTrace stack) {
    // 如果提供了自定义构建器，使用它
    if (widget.fallbackBuilder != null) {
      return widget.fallbackBuilder!(context, error, stack, _retry);
    }

    // 默认错误 UI
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.error,
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.error_outline,
                color: Theme.of(context).colorScheme.error,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '组件加载失败',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            error.toString(),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onErrorContainer,
              fontSize: 14,
            ),
            maxLines: widget.showErrorDetails ? null : 3,
            overflow:
                widget.showErrorDetails ? null : TextOverflow.ellipsis,
          ),
          if (widget.showErrorDetails) ...[
            const SizedBox(height: 12),
            Text(
              '堆栈追踪:',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              stack.toString(),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
                fontSize: 12,
              ),
              maxLines: 10,
            ),
          ],
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: _retry,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void showErrorBar(FlutterErrorDetails details) {
    // 捕获 Flutter 框架错误
    setState(() {
      _error = details.exception;
      _stack = details.stack;
    });

    // 调用错误回调
    widget.onError?.call(details.exception, details.stack ?? StackTrace.empty);

    // 上报错误
    UnifiedErrorHandler.handle(
      details.exception,
      details.stack ?? StackTrace.empty,
      context: 'ErrorBoundary',
    );
  }
}

/// 错误边界守护组件（自动捕获子组件错误）
class ErrorBoundaryGuard extends StatelessWidget {
  /// 创建错误边界守护
  const ErrorBoundaryGuard({
    super.key,
    required this.builder,
    this.onError,
    this.fallbackBuilder,
  });

  /// 子组件构建器
  final Widget Function(BuildContext context) builder;

  /// 错误回调
  final void Function(Object error, StackTrace stack)? onError;

  /// 自定义错误 UI 构建器
  final Widget Function(
    BuildContext context,
    Object error,
    StackTrace stack,
    VoidCallback retry,
  )? fallbackBuilder;

  @override
  Widget build(BuildContext context) {
    return ErrorBoundary(
      onError: onError,
      fallbackBuilder: fallbackBuilder,
      child: Builder(
        builder: builder,
      ),
    );
  }
}

// ============================================================================
// 错误处理装饰器
// ============================================================================

/// 异步操作错误装饰器
///
/// 包装异步操作，自动捕获并处理错误
class AsyncErrorGuard {
  /// 守护异步操作
  ///
  /// [operation] 要执行的操作
  /// [context] 操作上下文
  /// [fallback] 失败时的备用值
  /// [onError] 额外的错误处理回调
  static Future<T> guard<T>(
    Future<T> Function() operation, {
    String? context,
    T? fallback,
    void Function(AppException error)? onError,
  }) async {
    try {
      return await operation();
    } catch (error, stack) {
      final appException = error is AppException
          ? error
          : AppException(
              message: '操作失败: ${error.toString()}',
              code: 'ASYNC_ERROR',
              severity: ErrorSeverity.ERROR,
              originalError: error,
              stack: stack,
              context: context,
            );

      // 处理错误
      UnifiedErrorHandler.handle(error, stack, context: context);

      // 调用回调
      onError?.call(appException);

      // 返回备用值或重新抛出
      if (fallback != null) {
        return fallback;
      }
      rethrow;
    }
  }

  /// 执行多个异步操作，忽略错误
  ///
  /// [operations] 操作列表
  /// [context] 操作上下文
  static Future<List<T>> guardAll<T>(
    List<Future<T> Function()> operations, {
    String? context,
  }) async {
    final results = <T>[];
    for (final operation in operations) {
      try {
        results.add(await operation());
      } catch (error, stack) {
        UnifiedErrorHandler.handle(error, stack, context: context);
      }
    }
    return results;
  }
}

// ============================================================================
// 扩展方法
// ============================================================================

/// 异步操作的错误处理扩展
extension FutureErrorGuard<T> on Future<T> {
  /// 守护 Future 操作
  ///
  /// [context] 操作上下文
  /// [fallback] 失败时的备用值
  Future<T> guard({
    String? context,
    T? fallback,
  }) {
    return AsyncErrorGuard.guard(
      () => this,
      context: context,
      fallback: fallback,
    );
  }
}

/// AppException 的便捷扩展
extension AppExceptionExtension on AppException {
  /// 是否是严重错误
  bool get isSevere => severity == ErrorSeverity.ERROR;

  /// 是否是警告
  bool get isWarning => severity == ErrorSeverity.WARNING;

  /// 是否是信息
  bool get isInfo => severity == ErrorSeverity.INFO;

  /// 转换为用户友好的消息
  String get userFriendlyMessage {
    if (isSevere) {
      return '发生错误: $message';
    } else if (isWarning) {
      return '注意: $message';
    } else {
      return message;
    }
  }
}
