import 'package:flutter/material.dart';

import 'package:drawing_notes_app/l10n/app_localizations.dart';

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

  /// 侧车注册表「读不出来 → 覆盖前已另存一份原件」的可见回执
  /// （STO-004 / DOC-12 乙，业主 2026-10-16 点名）。
  ///
  /// 为什么收在这里而不是各页面自己拼句子：标签注册表与收藏集合是**同一个形状**，
  /// 本仓头号复发形态就是「一份判据 N 份副本」。两个 store 只负责给出事实
  /// （`salvagedOriginalName`），说出来这件事只有这一处定义。
  /// [salvagedName] 为 null（正常路径）时**什么都不说**——反向锁：不许把好消息据成事故。
  static void showSidecarSalvage(
    BuildContext context,
    String? salvagedName,
  ) {
    if (salvagedName == null) return;
    show(
      context,
      AppLocalizations.of(context)?.sidecarOriginalKept(salvagedName) ??
          '旧内容读不出来，已另存一份原件（$salvagedName），本次覆盖没有删掉它。',
    );
  }
}
