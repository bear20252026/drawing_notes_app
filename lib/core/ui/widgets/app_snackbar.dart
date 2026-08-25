/// 统一 SnackBar 工具（P2 #33 + P2 #34）
library;

import 'package:flutter/material.dart';

import '../../exceptions/app_exceptions.dart';

/// SnackBar 类型
enum SnackBarType { error, success, warning, info }

/// 统一 SnackBar 工具类
class AppSnackbar {
  AppSnackbar._();

  static void showError(
    BuildContext context,
    String message, {
    VoidCallback? onRetry,
    Duration duration = const Duration(seconds: 4),
  }) {
    _show(context, message: message, type: SnackBarType.error, onRetry: onRetry, duration: duration);
  }

  static void showException(
    BuildContext context,
    Object error, {
    VoidCallback? onRetry,
    Duration duration = const Duration(seconds: 4),
  }) {
    final message = ExceptionUtils.getUserMessage(error);
    final type = _getSnackBarType(error);
    _show(context, message: message, type: type, onRetry: onRetry, duration: duration);
  }

  static void showSuccess(BuildContext context, String message, {
    Duration duration = const Duration(seconds: 2),
  }) {
    _show(context, message: message, type: SnackBarType.success, duration: duration);
  }

  static void showWarning(BuildContext context, String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    _show(context, message: message, type: SnackBarType.warning, duration: duration);
  }

  static void showInfo(BuildContext context, String message, {
    Duration duration = const Duration(seconds: 2),
  }) {
    _show(context, message: message, type: SnackBarType.info, duration: duration);
  }

  static void _show(
    BuildContext context, {
    required String message,
    required SnackBarType type,
    VoidCallback? onRetry,
    Duration duration = const Duration(seconds: 4),
  }) {
    // Apple 风格：iOS 式轻提示（深色背景，圆角 12px，无阴影）
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF2C2C2E) : const Color(0xFF1D1D1F);
    final textColor = Colors.white;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(_getIcon(type), color: textColor, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: textColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: bgColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 0,
        margin: const EdgeInsets.all(16),
        duration: duration,
        action: onRetry != null
            ? SnackBarAction(
                label: '重试',
                textColor: const Color(0xFF2997FF),
                onPressed: onRetry,
              )
            : null,
      ),
    );
  }
    final backgroundColor = _getBackgroundColor(type, colorScheme);
    final foregroundColor = _getForegroundColor(type, colorScheme);
    final icon = _getIcon(type);

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: foregroundColor, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message, style: TextStyle(color: foregroundColor)),
            ),
          ],
        ),
        backgroundColor: backgroundColor,
        duration: duration,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        action: onRetry != null
            ? SnackBarAction(label: '重试', textColor: foregroundColor, onPressed: onRetry)
            : null,
      ),
    );
  }

  static SnackBarType _getSnackBarType(Object error) {
    if (error is NetworkException) return SnackBarType.error;
    if (error is StorageException) return SnackBarType.error;
    if (error is CryptoException) return SnackBarType.warning;
    if (error is UIException) return SnackBarType.error;
    return SnackBarType.error;
  }

  static Color _getBackgroundColor(SnackBarType type, ColorScheme colorScheme) {
    switch (type) {
      case SnackBarType.error: return colorScheme.error;
      case SnackBarType.success: return const Color(0xFF2E7D32);
      case SnackBarType.warning: return const Color(0xFFE65100);
      case SnackBarType.info: return colorScheme.inverseSurface;
    }
  }

  static Color _getForegroundColor(SnackBarType type, ColorScheme colorScheme) {
    switch (type) {
      case SnackBarType.error: return colorScheme.onError;
      case SnackBarType.success: return Colors.white;
      case SnackBarType.warning: return Colors.white;
      case SnackBarType.info: return colorScheme.onInverseSurface;
    }
  }

  static IconData _getIcon(SnackBarType type) {
    switch (type) {
      case SnackBarType.error: return Icons.error_outline;
      case SnackBarType.success: return Icons.check_circle_outline;
      case SnackBarType.warning: return Icons.warning_amber;
      case SnackBarType.info: return Icons.info_outline;
    }
  }
}
