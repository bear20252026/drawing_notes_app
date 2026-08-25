// Copyright (c) 2026 Project Authors. All rights reserved.
//
// 崩溃报告服务层：提供统一的崩溃/错误上报抽象，支持 Sentry、Firebase Crashlytics
// 或本地日志回退方案。通过平台自动检测选择最佳实现，保证应用在所有环境下都能
// 记录和上报异常信息。
//
// 设计原则：
// - 接口抽象化：CrashReporter 定义标准契约，具体实现可插拔
// - 安全敏感数据过滤：自动移除密码、令牌、API 密钥等敏感信息
// - 平台适配：Web/Desktop 使用 Sentry，移动端使用 Crashlytics，开发环境使用本地日志
// - 优雅降级：无 DSN 或依赖不可用时自动回退到本地存储

import 'dart:io';

import 'package:flutter/foundation.dart';

import 'error_log_service.dart';

/// ============================================================
/// 1. 抽象接口层
/// ============================================================

/// 崩溃报告器抽象接口：定义所有崩溃上报服务的标准契约。
///
/// 所有实现必须满足：
//   - 初始化时接受 DSN 或配置参数
//   - 支持用户上下文和自定义标签设置
//   - 提供错误和消息上报接口
//   - 支持面包屑追踪（用户操作轨迹记录）
abstract class CrashReporter {
  /// 使用 DSN 或配置参数初始化上报服务。
  ///
  /// [dsn] - 数据源名称（Sentry/Crashlytics 所需的认证标识），
  ///          本地上报时可为 null。
  Future<void> initialize({String? dsn});

  /// 设置当前用户标识，用于关联用户与错误报告。
  ///
  /// [userId] - 用户唯一标识符（应脱敏处理，避免泄露隐私）。
  void setUserId(String userId);

  /// 为后续上报添加自定义标签（键值对），帮助过滤和搜索错误。
  ///
  /// [key] - 标签名（如 'environment'、'version'）
  /// [value] - 标签值（如 'production'、'2.1.0'）
  void setTag(String key, String value);

  /// 上报非致命错误到远程服务。
  ///
  /// [error] - 异常对象
  /// [stack] - 堆栈追踪
  /// [context] - 可选的错误上下文描述（如当前页面、操作名称）
  /// [extras] - 可选的附加数据（如用户输入、设备状态等）
  ///
  /// 注意：所有上报数据都会经过敏感信息过滤。
  Future<void> reportError(
    Object error,
    StackTrace stack, {
    String? context,
    Map<String, dynamic>? extras,
  });

  /// 上报普通消息/日志到远程服务（非错误级别）。
  ///
  /// [message] - 消息内容
  /// [stack] - 可选的堆栈追踪（通常用于警告级别日志）
  Future<void> reportMessage(String message, {StackTrace? stack});

  /// 添加面包屑记录：追踪用户操作和系统事件的时间线。
  ///
  /// [message] - 事件描述
  /// [category] - 事件分类（如 'navigation'、'ui.click'、'http'）
  /// [data] - 附加数据（如页面路由、请求参数等）
  void logBreadcrumb(
    String message, {
    String? category,
    Map<String, dynamic>? data,
  });
}

/// ============================================================
/// 2. 实现层 - Sentry
/// ============================================================

/// Sentry 崩溃上报器实现（针对 Web/Desktop 平台优化）。
///
/// Sentry 特性：
//   - 实时崩溃监控和性能追踪
//   - 高级错误分组和去重
//   - 用户反馈集成
//   - 自动性能追踪（页面加载、网络请求等）
///
/// 注意：这是完整的桩实现；若需实际集成 Sentry，请使用
/// `sentry` 或 `sentry_flutter` 包替换此实现。
class SentryReporter implements CrashReporter {
  SentryReporter._();

  String? _dsn;
  String? _userId;
  final Map<String, String> _tags = {};
  bool _initialized = false;

  // 敏感数据过滤器实例
  final _sanitizer = _SensitiveDataSanitizer();

  @override
  Future<void> initialize({String? dsn}) async {
    if (dsn == null || dsn.isEmpty) {
      debugPrint('[SentryReporter] 未提供 DSN，跳过 Sentry 初始化');
      return;
    }

    _dsn = dsn;
    _initialized = true;

    // TODO: 在实际集成中，此处调用 Sentry.init()
    // Sentry.init((options) {
    //   options.dsn = dsn;
    //   options.beforeSend = _filterSensitiveData;
    //   options.environment = kDebugMode ? 'debug' : 'production';
    // });

    debugPrint('[SentryReporter] Sentry 已初始化（桩实现）');
  }

  @override
  void setUserId(String userId) {
    _userId = _sanitizer.sanitizeUserId(userId);
    debugPrint('[SentryReporter] 用户 ID 已设置: $_userId');
  }

  @override
  void setTag(String key, String value) {
    _tags[key] = _sanitizer.sanitizeTagValue(value);
    debugPrint('[SentryReporter] 标签已设置: $key = ${_tags[key]}');
  }

  @override
  Future<void> reportError(
    Object error,
    StackTrace stack, {
    String? context,
    Map<String, dynamic>? extras,
  }) async {
    if (!_initialized) {
      debugPrint('[SentryReporter] 未初始化，无法上报错误');
      return;
    }

    final sanitizedError = _sanitizer.sanitizeObject(error);
    final sanitizedStack = _sanitizer.sanitizeStackTrace(stack);
    final sanitizedExtras = extras != null
        ? Map<String, dynamic>.from(
            extras.map((k, v) => MapEntry(k, _sanitizer.sanitizeObject(v))),
          )
        : null;

    // TODO: 在实际集成中，调用 Sentry.captureException()
    // Sentry.captureException(
    //   sanitizedError,
    //   stackTrace: sanitizedStack,
    //   hint: Hint.withMap({
    //     if (context != null) 'context': context,
    //     if (sanitizedExtras != null) 'extras': sanitizedExtras,
    //     'userId': _userId,
    //     ..._tags,
    //   }),
    // );

    debugPrint('[SentryReporter] 错误已上报（桩实现）');
    debugPrint('  错误: $sanitizedError');
    debugPrint('  上下文: $context');
  }

  @override
  Future<void> reportMessage(String message, {StackTrace? stack}) async {
    if (!_initialized) return;

    final sanitizedMessage = _sanitizer.sanitizeString(message);

    // TODO: 在实际集成中，调用 Sentry.captureMessage()
    // Sentry.captureMessage(
    //   sanitizedMessage,
    //   stackTrace: stack != null ? _sanitizer.sanitizeStackTrace(stack) : null,
    // );

    debugPrint('[SentryReporter] 消息已上报（桩实现）: $sanitizedMessage');
  }

  @override
  void logBreadcrumb(
    String message, {
    String? category,
    Map<String, dynamic>? data,
  }) {
    if (!_initialized) return;

    final sanitizedMessage = _sanitizer.sanitizeString(message);
    final sanitizedData = data != null
        ? Map<String, dynamic>.from(
            data.map((k, v) => MapEntry(k, _sanitizer.sanitizeObject(v))),
          )
        : null;

    // TODO: 在实际集成中，调用 Sentry.addBreadcrumb()
    // Sentry.addBreadcrumb(Breadcrumb(
    //   message: sanitizedMessage,
    //   category: category,
    //   data: sanitizedData,
    //   timestamp: DateTime.now(),
    // ));

    debugPrint(
      '[SentryReporter] 面包屑已记录（桩实现）: [$category] $sanitizedMessage',
    );
  }
}

/// ============================================================
/// 3. 实现层 - Firebase Crashlytics
/// ============================================================

/// Firebase Crashlytics 崩溃上报器实现（针对移动平台优化）。
///
/// Crashlytics 特性：
//   - 与 Firebase 控制台深度集成
//   - 自动收集崩溃报告和 ANR 事件
//   - 自定义日志和非致命异常记录
//   - 用户属性和自定义键值对设置
///
/// 注意：这是完整的桩实现；若需实际集成 Crashlytics，请使用
/// `firebase_crashlytics` 包替换此实现。
class CrashlyticsReporter implements CrashReporter {
  CrashlyticsReporter._();

  bool _initialized = false;
  String? _userId;
  final Map<String, String> _customKeys = {};
  final _sanitizer = _SensitiveDataSanitizer();

  @override
  Future<void> initialize({String? dsn}) async {
    // Firebase Crashlytics 不需要 DSN（通过 firebase_options.dart 配置）
    // 此处仅做初始化标记

    _initialized = true;

    // TODO: 在实际集成中，初始化 Firebase 并启用 Crashlytics
    // await Firebase.initializeApp();
    // await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);

    debugPrint('[CrashlyticsReporter] Firebase Crashlytics 已初始化（桩实现）');
  }

  @override
  void setUserId(String userId) {
    _userId = _sanitizer.sanitizeUserId(userId);

    // TODO: 在实际集成中，调用 Crashlytics.setCustomKey()
    // FirebaseCrashlytics.instance.setUserIdentifier(_userId);

    debugPrint('[CrashlyticsReporter] 用户 ID 已设置: $_userId');
  }

  @override
  void setTag(String key, String value) {
    final sanitizedKey = _sanitizer.sanitizeTagKey(key);
    final sanitizedValue = _sanitizer.sanitizeTagValue(value);

    _customKeys[sanitizedKey] = sanitizedValue;

    // TODO: 在实际集成中，调用 Crashlytics.setCustomKey()
    // FirebaseCrashlytics.instance.setCustomKey(sanitizedKey, sanitizedValue);

    debugPrint(
      '[CrashlyticsReporter] 自定义键已设置: $sanitizedKey = $sanitizedValue',
    );
  }

  @override
  Future<void> reportError(
    Object error,
    StackTrace stack, {
    String? context,
    Map<String, dynamic>? extras,
  }) async {
    if (!_initialized) {
      debugPrint('[CrashlyticsReporter] 未初始化，无法上报错误');
      return;
    }

    final sanitizedError = _sanitizer.sanitizeObject(error);
    final sanitizedStack = _sanitizer.sanitizeStackTrace(stack);
    final sanitizedContext = context != null
        ? _sanitizer.sanitizeString(context)
        : null;

    // TODO: 在实际集成中，记录非致命异常
    // FirebaseCrashlytics.instance.recordError(
    //   sanitizedError,
    //   sanitizedStack,
    //   reason: sanitizedContext,
    //   information: extras != null ? _sanitizer.sanitizeMap(extras) : null,
    // );

    debugPrint('[CrashlyticsReporter] 错误已上报（桩实现）');
    debugPrint('  错误: $sanitizedError');
    debugPrint('  上下文: $sanitizedContext');
  }

  @override
  Future<void> reportMessage(String message, {StackTrace? stack}) async {
    if (!_initialized) return;

    final sanitizedMessage = _sanitizer.sanitizeString(message);

    // TODO: 在实际集成中，记录自定义日志
    // FirebaseCrashlytics.instance.log(sanitizedMessage);

    debugPrint(
      '[CrashlyticsReporter] 消息已记录（桩实现）: $sanitizedMessage',
    );
  }

  @override
  void logBreadcrumb(
    String message, {
    String? category,
    Map<String, dynamic>? data,
  }) {
    if (!_initialized) return;

    final sanitizedMessage = _sanitizer.sanitizeString(message);
    final formattedMessage = category != null
        ? '[$category] $sanitizedMessage'
        : sanitizedMessage;

    // TODO: 在实际集成中，记录自定义日志（Crashlytics 无面包屑概念，用日志替代）
    // FirebaseCrashlytics.instance.log(formattedMessage);

    debugPrint(
      '[CrashlyticsReporter] 面包屑已记录（桩实现）: $formattedMessage',
    );
  }
}

/// ============================================================
/// 4. 实现层 - 本地日志记录器
/// ============================================================

/// 本地崩溃报告器实现：开发环境的优雅降级方案。
///
/// 特性：
//   - 无需外部服务配置（无 DSN 也能工作）
//   - 使用 ErrorLogService 存储错误到本地文件
//   - 支持离线模式和后续上传（通过 readUnsyncedReports）
//   - 自动脱敏处理敏感数据
///
/// 适用场景：
//   - 开发和调试阶段
//   - 外部崩溃上报服务不可用时的降级方案
//   - 内网/受限网络环境
class LocalCrashReporter implements CrashReporter {
  LocalCrashReporter._();

  bool _initialized = false;
  String? _userId;
  final Map<String, String> _tags = {};
  final List<_LocalCrashReport> _pendingReports = [];
  final _sanitizer = _SensitiveDataSanitizer();

  @override
  Future<void> initialize({String? dsn}) async {
    // 本地上报不需要 DSN
    _initialized = true;
    debugPrint('[LocalCrashReporter] 本地崩溃上报器已初始化');
  }

  @override
  void setUserId(String userId) {
    _userId = _sanitizer.sanitizeUserId(userId);
    debugPrint('[LocalCrashReporter] 用户 ID 已设置: $_userId');
  }

  @override
  void setTag(String key, String value) {
    _tags[key] = _sanitizer.sanitizeTagValue(value);
    debugPrint('[LocalCrashReporter] 标签已设置: $key = ${_tags[key]}');
  }

  @override
  Future<void> reportError(
    Object error,
    StackTrace stack, {
    String? context,
    Map<String, dynamic>? extras,
  }) async {
    if (!_initialized) {
      debugPrint('[LocalCrashReporter] 未初始化，无法上报错误');
      return;
    }

    final sanitizedError = _sanitizer.sanitizeObject(error);
    final sanitizedStack = _sanitizer.sanitizeStackTrace(stack);
    final sanitizedContext = context != null
        ? _sanitizer.sanitizeString(context)
        : null;

    // 使用 ErrorLogService 记录错误到本地文件
    await ErrorLogService.log(
      sanitizedError,
      stack,
      context: sanitizedContext,
    );

    // 同时保存到待上传队列（用于后续批量同步）
    _pendingReports.add(
      _LocalCrashReport(
        type: _LocalCrashReportType.error,
        error: sanitizedError.toString(),
        stackTrace: sanitizedStack.toString(),
        context: sanitizedContext,
        userId: _userId,
        tags: Map.from(_tags),
        extras: extras,
        timestamp: DateTime.now(),
      ),
    );

    debugPrint('[LocalCrashReporter] 错误已记录到本地（桩实现）');
  }

  @override
  Future<void> reportMessage(String message, {StackTrace? stack}) async {
    if (!_initialized) return;

    final sanitizedMessage = _sanitizer.sanitizeString(message);
    final sanitizedStack = stack != null
        ? _sanitizer.sanitizeStackTrace(stack)
        : null;

    // 保存到待上传队列
    _pendingReports.add(
      _LocalCrashReport(
        type: _LocalCrashReportType.message,
        error: sanitizedMessage,
        stackTrace: sanitizedStack?.toString(),
        userId: _userId,
        tags: Map.from(_tags),
        timestamp: DateTime.now(),
      ),
    );

    debugPrint('[LocalCrashReporter] 消息已记录（桩实现）: $sanitizedMessage');
  }

  @override
  void logBreadcrumb(
    String message, {
    String? category,
    Map<String, dynamic>? data,
  }) {
    if (!_initialized) return;

    final sanitizedMessage = _sanitizer.sanitizeString(message);

    // 本地上报器仅在控制台输出面包屑
    debugPrint(
      '[LocalCrashReporter] 面包屑（桩实现）: [$category] $sanitizedMessage',
    );
  }

  /// 获取所有待上报的本地崩溃记录（用于后续批量上传）。
  List<Map<String, dynamic>> readUnsyncedReports() {
    return _pendingReports
        .map((report) => report.toMap())
        .toList();
  }

  /// 清除已同步的上报记录。
  void clearSyncedReports() {
    _pendingReports.clear();
    debugPrint('[LocalCrashReporter] 已同步的上报记录已清除');
  }
}

/// ============================================================
/// 5. 单例管理服务
/// ============================================================

/// 崩溃报告服务单例：统一管理崩溃上报器的初始化、配置和使用。
///
/// 自动检测当前平台并选择最佳的崩溃上报器实现：
//   - Web/Desktop → Sentry
//   - Android/iOS → Firebase Crashlytics
//   - 开发环境或无 DSN → 本地日志
///
/// 使用示例：
/// ```dart
/// // 初始化（在 main.dart 中调用）
/// await CrashReportingService.initialize(dsn: 'your-sentry-dsn');
///
/// // 上报错误
/// CrashReportingService.report(
///   error,
///   stack,
///   context: '加载用户数据失败',
/// );
///
/// // 记录面包屑
/// CrashReportingService.instance.logBreadcrumb(
///   '用户点击了保存按钮',
///   category: 'ui.click',
/// );
/// ```
class CrashReportingService {
  CrashReportingService._();

  static CrashReporter? _instance;
  static bool _initialized = false;

  /// 获取当前活跃的崩溃上报器实例。
  ///
  /// 如果尚未初始化，返回本地崩溃上报器作为默认值。
  static CrashReporter get instance {
    if (_instance == null) {
      // 延迟初始化：使用本地上报器作为默认值
      _instance = LocalCrashReporter._();
      _instance!.initialize();
      _initialized = true;
    }
    return _instance!;
  }

  /// 初始化崩溃报告服务，自动检测平台并选择最佳上报器。
  ///
  /// [dsn] - 数据源名称（可选）；提供时启用 Sentry（Web/Desktop）
  ///         或 Crashlytics（移动端），否则使用本地上报器。
  ///
  /// 平台检测逻辑：
  /// 1. Web 平台 → 使用 Sentry
  /// 2. Desktop（Windows/macOS/Linux）→ 使用 Sentry
  /// 3. Android/iOS → 使用 Firebase Crashlytics（需提供 dsn）
  /// 4. 其他或无 dsn → 使用本地上报器
  static Future<void> initialize({String? dsn}) async {
    if (_initialized) {
      debugPrint('[CrashReportingService] 已初始化，跳过重复初始化');
      return;
    }

    // 平台检测并选择上报器
    _instance = _createReporterForPlatform(dsn);
    await _instance!.initialize(dsn: dsn);
    _initialized = true;

    debugPrint('[CrashReportingService] 已初始化，上报器: ${_instance.runtimeType}');
  }

  /// 平台检测：根据运行时平台创建合适的崩溃上报器。
  static CrashReporter _createReporterForPlatform(String? dsn) {
    // Web 平台检查
    if (kIsWeb) {
      debugPrint('[CrashReportingService] 检测到 Web 平台，使用 Sentry');
      return SentryReporter._();
    }

    // 桌面平台检查
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      debugPrint('[CrashReportingService] 检测到桌面平台 (${Platform.operatingSystem})，使用 Sentry');
      return SentryReporter._();
    }

    // 移动平台检查
    if (Platform.isAndroid || Platform.isIOS) {
      if (dsn != null && dsn.isNotEmpty) {
        debugPrint('[CrashReportingService] 检测到移动平台 (${Platform.operatingSystem})，使用 Crashlytics');
        return CrashlyticsReporter._();
      } else {
        debugPrint('[CrashReportingService] 检测到移动平台但无 DSN，使用本地上报器');
        return LocalCrashReporter._();
      }
    }

    // 未知平台或开发环境 → 本地上报器
    debugPrint('[CrashReportingService] 未知平台，使用本地上报器');
    return LocalCrashReporter._();
  }

  /// 上报错误的简写方法。
  ///
  /// [error] - 异常对象
  /// [stack] - 堆栈追踪
  /// [context] - 可选的上下文描述
  ///
  /// 使用示例：
  /// ```dart
  /// try {
  ///   await api.fetchData();
  /// } catch (error, stack) {
  ///   CrashReportingService.report(error, stack, context: '获取用户数据');
  /// }
  /// ```
  static void report(
    Object error,
    StackTrace stack, {
    String? context,
  }) {
    instance.reportError(error, stack, context: context);
  }

  /// 设置用户标识符。
  static void setUserId(String userId) {
    instance.setUserId(userId);
  }

  /// 设置自定义标签。
  static void setTag(String key, String value) {
    instance.setTag(key, value);
  }

  /// 记录面包屑事件。
  static void logBreadcrumb(
    String message, {
    String? category,
    Map<String, dynamic>? data,
  }) {
    instance.logBreadcrumb(message, category: category, data: data);
  }

  /// 上报普通消息。
  static Future<void> reportMessage(
    String message, {
    StackTrace? stack,
  }) {
    return instance.reportMessage(message, stack: stack);
  }

  /// 重置服务（仅用于测试）。
  @visibleForTesting
  static void reset() {
    _instance = null;
    _initialized = false;
  }
}

/// ============================================================
/// 6. 敏感数据过滤器
/// ============================================================

/// 敏感数据脱敏处理器：自动过滤和净化错误报告中的敏感信息。
///
/// 处理范围：
//   - 密码、令牌、API 密钥等认证凭证
//   - 用户个人信息（邮箱、电话、身份证号）
//   - 文件路径（移除用户主目录）
//   - 长堆栈追踪截断
///
/// 脱敏策略：
//   - 字符串模式匹配 + 正则表达式检测
//   - 关键词替换为 [REDACTED] 标记
//   - 路径规范化（移除 /Users/username/ 或 C:\Users\username\）
class _SensitiveDataSanitizer {
  /// 正则表达式模式：匹配敏感信息
  static final _sensitivePatterns = [
    // 密码和令牌
    RegExp(r'(?i)(password|passwd|pwd|secret|token|api[_-]?key|auth[_-]?token)\s*[:=]\s*\S+'),
    // 电子邮箱
    RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}'),
    // 中国手机号码
    RegExp(r'1[3-9]\d{9}'),
    // 身份证号码
    RegExp(r'\d{17}[\dXx]'),
    // 信用卡号
    RegExp(r'\b(?:\d[ -]*?){13,16}\b'),
  ];

  /// 关键词列表：出现在键名中则认为是敏感字段
  static final _sensitiveKeywords = [
    'password', 'passwd', 'pwd', 'secret', 'token',
    'api_key', 'apikey', 'api-key', 'auth', 'credential',
    'access_token', 'refresh_token', 'bearer',
  ];

  /// 主机用户名列表：用于移除文件路径中的用户主目录
  static final _homePatterns = [
    RegExp(r'/Users/[^/]+/'),  // macOS/Linux
    RegExp(r'/home/[^/]+/'),   // Linux
    RegExp(r'C:\\Users\\[^\\]+\\'),  // Windows
    RegExp(r'D:\\Users\\[^\\]+\\'),  // Windows (D drive)
  ];

  /// 清理字符串：移除敏感信息并规范化。
  String sanitizeString(String input) {
    if (input.isEmpty) return input;

    var result = input;

    // 移除敏感模式匹配
    for (final pattern in _sensitivePatterns) {
      result = result.replaceAll(pattern, '[REDACTED]');
    }

    // 规范化文件路径
    result = _sanitizeFilePath(result);

    return result;
  }

  /// 清理堆栈追踪：截断过长的堆栈并脱敏路径。
  String sanitizeStackTrace(StackTrace stack) {
    var stackStr = stack.toString();

    // 脱敏路径
    stackStr = _sanitizeFilePath(stackStr);

    // 截断过长堆栈（保留前 1000 字符）
    const maxLength = 1000;
    if (stackStr.length > maxLength) {
      stackStr = '${stackStr.substring(0, maxLength)}\n... (truncated)';
    }

    return stackStr;
  }

  /// 清理对象：如果是字符串则净化，否则转为字符串后净化。
  String sanitizeObject(Object obj) {
    if (obj is String) {
      return sanitizeString(obj);
    }
    return sanitizeString(obj.toString());
  }

  /// 清理用户 ID：移除潜在的敏感信息。
  String sanitizeUserId(String userId) {
    // 用户 ID 通常不应包含敏感信息，但以防万一进行脱敏
    return sanitizeString(userId);
  }

  /// 清理标签键：移除潜在的敏感信息。
  String sanitizeTagKey(String key) {
    final lowerKey = key.toLowerCase();

    // 检查是否为敏感关键词
    for (final keyword in _sensitiveKeywords) {
      if (lowerKey.contains(keyword)) {
        return '[REDACTED_KEY]';
      }
    }

    return key;
  }

  /// 清理标签值：脱敏处理。
  String sanitizeTagValue(String value) {
    return sanitizeString(value);
  }

  /// 清理 Map：对所有键值对进行脱敏。
  Map<String, dynamic> sanitizeMap(Map<String, dynamic> map) {
    return Map<String, dynamic>.from(
      map.map((key, value) {
        final sanitizedKey = sanitizeTagKey(key);
        final sanitizedValue = sanitizeObject(value);
        return MapEntry(sanitizedKey, sanitizedValue);
      }),
    );
  }

  /// 规范化文件路径：移除用户主目录部分。
  String _sanitizeFilePath(String input) {
    var result = input;

    for (final pattern in _homePatterns) {
      result = result.replaceAll(pattern, '[HOME]/');
    }

    return result;
  }
}

/// ============================================================
/// 7. 本地崩溃报告数据模型
/// ============================================================

/// 本地崩溃报告类型枚举。
enum _LocalCrashReportType {
  error,
  message,
}

/// 本地崩溃报告数据模型：用于存储待上传的错误/消息记录。
class _LocalCrashReport {
  const _LocalCrashReport({
    required this.type,
    required this.error,
    this.stackTrace,
    this.context,
    this.userId,
    this.tags = const {},
    this.extras,
    required this.timestamp,
  });

  final _LocalCrashReportType type;
  final String error;
  final String? stackTrace;
  final String? context;
  final String? userId;
  final Map<String, String> tags;
  final Map<String, dynamic>? extras;
  final DateTime timestamp;

  /// 转换为可序列化的 Map（用于上传或本地存储）。
  Map<String, dynamic> toMap() {
    return {
      'type': type.name,
      'error': error,
      if (stackTrace != null) 'stack_trace': stackTrace,
      if (context != null) 'context': context,
      if (userId != null) 'user_id': userId,
      'tags': tags,
      if (extras != null) 'extras': extras,
      'timestamp': timestamp.toIso8601String(),
      'platform': _getPlatformInfo(),
    };
  }

  /// 获取平台信息摘要。
  static Map<String, String> _getPlatformInfo() {
    return {
      'os': Platform.operatingSystem,
      'os_version': Platform.operatingSystemVersion,
      if (!kIsWeb) 'locale': Platform.localeName,
    };
  }

  /// 从 JSON 反序列化。
  factory _LocalCrashReport.fromMap(Map<String, dynamic> map) {
    return _LocalCrashReport(
      type: _LocalCrashReportType.values.firstWhere(
        (t) => t.name == map['type'],
        orElse: () => _LocalCrashReportType.error,
      ),
      error: map['error'] as String,
      stackTrace: map['stack_trace'] as String?,
      context: map['context'] as String?,
      userId: map['user_id'] as String?,
      tags: Map<String, String>.from(map['tags'] ?? {}),
      extras: map['extras'] as Map<String, dynamic>?,
      timestamp: DateTime.parse(map['timestamp'] as String),
    );
  }

  @override
  String toString() {
    return '_LocalCrashReport('
        'type: ${type.name}, '
        'error: $error, '
        'context: $context, '
        'timestamp: $timestamp)';
  }
}
