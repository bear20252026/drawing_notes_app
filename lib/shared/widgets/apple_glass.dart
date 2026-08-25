// shared/widgets——AppleGlassWidget 毛玻璃容器（苹果 Liquid Glass——2026-08-22）。
//
// 用户需求：使用苹果的设计语言——毛玻璃/圆角/清爽——
// 借鉴 Excalidraw/excalidraw-cn/Saber/AFFiNE 的 UI 设计。
//
// 苹果 Liquid Glass（WWDC25——iOS 26/macOS Tahoe）：
// - 半透明毛玻璃（BackdropFilter blur——反射/折射周围内容）
// - 圆角（Liquid Glass 形状——12/20pt）
// - 高光边（顶部亮边——玻璃质感）+ 暗边（层次）
//
// 积木式独立 Widget——可插拔——不搞崩。
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:editor_core/editor_core.dart';

/// 苹果毛玻璃容器（Liquid Glass——半透明 + 模糊 + 圆角 + 高光边）。
///
/// 用法：把任意内容包进 AppleGlassWidget——获得苹果设计语言质感。
/// ```dart
/// AppleGlassWidget(
///   child: Text('内容'),
/// )
/// ```
class AppleGlassWidget extends StatelessWidget {
  const AppleGlassWidget({
    super.key,
    required this.child,
    this.blurRadius = 20.0,
    this.opacity = 0.72,
    this.cornerRadius = 12.0,
    this.showHighlight = true,
    this.color = Colors.white,
  });

  final Widget child;

  /// 毛玻璃模糊半径（Liquid Glass）。
  final double blurRadius;

  /// 毛玻璃表面不透明度。
  final double opacity;

  /// 圆角（Liquid Glass 形状）。
  final double cornerRadius;

  /// 是否显示高光边（顶部亮边——玻璃质感）。
  final bool showHighlight;

  /// 表面颜色（亮色——暗色模式由外部切换）。
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(cornerRadius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: blurRadius, sigmaY: blurRadius),
        child: Container(
          decoration: BoxDecoration(
            color: color.withValues(alpha: opacity),
            borderRadius: BorderRadius.circular(cornerRadius),
            // 注意：不用 Border（非 uniform 颜色与 borderRadius 冲突——
            // 高光/暗边用 Positioned 条实现——修复渲染异常）。
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            children: [
              child,
              // 顶部高光条（玻璃质感——Liquid Glass 高光）。
              if (showHighlight)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
                ),
              // 底部暗边（层次感——Depth）。
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 0.5,
                  color: Colors.black.withValues(alpha: 0.12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 苹果毛玻璃卡片（便捷工厂——AppleTheme 参数）。
  factory AppleGlassWidget.card({required Widget child}) {
    return AppleGlassWidget(
      child: child,
    );
  }

  /// 苹果毛玻璃工具栏（大圆角——Liquid Glass 控件）。
  factory AppleGlassWidget.toolbar({required Widget child}) {
    return AppleGlassWidget(
      opacity: 0.85,
      cornerRadius: AppleTheme.cornerRadiusLarge,
      child: child,
    );
  }
}
