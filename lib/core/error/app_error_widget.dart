import 'package:flutter/material.dart';

import 'error_log_service.dart';

/// 自定义 ErrorWidget：替换 Flutter 默认的红色错误屏幕，
/// 提供用户友好的错误页面并自动记录到本地日志。
///
/// 在 main.dart 中通过 `ErrorWidget.builder = AppErrorWidget.handler;` 注册。
class AppErrorWidget extends StatelessWidget {
  const AppErrorWidget({super.key, required this.error, required this.stack});

  final Object error;
  final StackTrace? stack;

  /// 作为 [ErrorWidget.builder] 的处理器。
  static Widget handler(FlutterErrorDetails details) {
    // 记录到本地日志文件（异步，不阻塞 UI）。
    ErrorLogService.log(
      details.exception,
      details.stack ?? StackTrace.empty,
      context: details.context?.toString(),
    );
    return AppErrorWidget(
      error: details.exception,
      stack: details.stack,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDebug = const bool.fromEnvironment('dart.vm.product') == false;

    return Material(
      color: theme.scaffoldBackgroundColor,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 64,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                '出了点问题',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '应用遇到了一个错误，但数据不会丢失。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () {
                  // 重新构建整个应用树，恢复到稳定状态。
                  Navigator.of(context).popUntil((route) => route.isFirst);
                  // 触发 framework 重新渲染首帧。
                  WidgetsBinding.instance.reassembleApplication();
                },
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('返回首页'),
              ),
              if (isDebug) ...[
                const SizedBox(height: 16),
                ExpansionTile(
                  title: const Text('错误详情（调试模式）'),
                  tilePadding: EdgeInsets.zero,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SelectableText(
                        'Error: $error\n\n$stack',
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
