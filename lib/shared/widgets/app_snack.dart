import 'package:flutter/material.dart';

// ============================================================================
// app_snack.dart —— 轻量 Snack 反馈（去重收敛 2026-09-07）
// ============================================================================
//
// 此前 7 个页面的私有 _snack/_showSnack 逐字节相同（mounted 守卫 + 默认
// SnackBar）。收敛为唯一入口；各页面私有方法保留为薄委托（签名不变，
// 调用点零改动）。
//
// mounted 守卫留在调用方 State 的私有方法里：State.mounted 与本工具
// 收到的 context 的生命周期由调用方保证，工具本身不做隐式守卫。

/// 全局轻量反馈通道：默认样式 SnackBar（宽度/时长/行为与原各页面
/// 私有实现完全一致——Material 默认时长与宽度，无 action）。
class AppSnack {
  AppSnack._();

  static void show(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
