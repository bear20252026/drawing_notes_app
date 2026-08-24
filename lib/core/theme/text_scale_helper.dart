import 'package:flutter/material.dart';

/// 文本缩放辅助工具（WCAG 1.4.4 合规）。
///
/// 将硬编码 fontSize 通过 MediaQuery.textScalerOf 转换为系统缩放后的值。
/// 最大缩放倍数限制为 2.0x，防止布局溢出。
///
/// 使用方式：
/// ```dart
/// // 替换前
/// Text('标题', style: TextStyle(fontSize: 18))
///
/// // 替换后
/// Text('标题', style: TextStyle(fontSize: TextScaleHelper.scaled(context, 18)))
/// ```
class TextScaleHelper {
  TextScaleHelper._();

  /// 根据系统文本缩放比例调整字号（最大 2.0x）。
  static double scaled(BuildContext context, double baseFontSize) {
    final scaler = MediaQuery.textScalerOf(context);
    return scaler.scale(baseFontSize).clamp(
      baseFontSize * 0.8, // 最小 0.8x（防止过小）
      baseFontSize * 2.0, // 最大 2.0x（WCAG AAA 级）
    );
  }

  /// 创建缩放后的 TextStyle。
  static TextStyle style(
    BuildContext context, {
    required double fontSize,
    FontWeight? fontWeight,
    Color? color,
    String? fontFamily,
    double? letterSpacing,
    double? height,
    TextDecoration? decoration,
  }) {
    return TextStyle(
      fontSize: scaled(context, fontSize),
      fontWeight: fontWeight,
      color: color,
      fontFamily: fontFamily,
      letterSpacing: letterSpacing,
      height: height,
      decoration: decoration,
    );
  }
}
