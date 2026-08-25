// editor_core——SlashCommandService（AFFiNE BlockSuite Slash 命令借鉴——2026-08-22）。
//
// AFFiNE Slash 命令（/ 键——双栏菜单——插入块：段落/标题/列表/引用/代码）。
// 本地化：/ 键输入 → 命令匹配 → 插入块类型——Word 式打字增强。
// 纯 Dart 不可变——可独立测试——不搞崩。
//
// 版权：AFFiNE（BSL 1.1——BlockSuite MIT）——仅概念借鉴——NOTICE 已记录。
library;

/// 块类型（/ 键菜单——AFFiNE 块类型本地化）。
enum SlashBlockType {
  paragraph, // 段落。
  heading,   // 标题。
  list,      // 列表。
  quote,     // 引用。
  code,      // 代码。
  divider,   // 分隔线。
}

/// 块命令（/ 键菜单项——不可变）。
class SlashCommand {
  const SlashCommand({
    required this.type,
    required this.name,
    required this.keyword,
    this.icon = '',
  });

  final SlashBlockType type;
  final String name; // 显示名（中文）。
  final String keyword; // 匹配关键词（/ 后输入）。
  final String icon; // 图标（emoji——简化）。

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is SlashCommand && type == other.type;

  @override
  int get hashCode => type.hashCode;
}

/// Slash 命令服务（/ 键解析——积木式纯 Dart）。
///
/// AFFiNE BlockSuite：/ 键打开块菜单——输入关键词过滤——选择插入块。
/// 本地化：/ 后输入（如 /标题）→ 匹配命令 → 块类型。
class SlashCommandService {
  const SlashCommandService();

  /// 全部命令（/ 键菜单——段落/标题/列表/引用/代码/分隔线）。
  static const List<SlashCommand> commands = [
    SlashCommand(type: SlashBlockType.paragraph, name: '段落', keyword: '段落 para p', icon: '📄'),
    SlashCommand(type: SlashBlockType.heading, name: '标题', keyword: '标题 heading h', icon: '🔠'),
    SlashCommand(type: SlashBlockType.list, name: '列表', keyword: '列表 list l', icon: '📋'),
    SlashCommand(type: SlashBlockType.quote, name: '引用', keyword: '引用 quote q', icon: '💬'),
    SlashCommand(type: SlashBlockType.code, name: '代码', keyword: '代码 code c', icon: '💻'),
    SlashCommand(type: SlashBlockType.divider, name: '分隔线', keyword: '分隔线 divider d', icon: '➖'),
  ];

  /// 判断输入是否为 Slash 命令（以 / 开头）。
  static bool isSlash(String input) => input.startsWith('/');

  /// 匹配命令（/ 后输入关键词——模糊匹配——返回最佳命令）。
  SlashCommand? match(String input) {
    if (!isSlash(input)) return null;
    final query = input.substring(1).trim().toLowerCase();
    if (query.isEmpty) return null;

    for (final cmd in commands) {
      final keywords = cmd.keyword.toLowerCase().split(' ');
      if (keywords.contains(query)) return cmd;
    }
    return null;
  }

  /// 搜索命令（/ 后输入——模糊匹配列表——AFFiNE 双栏菜单过滤）。
  List<SlashCommand> search(String input) {
    if (!isSlash(input)) return const [];
    final query = input.substring(1).trim().toLowerCase();
    if (query.isEmpty) return commands;

    return commands.where((cmd) {
      final keywords = cmd.keyword.toLowerCase().split(' ');
      return keywords.any((k) => k.contains(query)) ||
          cmd.name.toLowerCase().contains(query);
    }).toList();
  }
}
