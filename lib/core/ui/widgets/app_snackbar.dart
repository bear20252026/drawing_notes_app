/// iOS-style SnackBar utility (Apple HIG compliant)
library;

import 'package:flutter/material.dart';

import '../../exceptions/app_exceptions.dart';

/// SnackBar type
enum SnackBarType { error, success, warning, info }

/// Unified SnackBar utility — Apple style: dark background, 12px radius, floating, no elevation
class AppSnackbar {
  static void show(
    BuildContext context, {
    required String message,
    SnackBarType type = SnackBarType.info,
    VoidCallback? onRetry,
    Duration duration = const Duration(seconds: 4),
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF2C2C2E) : const Color(0xFF1D1D1F);

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(_getIcon(type), color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                  letterSpacing: -0.24,
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
                label: 'Retry',
                textColor: const Color(0xFF2997FF),
                onPressed: onRetry,
              )
            : null,
      ),
    );
  }

  static void showError(
    BuildContext context,
    String message, {
    VoidCallback? onRetry,
    Duration duration = const Duration(seconds: 4),
  }) {
    show(context, message: message, type: SnackBarType.error, onRetry: onRetry, duration: duration);
  }

  static void showException(
    BuildContext context,
    Object error, {
    VoidCallback? onRetry,
    Duration duration = const Duration(seconds: 4),
  }) {
    final message = ExceptionUtils.getUserMessage(error);
    final type = error is CryptoException ? SnackBarType.warning : SnackBarType.error;
    show(context, message: message, type: type, onRetry: onRetry, duration: duration);
  }

  static void showSuccess(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 2),
  }) {
    show(context, message: message, type: SnackBarType.success, duration: duration);
  }

  static void showWarning(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    show(context, message: message, type: SnackBarType.warning, duration: duration);
  }

  static void showInfo(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 2),
  }) {
    show(context, message: message, duration: duration);
  }

  static IconData _getIcon(SnackBarType type) {
    switch (type) {
      case SnackBarType.error:
        return Icons.error_outline_rounded;
      case SnackBarType.success:
        return Icons.check_circle_outline_rounded;
      case SnackBarType.warning:
        return Icons.warning_amber_rounded;
      case SnackBarType.info:
        return Icons.info_outline_rounded;
    }
  }
}
