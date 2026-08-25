part of 'editor_page.dart';

/// 编辑器状态变量与计算属性（拆分自 editor_page.dart 主类）。
///
/// extension 不能声明实例字段——本文件包含在主类中声明的字段与 getter，
/// 仅供编辑器主类及其兄弟 part 文件使用。
///
/// 说明：由于 Dart 的 `part` 机制，extension 无法声明实例字段，
/// 所以这些字段仍需在主类中声明。本文件仅作为逻辑分组的索引，
/// 记录 editor_page.dart 中第 113~380 行的状态变量与 getter 所属域。
/// 当前未实际拆分，保留此文件作为后续优化的占位。
///
/// TODO(01a0333c): 将编辑器 UI 拆分为独立 Widget 时，
/// 可以把状态提升到独立的 StateNotifier/Riverpod，
/// 从而真正移除主类中的大量字段。
