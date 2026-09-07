import 'package:flutter/material.dart';

import 'package:drawing_notes_app/core/theme/apple_design.dart';

/// 内容工作区的低对比环境背景。
///
/// 仅用于资料库与列表等导航场景，为局部玻璃控制层提供自然的明暗参照；
/// 编辑器画布与纸张内容保持独立，不使用该背景以避免影响创作判断。
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          // 渐变色已收编为 AppleColor 令牌（页面禁写字面量）。
          colors: isDark
              ? AppleColor.ambientDarkGradient
              : AppleColor.ambientLightGradient,
          stops: const [0, 0.52, 1],
        ),
      ),
      child: child,
    );
  }
}
