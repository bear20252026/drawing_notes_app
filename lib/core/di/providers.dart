import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_design.dart';

/// Riverpod 状态管理骨架（S5 落地，2026 官方推荐模式）。
///
/// 原则（riverpod.dev 官方）：
/// - Provider 是**顶层 final 不可变**声明（类似函数声明，可测试可维护）
/// - 编译时安全：provider 类型在编译期解析，拼写错误即编译失败
/// - 可测试：ProviderContainer 可独立构建，provider 可用 override 替换
///
/// 当前最小落地：主题 provider 作为首个示例，验证管线打通；
/// 既有 ChangeNotifier（DrawingController/EditorViewModel）按 S5 后续
/// 迭代逐步迁移为 Notifier/AsyncNotifier，不一次大规模替换（不冒险）。
final themeProvider = Provider<ThemeData>((ref) => AppDesign.lightTheme());

/// 主题模式（深色/浅色）状态——供 UI 层 ref.watch 驱动。
final darkModeProvider = StateProvider<bool>((ref) => false);
