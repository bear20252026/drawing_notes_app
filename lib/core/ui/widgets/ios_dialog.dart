/// iOS 风格对话框（Apple HIG 标准）。
///
/// 视觉特征：
/// - 圆角 14px（Apple 标准对话框圆角）
/// - 居中标题（17px/600）
/// - 居中内容（13px/400）
/// - 底部按钮（全宽，44px 高，1px 分隔线）
/// - 无阴影（Flat 风格）
library;

import 'package:flutter/material.dart';

/// iOS 风格对话框。
class IosDialog extends StatelessWidget {
  const IosDialog({
    super.key,
    required this.title,
    this.content,
    this.actions = const [],
    this.scrollable = false,
  });

  final String title;
  final String? content;
  final List<IosDialogAction> actions;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        width: 270,
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF2C2C2E)
              : const Color(0xFFF2F2F7),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1D1D1F),
                ),
              ),
            ),
            // 内容
            if (content != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                child: Text(
                  content!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: Color(0xFF6E6E73),
                  ),
                ),
              ),
            // 分隔线
            Container(height: 0.5, color: const Color(0xFFE0E0E0)),
            // 按钮
            ..._buildActions(context),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildActions(BuildContext context) {
    if (actions.isEmpty) return [];
    if (actions.length == 1) {
      return [_buildAction(context, actions[0], isFirst: true, isLast: true)];
    }

    final widgets = <Widget>[];
    for (var i = 0; i < actions.length; i++) {
      widgets.add(_buildAction(
        context,
        actions[i],
        isFirst: i == 0,
        isLast: i == actions.length - 1,
      ));
    }
    return widgets;
  }

  Widget _buildAction(
    BuildContext context,
    IosDialogAction action, {
    required bool isFirst,
    required bool isLast,
  }) {
    return Column(
      children: [
        if (!isFirst)
          Container(height: 0.5, color: const Color(0xFFE0E0E0)),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: TextButton(
            onPressed: () {
              Navigator.of(context).pop(action.result);
            },
            style: TextButton.styleFrom(
              foregroundColor: action.isDestructive
                  ? const Color(0xFFFF3B30)
                  : const Color(0xFF0066CC),
              shape: const RoundedRectangleBorder(),
              textStyle: TextStyle(
                fontSize: 17,
                fontWeight: action.isDefault ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            child: Text(action.label),
          ),
        ),
      ],
    );
  }
}

/// iOS 对话框按钮。
class IosDialogAction {
  const IosDialogAction({
    required this.label,
    this.result,
    this.isDefault = false,
    this.isDestructive = false,
  });

  final String label;
  final Object? result;
  final bool isDefault;
  final bool isDestructive;
}

/// 显示 iOS 风格对话框。
Future<T?> showIosDialog<T>(
  BuildContext context, {
  required String title,
  String? content,
  List<IosDialogAction> actions = const [],
  bool barrierDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: Colors.black54,
    builder: (context) => IosDialog(
      title: title,
      content: content,
      actions: actions,
    ),
  );
}
