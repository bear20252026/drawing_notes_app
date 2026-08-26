// notes — Presentation 层：Apple 风格搜索栏组件
// 从 home_page.dart 拆出（Clean Architecture：UI 组件独立）

import 'package:flutter/material.dart';

import '../../../../core/theme/app_design.dart';

/// Apple 风格搜索栏（iOS 15+ 圆角矩形搜索框）
///
/// 视觉特征：
/// - 圆角矩形（borderRadius 10）
/// - 背景：systemGray6（浅色 #F2F2F7 / 深色 #2C2C2E）
/// - 放大镜图标 + 占位符文本
/// - 点击后触发 onTap 回调
class AppleSearchBar extends StatelessWidget {
  const AppleSearchBar({super.key, required this.onTap, this.hintText});

  /// 点击回调
  final VoidCallback onTap;

  /// 占位符文本（可选）
  final String? hintText;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark
        ? const Color(0xFF2C2C2E)
        : const Color(0xFFF2F2F7);
    final hintColor = isDark
        ? const Color(0xFF8E8E93)
        : const Color(0xFF8E8E8E);
    final iconColor = isDark
        ? const Color(0xFF8E8E93)
        : const Color(0xFF8E8E8E);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44, // DESIGN.md: 44px search-input height
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(AppDesign.roundedPill),
        ),
        padding: const EdgeInsets.symmetric(horizontal: AppDesign.spacingSm),
        child: Row(
          children: [
            Icon(Icons.search, size: 18, color: iconColor),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                hintText ?? '搜索',
                style: AppDesign.body.copyWith(color: hintColor, fontSize: 17),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
