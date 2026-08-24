import 'package:flutter/material.dart';

/// 搜索框光晕聚焦效果组件。
///
/// 灵感来源：Inspira UI halo-search
/// 功能：搜索框聚焦时显示光晕动画效果，提升搜索体验。
///
/// 支持自定义光晕颜色、模糊半径、动画时长。
class HaloSearch extends StatefulWidget {
  /// 搜索框控制器。
  final TextEditingController? controller;

  /// 占位文本。
  final String hintText;

  /// 光晕颜色。
  final Color? haloColor;

  /// 光晕模糊半径。
  final double haloBlur;

  /// 光晕扩展半径。
  final double haloSpread;

  /// 动画时长。
  final Duration animationDuration;

  /// 聚焦时回调。
  final ValueChanged<bool>? onFocusChanged;

  /// 文本变化回调。
  final ValueChanged<String>? onChanged;

  /// 提交回调。
  final ValueChanged<String>? onSubmitted;

  /// 前置图标。
  final Widget? prefixIcon;

  /// 后置图标。
  final Widget? suffixIcon;

  /// 输入框填充色。
  final Color? fillColor;

  /// 边框圆角。
  final double borderRadius;

  const HaloSearch({
    super.key,
    this.controller,
    this.hintText = '搜索...',
    this.haloColor,
    this.haloBlur = 20.0,
    this.haloSpread = 4.0,
    this.animationDuration = const Duration(milliseconds: 300),
    this.onFocusChanged,
    this.onChanged,
    this.onSubmitted,
    this.prefixIcon,
    this.suffixIcon,
    this.fillColor,
    this.borderRadius = 28.0,
  });

  @override
  State<HaloSearch> createState() => _HaloSearchState();
}

class _HaloSearchState extends State<HaloSearch>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _haloAnimation;
  late final FocusNode _focusNode;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
    );
    _haloAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    final focused = _focusNode.hasFocus;
    if (focused != _isFocused) {
      setState(() => _isFocused = focused);
      if (focused) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
      widget.onFocusChanged?.call(focused);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final haloColor = widget.haloColor ?? theme.colorScheme.primary;

    return AnimatedBuilder(
      animation: _haloAnimation,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            boxShadow: [
              BoxShadow(
                color: haloColor.withValues(
                  alpha: 0.3 * _haloAnimation.value,
                ),
                blurRadius: widget.haloBlur * _haloAnimation.value,
                spreadRadius: widget.haloSpread * _haloAnimation.value,
              ),
            ],
          ),
          child: child,
        );
      },
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        decoration: InputDecoration(
          hintText: widget.hintText,
          filled: true,
          fillColor: widget.fillColor ?? theme.colorScheme.surfaceContainerHighest,
          prefixIcon: widget.prefixIcon ??
              Icon(Icons.search, color: theme.colorScheme.onSurfaceVariant),
          suffixIcon: widget.suffixIcon,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            borderSide: BorderSide(
              color: haloColor.withValues(alpha: 0.5),
              width: 1.5,
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 14,
          ),
        ),
      ),
    );
  }
}

/// 简化版搜索框组件（无光晕效果）。
///
/// 适用于不需要光晕动画的场景。
class SimpleSearch extends StatelessWidget {
  final TextEditingController? controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final Color? fillColor;
  final double borderRadius;

  const SimpleSearch({
    super.key,
    this.controller,
    this.hintText = '搜索...',
    this.onChanged,
    this.onSubmitted,
    this.prefixIcon,
    this.suffixIcon,
    this.fillColor,
    this.borderRadius = 28.0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return TextField(
      controller: controller,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        hintText: hintText,
        filled: true,
        fillColor: fillColor ?? theme.colorScheme.surfaceContainerHighest,
        prefixIcon: prefixIcon ??
            Icon(Icons.search, color: theme.colorScheme.onSurfaceVariant),
        suffixIcon: suffixIcon,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 14,
        ),
      ),
    );
  }
}
