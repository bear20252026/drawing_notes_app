/// iOS-style dialog (Apple HIG standard).
///
/// Features:
/// - 14px radius (Apple standard dialog corner)
/// - Centered title 17px/600
/// - Centered content 13px/400
/// - Bottom buttons (full-width, 44px height, 0.5px dividers)
/// - Flat style (no elevation)
library;

import 'package:flutter/material.dart';

/// iOS-style dialog.
class IosDialog extends StatelessWidget {
  const IosDialog({
    super.key,
    required this.title,
    this.content,
    this.contentWidget,
    this.actions = const [],
    this.scrollable = false,
  });

  final String title;
  final String? content;
  final Widget? contentWidget;
  final List<IosDialogAction> actions;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7);
    final textColor = isDark ? const Color(0xFFFFFFFF) : const Color(0xFF1D1D1F);
    final subTextColor = isDark ? const Color(0xFFEBEBF5) : const Color(0xFF6E6E73);
    final dividerColor = isDark ? const Color(0xFF38383A) : const Color(0xFFE0E0E0);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        width: 270,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Title
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
            ),
            // Content (text or custom widget)
            if (content != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                child: Text(
                  content!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: subTextColor,
                  ),
                ),
              ),
            if (contentWidget != null)
              Flexible(
                child: Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: contentWidget!,
                ),
              ),
            // Divider
            Container(height: 0.5, color: dividerColor),
            // Actions
            ..._buildIosActions(context, actions, isDark, dividerColor),
          ],
        ),
      ),
    );
  }
}

/// iOS dialog action button.
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

/// Show iOS-style dialog.
Future<T?> showIosDialog<T>(
  BuildContext context, {
  required String title,
  String? content,
  Widget? contentWidget,
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
      contentWidget: contentWidget,
      actions: actions,
    ),
  );
}

/// Show iOS-style stateful dialog (for dialogs with internal state like forms).
///
/// This wraps [StatefulBuilder] with iOS dialog styling, providing the same
/// API as [showDialog] but with Apple HIG compliant visuals.
Future<T?> showIosStatefulDialog<T>(
  BuildContext context, {
  required String title,
  required Widget Function(BuildContext context, void Function(VoidCallback) setState) builder,
  List<IosDialogAction> actions = const [],
  bool barrierDismissible = true,
  double? width,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: Colors.black54,
    builder: (context) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final bgColor = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7);
      final textColor = isDark ? const Color(0xFFFFFFFF) : const Color(0xFF1D1D1F);
      final dividerColor = isDark ? const Color(0xFF38383A) : const Color(0xFFE0E0E0);

      return Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          width: width ?? 270,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(14),
          ),
          child: StatefulBuilder(
            builder: (context, setDialogState) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Title
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                ),
                // Content
                Flexible(
                  child: builder(context, (fn) => setDialogState(fn)),
                ),
                // Divider
                Container(height: 0.5, color: dividerColor),
                // Actions
                ..._buildIosActions(context, actions, isDark, dividerColor),
              ],
            ),
          ),
        ),
      );
    },
  );
}

List<Widget> _buildIosActions(
  BuildContext context,
  List<IosDialogAction> actions,
  bool isDark,
  Color dividerColor,
) {
  if (actions.isEmpty) return [];
  if (actions.length == 1) {
    return [_buildIosAction(context, actions[0], isFirst: true, isLast: true, dividerColor: dividerColor)];
  }

  final widgets = <Widget>[];
  for (var i = 0; i < actions.length; i++) {
    widgets.add(_buildIosAction(
      context,
      actions[i],
      isFirst: i == 0,
      isLast: i == actions.length - 1,
      dividerColor: dividerColor,
    ));
  }
  return widgets;
}

Widget _buildIosAction(
  BuildContext context,
  IosDialogAction action, {
  required bool isFirst,
  required bool isLast,
  required Color dividerColor,
}) {
  return Column(
    children: [
      if (!isFirst)
        Container(height: 0.5, color: dividerColor),
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

/// iOS-style action sheet (slides up from bottom).
class IosActionSheet extends StatelessWidget {
  const IosActionSheet({
    super.key,
    this.title,
    this.message,
    required this.actions,
    this.cancelButton,
    this.destructiveButtonIndex,
  });

  final String? title;
  final String? message;
  final List<IosActionSheetAction> actions;
  final IosActionSheetAction? cancelButton;
  final int? destructiveButtonIndex;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7);
    final subTextColor = isDark ? const Color(0xFFEBEBF5) : const Color(0xFF6E6E73);
    final dividerColor = isDark ? const Color(0xFF38383A) : const Color(0xFFE0E0E0);

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Title
            if (title != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                child: Text(
                  title!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: subTextColor,
                  ),
                ),
              ),
            // Message
            if (message != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: subTextColor,
                  ),
                ),
              ),
            // Actions
            ...actions.asMap().entries.map((entry) {
              final index = entry.key;
              final action = entry.value;
              final isDestructive = destructiveButtonIndex == index;
              return Column(
                children: [
                  if (index > 0) Container(height: 0.5, color: dividerColor),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: TextButton(
                      onPressed: () {
                        Navigator.of(context).pop(action.result);
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: isDestructive
                            ? const Color(0xFFFF3B30)
                            : const Color(0xFF0066CC),
                        textStyle: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      child: Text(action.label),
                    ),
                  ),
                ],
              );
            }),
            // Divider
            Container(height: 8, color: Colors.transparent),
            // Cancel button
            if (cancelButton != null)
              SizedBox(
                width: double.infinity,
                height: 56,
                child: TextButton(
                  onPressed: () {
                    Navigator.of(context).pop(cancelButton!.result);
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF0066CC),
                    textStyle: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: Text(cancelButton!.label),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// iOS action sheet action.
class IosActionSheetAction {
  const IosActionSheetAction({
    required this.label,
    this.result,
  });

  final String label;
  final Object? result;
}

/// Show iOS-style action sheet.
Future<T?> showIosActionSheet<T>(
  BuildContext context, {
  String? title,
  String? message,
  required List<IosActionSheetAction> actions,
  IosActionSheetAction? cancelButton,
  int? destructiveButtonIndex,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => IosActionSheet(
      title: title,
      message: message,
      actions: actions,
      cancelButton: cancelButton,
      destructiveButtonIndex: destructiveButtonIndex,
    ),
  );
}
