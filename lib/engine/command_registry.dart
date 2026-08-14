import 'package:flutter/foundation.dart';

/// 编辑器命令的任务类别。
///
/// 分类只用于命令面板与快捷键帮助的可扫描呈现，不影响命令执行。
enum EditorCommandCategory {
  edit('编辑'),
  format('格式'),
  insert('插入'),
  arrange('排列'),
  view('视图'),
  export('导出');

  const EditorCommandCategory(this.label);

  final String label;
}

/// 与具体 UI 入口无关的编辑器动作契约。
///
/// 结构借鉴 Excalidraw 的 Action：同一命令可由菜单、工具栏、快捷键或
/// 命令面板调用；可用性由同一个谓词决定，避免各入口出现不同结果。
class EditorCommand {
  const EditorCommand({
    required this.id,
    required this.label,
    this.category = EditorCommandCategory.edit,
    this.keywords = const [],
    this.shortcut = '',
    this.isAvailable,
    this.run,
  });

  final String id;
  final String label;
  final EditorCommandCategory category;
  final List<String> keywords;

  /// 给用户展示的平台中立快捷键文本，例如 `Ctrl/Cmd+Shift+P`。
  final String shortcut;

  /// 当前编辑器状态下是否可执行。未提供时表示始终可用。
  final bool Function()? isAvailable;

  /// 命令执行回调（由编辑器页面提供闭包）。
  final VoidCallback? run;

  bool get available => isAvailable?.call() ?? true;

  /// 若命令当前不可用或没有执行器则返回 false，不制造无效反馈。
  bool execute() {
    if (!available || run == null) return false;
    run!.call();
    return true;
  }

  /// 用于命令面板的轻量匹配；中文保留原字符，英文忽略大小写。
  bool matchesQuery(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    final haystack = <String>[
      label,
      category.label,
      ...keywords,
    ].join(' ').toLowerCase();
    return haystack.contains(normalized);
  }
}

/// 命令注册表：集中管理编辑器操作。
///
/// 不保存编辑器状态；每个命令用闭包在执行时读取最新状态，使工具栏、
/// 主菜单、快捷键和命令面板共享同一可用性与副作用。
class CommandRegistry {
  final List<EditorCommand> _commands = [];

  /// 注册一条命令（已存在同 id 则覆盖，并保留原位置）。
  void register(EditorCommand command) {
    final index = _commands.indexWhere((item) => item.id == command.id);
    if (index >= 0) {
      _commands[index] = command;
    } else {
      _commands.add(command);
    }
  }

  /// 全部已注册命令（保持注册顺序）。
  List<EditorCommand> get commands => List.unmodifiable(_commands);

  /// 当前状态下可执行的命令；命令面板只展示该列表。
  List<EditorCommand> get availableCommands =>
      List.unmodifiable(_commands.where((command) => command.available));

  /// 按 id 查找命令。
  EditorCommand? find(String id) {
    for (final command in _commands) {
      if (command.id == id) return command;
    }
    return null;
  }

  /// 执行命令并报告是否真正执行，供快捷键调度决定是否消费事件。
  bool run(String id) => find(id)?.execute() ?? false;

  /// 获取当前可执行且匹配查询的命令。
  List<EditorCommand> search(String query) => List.unmodifiable(
    availableCommands.where((command) => command.matchesQuery(query)),
  );
}
