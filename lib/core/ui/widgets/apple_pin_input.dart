/// Apple 风格 PIN 输入组件。
///
/// 设计参考 iOS 锁屏密码输入：独立方框、自动聚焦、错误抖动动画、完成回调。
/// 遵循 Apple HIG 密码输入规范：
/// - 6 位数字（可配置 4–8 位）
/// - 独立输入框，圆角 12px，间距 12px
/// - 已输入显示填充框，未输入显示空心框
/// - 错误时红色边框 + 抖动动画
/// - 自动提交（输入满后回调）
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Apple 风格 PIN 输入组件。
///
/// 使用方式：
/// ```dart
/// ApplePinInput(
///   length: 6,
///   onCompleted: (pin) => _verifyPin(pin),
/// )
/// ```
class ApplePinInput extends StatefulWidget {
  /// PIN 位数（默认 6）。
  final int length;

  /// 输入完成回调（输入满 length 位后触发）。
  final ValueChanged<String> onCompleted;

  /// 是否使用数字键盘。
  final bool obscureText;

  /// 自定义圆点字符（默认 ●）。
  final String obscureCharacter;

  /// 输入框尺寸。
  final double boxSize;

  /// 输入框间距。
  final double spacing;

  const ApplePinInput({
    super.key,
    this.length = 6,
    required this.onCompleted,
    this.obscureText = true,
    this.obscureCharacter = '●',
    this.boxSize = 48,
    this.spacing = 12,
  });

  @override
  State<ApplePinInput> createState() => _ApplePinInputState();
}

class _ApplePinInputState extends State<ApplePinInput>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 12)
        .chain(CurveTween(curve: Curves.elasticIn))
        .animate(_shakeController)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _shakeController.reverse();
        }
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    setState(() {
      _hasError = false;
    });
    if (_controller.text.length == widget.length) {
      widget.onCompleted(_controller.text);
    }
  }

  /// 触发错误动画（外部验证失败时调用）。
  void triggerError() {
    setState(() => _hasError = true);
    _shakeController.forward(from: 0);
    HapticFeedback.mediumImpact();
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) {
        _controller.clear();
        _focusNode.requestFocus();
      }
    });
  }

  /// 清空输入。
  void clear() {
    _controller.clear();
    setState(() => _hasError = false);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _focusNode.requestFocus(),
      child: AnimatedBuilder(
        animation: _shakeAnimation,
        builder: (context, child) {
          return Transform.translate(
            offset: Offset(_shakeAnimation.value, 0),
            child: child,
          );
        },
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 隐藏的实际输入框（用于接收键盘输入）。
            Opacity(
              opacity: 0,
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                keyboardType: TextInputType.number,
                maxLength: widget.length,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: const InputDecoration(
                  counterText: '',
                  border: InputBorder.none,
                ),
              ),
            ),
            // 视觉 PIN 框。
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(widget.length, (index) {
                final isFilled = index < _controller.text.length;
                final text = widget.obscureText
                    ? (isFilled ? widget.obscureCharacter : '')
                    : (isFilled ? _controller.text[index] : '');
                return Container(
                  width: widget.boxSize,
                  height: widget.boxSize,
                  margin: EdgeInsets.symmetric(horizontal: widget.spacing / 2),
                  decoration: BoxDecoration(
                    color: isFilled
                        ? (_hasError
                            ? const Color(0xFFFF3B30).withOpacity(0.1)
                            : const Color(0xFF0066CC).withOpacity(0.1))
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _hasError
                          ? const Color(0xFFFF3B30)
                          : isFilled
                              ? const Color(0xFF0066CC)
                              : const Color(0xFFD2D2D7),
                      width: 2,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: isFilled
                      ? Text(
                          text,
                          style: TextStyle(
                            fontSize: widget.obscureText ? 20 : 24,
                            fontWeight: FontWeight.w600,
                            color: _hasError
                                ? const Color(0xFFFF3B30)
                                : const Color(0xFF1D1D1F),
                          ),
                        )
                      : null,
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}
