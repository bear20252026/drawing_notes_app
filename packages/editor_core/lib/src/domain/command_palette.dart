// editor_core——CommandPalette 命令面板（Excalidraw 借鉴——2026-08-21）。
//
// Excalidraw Command Palette（4.2）本地化——键盘驱动命令面板。
// 纯 Dart 不可变模型——可独立测试——不搞崩。
//
// Excalidraw 原版参考：
// - 4.2 Command Palette——键盘快捷键触发命令面板
// - 命令注册表 + 快捷键映射 + 模糊搜索
library;

/// 命令优先级（Excalidraw Command Palette 借鉴）。
enum CommandPriority {
  /// 高频操作（撤销/重做/保存）。
  high,

  /// 中频操作（复制/粘贴/剪切）。
  medium,

  /// 低频操作（设置/帮助）。
  low,
}

/// 命令条目（Excalidraw Command 本地化——不可变）。
class CommandEntry {
  const CommandEntry({
    required this.id,
    required this.label,
    required this.action,
    this.shortcut = '',
    this.priority = CommandPriority.medium,
    this.category = '',
    this.keywords = const [],
  });

  final String id;
  final String label;
  final String action;
  final String shortcut;
  final CommandPriority priority;
  final String category;
  final List<String> keywords;

  /// 是否有快捷键。
  bool get hasShortcut => shortcut.isNotEmpty;

  /// 匹配搜索关键词（模糊匹配——Excalidraw 模式）。
  bool matches(String query) {
    if (query.isEmpty) return true;
    final lower = query.toLowerCase();
    if (label.toLowerCase().contains(lower)) return true;
    if (category.toLowerCase().contains(lower)) return true;
    return keywords.any((k) => k.toLowerCase().contains(lower));
  }

  CommandEntry copyWith({String? label, String? shortcut, CommandPriority? priority, String? category}) {
    return CommandEntry(
      id: id,
      label: label ?? this.label,
      action: action,
      shortcut: shortcut ?? this.shortcut,
      priority: priority ?? this.priority,
      category: category ?? this.category,
      keywords: keywords,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is CommandEntry && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// 命令面板（Excalidraw Command Palette 本地化——积木式纯 Dart）。
///
/// 功能：
/// - 命令注册表（add/remove/get）
/// - 快捷键映射（shortcut → command）
/// - 模糊搜索（label/category/keywords）
/// - 执行命令（execute）
class CommandPalette {
  const CommandPalette({this.commands = const []});

  final List<CommandEntry> commands;

  /// 注册命令。
  CommandPalette add(CommandEntry command) {
    return CommandPalette(commands: [...commands, command]);
  }

  /// 移除命令。
  CommandPalette remove(String commandId) {
    return CommandPalette(commands: commands.where((c) => c.id != commandId).toList());
  }

  /// 获取命令。
  CommandEntry? get(String commandId) {
    return commands.where((c) => c.id == commandId).firstOrNull;
  }

  /// 快捷键查找命令（Excalidraw shortcut mapping）。
  CommandEntry? getByShortcut(String shortcut) {
    return commands.where((c) => c.shortcut == shortcut).firstOrNull;
  }

  /// 模糊搜索（Excalidraw Command Palette 搜索）。
  List<CommandEntry> search(String query) {
    if (query.isEmpty) return commands;
    return commands.where((c) => c.matches(query)).toList();
  }

  /// 按分类过滤。
  List<CommandEntry> byCategory(String category) {
    return commands.where((c) => c.category == category).toList();
  }

  /// 按优先级排序（Excalidraw 优先级排序）。
  List<CommandEntry> sortedByPriority() {
    final sorted = List<CommandEntry>.from(commands);
    sorted.sort((a, b) => a.priority.index.compareTo(b.priority.index));
    return sorted;
  }

  int get count => commands.length;
  bool get isEmpty => commands.isEmpty;

  CommandPalette copyWith({List<CommandEntry>? commands}) {
    return CommandPalette(commands: commands ?? this.commands);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is CommandPalette && count == other.count;

  @override
  int get hashCode => count.hashCode;
}
