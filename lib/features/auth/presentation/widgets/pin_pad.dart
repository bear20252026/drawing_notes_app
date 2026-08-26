import 'package:flutter/material.dart';

/// PIN 码输入键盘组件。
///
/// 可复用的数字键盘，用于 PIN 码输入场景。
class PinPad extends StatelessWidget {
  /// 数字按键回调
  final ValueChanged<String> onKeyPressed;

  /// 是否禁用（锁定状态）
  final bool disabled;

  const PinPad({
    super.key,
    required this.onKeyPressed,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', '⌫'],
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: keys.map((row) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: row.map((key) {
              if (key.isEmpty) {
                return const SizedBox(width: 72, height: 72);
              }
              return _KeyButton(
                value: key,
                isDark: isDark,
                disabled: disabled,
                onPressed: onKeyPressed,
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }
}

class _KeyButton extends StatelessWidget {
  final String value;
  final bool isDark;
  final bool disabled;
  final ValueChanged<String> onPressed;

  const _KeyButton({
    required this.value,
    required this.isDark,
    required this.disabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final isDelete = value == '⌫';

    return GestureDetector(
      onTap: disabled ? null : () => onPressed(value),
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.black.withValues(alpha: 0.05),
        ),
        alignment: Alignment.center,
        child: isDelete
            ? Icon(
                Icons.backspace_outlined,
                size: 24,
                color: isDark ? Colors.white70 : Colors.black54,
              )
            : Text(
                value,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w300,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
      ),
    );
  }
}
