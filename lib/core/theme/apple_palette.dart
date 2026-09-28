import 'package:flutter/material.dart';

import 'package:drawing_notes_app/core/theme/apple_design.dart';

/// 画笔色板域常量（D-06/D-07 收编，审计 2026-09-28）。
///
/// 单一事实来源：
/// - [preset]：12 色预设色板——ColorPickerDialog 色板与画笔取色共用；
/// - 工具默认色：pen / pencil / marker / laser 四件，BrushPresetBook
///   默认档引用。
///
/// 放 core/theme 而非 features/drawing：ColorPickerDialog 在 shared，
/// 边界规则禁止 shared→features，core 双方可依赖。
abstract final class ApplePalette {
  /// 12 色预设色板（顺序即展示顺序）。
  static const List<Color> preset = <Color>[
    Color(0xFF1A1A1A), // 黑
    Color(0xFF555555), // 深灰
    Color(0xFF8B8B8B), // 中灰
    AppleColor.surfaceWhite, // 白
    Color(0xFFD32F2F), // 红
    Color(0xFFFF7043), // 橙
    Color(0xFFFBC02D), // 黄
    Color(0xFF388E3C), // 绿
    Color(0xFF00897B), // 青
    Color(0xFF1976D2), // 蓝
    Color(0xFF7B1FA2), // 紫
    Color(0xFFC2185B), // 粉
  ];

  /// 画笔（pen）默认色——纯黑墨。
  static const Color brushPen = Color(0xFF1A1A1A);

  /// 铅笔（pencil）默认色——深灰，弱于墨线。
  static const Color brushPencil = Color(0xFF424242);

  /// 马克笔（marker）默认色——浅黄高亮感。
  static const Color brushMarker = Color(0xFFFFD54F);
}
