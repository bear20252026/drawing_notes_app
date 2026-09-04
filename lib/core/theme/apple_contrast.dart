import 'package:flutter/material.dart';

/// 对比度档位（平台域裁决 C2，2026-09-04）。
///
/// **权威**：Microsoft win-dev-skills（Windows 高对比度主题规范）。
///
/// 对比度与明暗不是同一个维度：明暗决定「亮还是暗」，对比度决定
/// 「看不看得清」。Windows 用户在系统设置里开启高对比度后，应用必须
/// 提供**第三套**配色——否则本项目的发丝线（8% 黑）、次要文字
/// （`onSurfaceVariant`）、卡片边框会淡到几乎看不见，而这些恰恰是
/// 本项目表达层级的主要手段（见 `AppleHairline` 的设计说明）。
///
/// 按 `docs/DESIGN_SYSTEM.md` 的分权模型，这属于**平台行为域**，
/// `DESIGN.md` 对该域表决权为零（它只管色/字/间距/圆角），所以这里
/// 可以直接把边框推到 100% 不透明，不违反「克制的苹果风」——
/// 无障碍档位下可读性优先于风格。
enum AppleContrast {
  /// 常规：发丝线 8%（亮）/ 12%（暗），遵循 DESIGN.md:395。
  normal,

  /// 高对比度：边框与分割线 100% 不透明，文字纯黑 / 纯白。
  high;

  /// 读取平台的高对比度设置。
  ///
  /// **不能用 `MediaQuery.highContrastOf(context)`**：本方法要在
  /// `MaterialApp` 之上调用（主题要在 MaterialApp 构造时就确定），
  /// 而那个位置还没有 MediaQuery 可用。因此直接从 [View] 读平台属性。
  static AppleContrast of(BuildContext context) {
    final data = MediaQueryData.fromView(View.of(context));
    return data.highContrast ? AppleContrast.high : AppleContrast.normal;
  }

  /// 把「用户覆盖值」与平台值合并成最终档位。
  ///
  /// [override] 为 null 表示「跟随系统」。
  static AppleContrast resolve({
    required bool? override,
    required AppleContrast platform,
  }) {
    if (override == null) return platform;
    return override ? AppleContrast.high : AppleContrast.normal;
  }
}
