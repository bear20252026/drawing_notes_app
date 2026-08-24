// editor_core——MarkdownShortcutService（AFFiNE Markdown 快捷借鉴——2026-08-22）。
//
// AFFiNE Markdown 支持：# 标题/- 列表/[] todo/> 引用/``` 代码——输入快捷转换。
// 本地化：# 标题/- 列表/[] todo——Word 式打字增强。
// 纯 Dart 不可变——可独立测试——不搞崩。
//
// 版权：AFFiNE（BSL 1.1——BlockSuite MIT）——仅概念借鉴——NOTICE 已记录。
library;

import 'slash_command.dart';

/// Markdown 解析结果（不可变——输入行 → 块类型 + 内容）。
class MarkdownParseResult {
  const MarkdownParseResult({required this.blockType, required this.content});

  final SlashBlockType blockType; // heading/list/todo 或 paragraph。
  final String content; // 去前缀后的内容。

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MarkdownParseResult && blockType == other.blockType && content == other.content;

  @override
  int get hashCode => Object.hash(blockType, content);
}

/// Markdown 快捷服务（输入行解析——积木式纯 Dart）。
///
/// AFFiNE Markdown 快捷：
/// - `# 标题` → heading（## 三级——### 三级）
/// - `- 列表` / `* 列表` → list（bullet）
/// - `[] todo` / `[x] 完成` → todo（checkbox）
/// - 其他 → paragraph（正文）
class MarkdownShortcutService {
  const MarkdownShortcutService();

  /// 解析一行（Markdown 快捷 → 块类型 + 内容）。
  MarkdownParseResult parse(String line) {
    // 标题（# 开头——最多 3 级）。
    final heading = RegExp(r'^(#{1,3})\s+(.+)$').firstMatch(line);
    if (heading != null) {
      return MarkdownParseResult(
        blockType: SlashBlockType.heading,
        content: heading.group(2)!,
      );
    }

    // 待办（[] / [x] / [ ]——空括号也匹配）。
    final todo = RegExp(r'^\[([ xX]?)\]\s*(.+)$').firstMatch(line);
    if (todo != null) {
      return MarkdownParseResult(
        blockType: SlashBlockType.list,
        content: todo.group(2)!,
      );
    }

    // 列表（- / * 开头）。
    final list = RegExp(r'^[-*]\s+(.+)$').firstMatch(line);
    if (list != null) {
      return MarkdownParseResult(
        blockType: SlashBlockType.list,
        content: list.group(1)!,
      );
    }

    // 正文。
    return MarkdownParseResult(blockType: SlashBlockType.paragraph, content: line);
  }

  /// 是否标题行（# 开头）。
  static bool isHeading(String line) => line.trimLeft().startsWith('#');

  /// 是否列表行（- / * 开头）。
  static bool isList(String line) {
    final t = line.trimLeft();
    return t.startsWith('- ') || t.startsWith('* ');
  }

  /// 是否待办行（[] / [x] / [ ] 开头）。
  static bool isTodo(String line) => RegExp(r'^\[[ xX]?\]').hasMatch(line.trimLeft());
}
