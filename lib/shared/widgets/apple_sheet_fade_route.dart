import 'package:flutter/material.dart';

import 'package:drawing_notes_app/core/theme/apple_motion.dart';

/// sheet + 淡入转场路由（审计三-8，2026-09-06）。
///
/// 页卡 → 编辑器的入厂转场：`AppleMotion.sheet`（300ms）+ `easeSheet`
/// 曲线，配合淡入、自 0.96 起始缩放与 4% 高度的轻上升（fade-through 语义
/// 的单路由近似——替换平台默认转场）。退场 250ms（toastOut 档）。
///
/// 合规要点：只动 transform/opacity；无 ease-in；减弱动效三信号
/// （motion / transparency / contrast）→ 只保留交叉淡入（更少更轻，非零）。
class AppleSheetFadeRoute<T> extends PageRouteBuilder<T> {
  AppleSheetFadeRoute({required WidgetBuilder builder, super.settings})
    : super(
        transitionDuration: AppleMotion.sheet,
        reverseTransitionDuration: AppleMotion.toastOut,
        pageBuilder: (context, animation, secondaryAnimation) =>
            builder(context),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: AppleMotion.easeSheet,
            reverseCurve: AppleMotion.easeOut,
          );
          if (AppleMotion.reduceMotionOf(context)) {
            return FadeTransition(opacity: curved, child: child);
          }
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.04),
                end: Offset.zero,
              ).animate(curved),
              child: ScaleTransition(
                scale: Tween<double>(
                  begin: AppleMotion.enterScale,
                  end: 1,
                ).animate(curved),
                child: child,
              ),
            ),
          );
        },
      );
}
