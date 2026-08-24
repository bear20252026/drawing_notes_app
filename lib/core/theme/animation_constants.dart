import 'package:flutter/material.dart';

/// 全局动画曲线常量。
///
/// 统一应用内所有动画的曲线选择，避免各处随意使用不同 Curves 导致
/// 视觉体验不一致。
class AppAnimation {
  AppAnimation._();

  /// 快速响应动画（工具切换、按钮反馈、微交互）。
  /// 对标 Material 3 quickMotion：200ms + easeOutCubic。
  static const Curve quickMotion = Curves.easeOutCubic;
  static const Duration quickDuration = Duration(milliseconds: 200);

  /// 标准过渡动画（页面切换、面板展开/收起、布局变化）。
  /// 对标 Material 3 standardMotion：300ms + easeInOutCubic。
  static const Curve standardMotion = Curves.easeInOutCubic;
  static const Duration standardDuration = Duration(milliseconds: 300);

  /// 缓慢动画（复杂过渡、全屏展开）。
  static const Curve slowMotion = Curves.easeInOut;
  static const Duration slowDuration = Duration(milliseconds: 500);
}
