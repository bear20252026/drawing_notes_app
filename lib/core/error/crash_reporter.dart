/// 崩溃上报接口抽象。
///
/// 统一封装 Sentry / Firebase Crashlytics 等第三方崩溃上报服务，
/// 提供一致的上报接口，便于切换实现或禁用。
library;

import 'package:flutter/foundation.dart';

/// 崩溃上报器接口。
abstract class CrashReporter {
  /// 初始化上报服务。
  Future<void> initialize();

  /// 上报一个异常。
  Future<void> reportException(
    Object error,
    StackTrace? stackTrace, {
    String? context,
    Map<String, dynamic>? extra,
  });

  /// 设置用户标识（脱敏后的用户 ID 或会话 ID）。
  Future<void> setUserId(String userId);

  /// 清除用户标识（退出登录时调用）。
  Future<void> clearUser();

  /// 添加面包屑（用于追踪用户操作路径）。
  Future<void> addBreadcrumb(String message, {String? category});
}

/// 空实现（默认不上报，仅记录日志）。
class NoopCrashReporter implements CrashReporter {
  const NoopCrashReporter();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> reportException(
    Object error,
    StackTrace? stackTrace, {
    String? context,
    Map<String, dynamic>? extra,
  }) async {
    if (kDebugMode) {
      final ctx = context != null ? '($context)' : '';
      debugPrint('[NoopCrashReporter] $error $ctx');
    }
  }

  @override
  Future<void> setUserId(String userId) async {}

  @override
  Future<void> clearUser() async {}

  @override
  Future<void> addBreadcrumb(String message, {String? category}) async {
    if (kDebugMode) {
      final tag = category != null ? '[$category]' : '';
      debugPrint('[Breadcrumb] $tag $message');
    }
  }
}

/// 开发环境上报器（仅输出到控制台）。
class DebugCrashReporter implements CrashReporter {
  const DebugCrashReporter();

  @override
  Future<void> initialize() async {
    debugPrint('[CrashReporter] Debug reporter initialized');
  }

  @override
  Future<void> reportException(
    Object error,
    StackTrace? stackTrace, {
    String? context,
    Map<String, dynamic>? extra,
  }) async {
    debugPrint('══════════════════════════════════════════');
    debugPrint('  ⚠️ EXCEPTION: $error');
    if (context != null) debugPrint('  Context: $context');
    if (extra != null && extra.isNotEmpty) debugPrint('  Extra: $extra');
    if (stackTrace != null) {
      final lines = stackTrace.toString().split('\n').take(5).join('\n');
      debugPrint('  Stack:\n$lines');
    }
    debugPrint('══════════════════════════════════════════');
  }

  @override
  Future<void> setUserId(String userId) async {
    debugPrint('[CrashReporter] User: $userId');
  }

  @override
  Future<void> clearUser() async {
    debugPrint('[CrashReporter] User cleared');
  }

  @override
  Future<void> addBreadcrumb(String message, {String? category}) {
    final tag = category != null ? '[$category]' : '';
    debugPrint('[Breadcrumb] $tag $message');
    return Future.value();
  }
}

/// 全局崩溃上报器单例。
class CrashReporterService {
  CrashReporterService._();

  static CrashReporter _instance = kDebugMode
      ? const DebugCrashReporter()
      : const NoopCrashReporter();

  /// 获取当前上报器实例。
  static CrashReporter get instance => _instance;

  /// 配置上报器（应在 main() 中尽早调用）。
  static void configure(CrashReporter reporter) {
    _instance = reporter;
  }

  /// 便捷方法：上报异常。
  static Future<void> report(
    Object error,
    StackTrace? stackTrace, {
    String? context,
    Map<String, dynamic>? extra,
  }) =>
      _instance.reportException(error, stackTrace,
          context: context, extra: extra);

  /// 便捷方法：添加面包屑。
  static Future<void> breadcrumb(String message, {String? category}) =>
      _instance.addBreadcrumb(message, category: category);
}
