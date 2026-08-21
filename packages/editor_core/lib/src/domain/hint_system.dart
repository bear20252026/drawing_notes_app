// editor_core——HintSystem 提示帮助系统（Excalidraw 4.6 借鉴——2026-08-21）。
//
// Excalidraw 4.6 Hints and Help System 本地化——上下文提示/快捷键帮助。
// 纯 Dart 不可变模型——可独立测试——不搞崩。
//
// Excalidraw 原版参考：
// - 4.6 Hints and Help System——根据当前工具/状态显示提示
// - 上下文提示（选择工具时显示可用快捷键）
// - 工具提示（鼠标悬停显示说明）
// - 帮助面板（所有快捷键/操作说明）
library;

/// 提示类型（Excalidraw Hints 借鉴）。
enum HintType {
  /// 工具提示（鼠标悬停）。
  tooltip,

  /// 上下文提示（当前工具/状态相关）。
  context,

  /// 快捷键提示（键盘快捷键）。
  shortcut,

  /// 操作提示（下一步操作建议）。
  action,
}

/// 提示条目（Excalidraw Hint 本地化——不可变）。
class Hint {
  const Hint({
    required this.id,
    required this.message,
    this.type = HintType.context,
    this.shortcut = '',
    this.tool = '',
    this.priority = 0,
    this.duration = 0, // 0 = 持续显示。
  });

  final String id;
  final String message;
  final HintType type;
  final String shortcut;
  final String tool; // 关联的工具（draw/select/shape 等）。
  final int priority; // 优先级（高优先级先显示）。
  final int duration; // 显示时长（毫秒——0=持续）。

  /// 是否有快捷键。
  bool get hasShortcut => shortcut.isNotEmpty;

  /// 是否与指定工具相关。
  bool isForTool(String toolName) => tool.isEmpty || tool == toolName;

  Hint copyWith({
    String? message,
    HintType? type,
    String? shortcut,
    String? tool,
    int? priority,
    int? duration,
  }) {
    return Hint(
      id: id,
      message: message ?? this.message,
      type: type ?? this.type,
      shortcut: shortcut ?? this.shortcut,
      tool: tool ?? this.tool,
      priority: priority ?? this.priority,
      duration: duration ?? this.duration,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Hint && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// 提示系统（Excalidraw Hints and Help System 本地化——积木式纯 Dart）。
///
/// 功能：
/// - 注册提示（add/remove）
/// - 按工具过滤（hintsForTool）
/// - 按类型过滤（hintsByType）
/// - 优先级排序（sortedByPriority）
/// - 帮助面板（所有快捷键/操作说明）
class HintSystem {
  const HintSystem({this.hints = const []});

  final List<Hint> hints;

  /// 注册提示。
  HintSystem add(Hint hint) {
    return HintSystem(hints: [...hints, hint]);
  }

  /// 移除提示。
  HintSystem remove(String hintId) {
    return HintSystem(hints: hints.where((h) => h.id != hintId).toList());
  }

  /// 获取指定工具的提示（Excalidraw context hints）。
  List<Hint> hintsForTool(String tool) {
    return hints.where((h) => h.isForTool(tool)).toList();
  }

  /// 按类型过滤。
  List<Hint> hintsByType(HintType type) {
    return hints.where((h) => h.type == type).toList();
  }

  /// 按优先级排序（高优先级先显示）。
  List<Hint> sortedByPriority() {
    final sorted = List<Hint>.from(hints);
    sorted.sort((a, b) => b.priority.compareTo(a.priority));
    return sorted;
  }

  /// 获取帮助面板内容（所有快捷键/操作——Excalidraw help panel）。
  List<Hint> helpPanel() {
    return hints.where((h) => h.hasShortcut).toList();
  }

  /// 搜索提示（模糊匹配 message）。
  List<Hint> search(String query) {
    if (query.isEmpty) return hints;
    final lower = query.toLowerCase();
    return hints.where((h) => h.message.toLowerCase().contains(lower)).toList();
  }

  int get count => hints.length;
  bool get isEmpty => hints.isEmpty;

  HintSystem copyWith({List<Hint>? hints}) {
    return HintSystem(hints: hints ?? this.hints);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is HintSystem && count == other.count;

  @override
  int get hashCode => count.hashCode;
}
