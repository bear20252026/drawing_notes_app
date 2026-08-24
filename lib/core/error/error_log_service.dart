import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 本地错误日志服务：将运行时异常写入应用文档目录下的日志文件，
/// 供调试和崩溃后排查使用。
///
/// 设计要点：
/// - 日志仅记录异常类型、消息摘要、堆栈前 500 字符（脱敏——不含用户内容）；
/// - 单文件上限 2MB，超限自动轮转（保留最近 3 个日志文件）；
/// - 仅 Debug 模式写文件，Release 模式默认关闭（可通过 [setEnabled] 强制开启）。
class ErrorLogService {
  ErrorLogService._();

  static bool _enabled = kDebugMode;
  static Directory? _logDir;
  static const int _maxLogSize = 2 * 1024 * 1024; // 2MB
  static const int _maxLogFiles = 3;

  /// 启用/禁用文件日志写入。
  static void setEnabled(bool enabled) => _enabled = enabled;

  /// 记录一条错误到本地日志文件。
  static Future<void> log(
    Object error,
    StackTrace stack, {
    String? context,
  }) async {
    if (!_enabled) return;
    try {
      final dir = await _ensureLogDir();
      final file = File('${dir.path}${Platform.pathSeparator}error.log');
      final entry = _formatEntry(error, stack, context);

      // 轮转检查
      if (await file.exists() && await file.length() > _maxLogSize) {
        await _rotateLogs(dir);
      }

      await file.writeAsString(entry, mode: FileMode.append, flush: true);
    } catch (_) {
      // 日志写入失败不应影响应用运行。
    }
  }

  static String _formatEntry(
    Object error,
    StackTrace stack,
    String? context,
  ) {
    final time = DateTime.now().toIso8601String();
    final type = error.runtimeType;
    final msg = error.toString();
    final stackStr = stack.toString();
    // 截断堆栈，避免单条日志过大。
    final truncatedStack =
        stackStr.length > 500 ? '${stackStr.substring(0, 500)}...' : stackStr;
    final ctx = context != null ? ' [$context]' : '';
    return '\n--- $time$ctx ---\n'
        'Type: $type\n'
        'Message: $msg\n'
        'Stack:\n$truncatedStack\n';
  }

  static Future<Directory> _ensureLogDir() async {
    if (_logDir != null) return _logDir!;
    final appDir = await getApplicationSupportDirectory();
    final dir = Directory('${appDir.path}${Platform.pathSeparator}logs');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _logDir = dir;
    return dir;
  }

  /// 轮转日志：error.log → error_1.log → error_2.log → 丢弃最旧。
  static Future<void> _rotateLogs(Directory dir) async {
    for (var i = _maxLogFiles - 1; i >= 1; i--) {
      final older = File('${dir.path}${Platform.pathSeparator}error_$i.log');
      if (await older.exists()) {
        if (i >= _maxLogFiles - 1) {
          await older.delete();
        } else {
          await older.rename(
            '${dir.path}${Platform.pathSeparator}error_${i + 1}.log',
          );
        }
      }
    }
    final current = File('${dir.path}${Platform.pathSeparator}error.log');
    if (await current.exists()) {
      await current.rename(
        '${dir.path}${Platform.pathSeparator}error_1.log',
      );
    }
  }

  /// 读取最近日志内容（供调试页面展示）。
  static Future<String> readRecentLogs() async {
    try {
      final dir = await _ensureLogDir();
      final file = File('${dir.path}${Platform.pathSeparator}error.log');
      if (!await file.exists()) return '';
      return await file.readAsString();
    } catch (_) {
      return '';
    }
  }
}
