import 'package:flutter/material.dart';

/// 全局错误服务：统一管理用户可见的错误提示（Snackbar / Dialog），
/// 与 [ErrorLogService] 和 [AuditLogger] 配合完成「记录 + 提示」闭环。
///
/// 使用方式：
/// ```dart
/// ErrorService.of(context).showError('保存失败，请重试');
/// ErrorService.of(context).showErrorWithRecovery(
///   message: '文件损坏，已恢复上一版本',
///   onRetry: () => _reload(),
/// );
/// ```
class ErrorService {
  ErrorService._(this._navigatorKey);

  final GlobalKey<NavigatorState> _navigatorKey;

  static ErrorService? _instance;

  /// 初始化全局 ErrorService（在 main.dart 中调用一次）。
  static void init(GlobalKey<NavigatorState> navigatorKey) {
    _instance = ErrorService._(navigatorKey);
  }

  /// 获取当前上下文可用的 ErrorService 实例。
  static ErrorService of(BuildContext context) {
    if (_instance != null) return _instance!;
    // fallback：从 context 中读取 navigatorKey。
    return ErrorService._(GlobalKey<NavigatorState>());
  }

  /// 显示一条错误 Snackbar。
  void showError(String message, {Duration duration = const Duration(seconds: 4)}) {
    final messenger = _currentMessenger;
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFFFF3B30),
        duration: duration,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  /// 显示带恢复操作的错误提示（Snackbar + 重试按钮）。
  void showErrorWithRecovery({
    required String message,
    VoidCallback? onRetry,
    String retryLabel = '重试',
  }) {
    final messenger = _currentMessenger;
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.orange.shade800,
        duration: const Duration(seconds: 6),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        action: onRetry != null
            ? SnackBarAction(
                label: retryLabel,
                textColor: Colors.white,
                onPressed: onRetry,
              )
            : null,
      ),
    );
  }

  /// 显示信息提示 Snackbar（非错误，用于操作反馈）。
  void showInfo(String message) {
    final messenger = _currentMessenger;
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  ScaffoldMessengerState? get _currentMessenger {
    final ctx = _navigatorKey.currentContext;
    if (ctx == null) return null;
    return ScaffoldMessenger.of(ctx);
  }
}
