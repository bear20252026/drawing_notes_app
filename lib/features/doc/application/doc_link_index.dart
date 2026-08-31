// 由 Claude 团队生成 | Drawing Notes App
// 文档双链索引（M12.7，AFFiNE Backlinks 对齐）。
//
// 语法：正文中的 `[[标题]]` 表示指向标题匹配文档的页面引用。
// 约定：
// - 纯 Dart，无 IO / 无 flutter 依赖（domain 级纯逻辑，可单测）；
// - 索引不持久化：每次从文档集合推导（数据即索引，永不失同步——
//   这是对"反向链接必须与内容一致"的根本保障）；
// - 重命名安全：解析时按"当前标题"匹配，旧文中的 [[旧标题]] 在文档
//   改名后自然失配（v1 语义；id 化引用留待后续版本升级）。

import 'package:drawing_notes_app/features/doc/domain/note_block.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block_doc.dart';

/// 页面引用语法：`[[标题]]`。
final RegExp docLinkPattern = RegExp(r'\[\[([^\[\]]+)\]\]');

/// 从块及其子块中提取全部链接文本（不含括号），保持出现顺序。
void collectLinksFromBlock(NoteBlock block, List<String> out) {
  out.addAll(
    docLinkPattern
        .allMatches(block.text)
        .map((m) => m.group(1)!)
        .where((t) => t.trim().isNotEmpty),
  );
  for (final child in block.children) {
    collectLinksFromBlock(child, out);
  }
}

/// 提取文档的全部出链标题（去重，保持顺序）。
List<String> extractOutLinks(NoteBlockDoc doc) {
  final out = <String>[];
  for (final block in doc.body) {
    collectLinksFromBlock(block, out);
  }
  return out.toSet().toList();
}

/// 构建反向链接索引：目标标题 → 引用它的文档 id 列表（按 updatedAt 倒序）。
Map<String, Set<String>> buildBacklinkIndex(List<NoteBlockDoc> docs) {
  final index = <String, Set<String>>{};
  for (final doc in docs) {
    for (final link in extractOutLinks(doc)) {
      index.putIfAbsent(link, () => <String>{}).add(doc.id);
    }
  }
  return index;
}

/// 返回引用了 [target] 的文档列表（标题或 id 匹配），按更新时间倒序。
List<NoteBlockDoc> backlinksOf(
  NoteBlockDoc target,
  List<NoteBlockDoc> allDocs,
) {
  final linked = <NoteBlockDoc>[];
  for (final doc in allDocs) {
    if (doc.id == target.id) continue; // 不含自身
    final links = extractOutLinks(doc);
    final hit = links.any((l) => l == target.title || l == target.id);
    if (hit) linked.add(doc);
  }
  linked.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return linked;
}

/// 返回 [source] 文档的出链目标文档（按标题/id 解析，解析失败的跳过），
/// 按 updatedAt 倒序。
List<NoteBlockDoc> outgoingLinksOf(
  NoteBlockDoc source,
  List<NoteBlockDoc> allDocs,
) {
  final byTitle = {for (final d in allDocs) d.title: d};
  final byId = {for (final d in allDocs) d.id: d};
  final result = <NoteBlockDoc>[];
  final seen = <String>{};
  for (final raw in extractOutLinks(source)) {
    final target = byId[raw] ?? byTitle[raw];
    if (target == null || target.id == source.id) continue;
    if (seen.add(target.id)) result.add(target);
  }
  result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return result;
}

/// 规范化引用文本：插入时统一写成 `[[标题]]`。
String formatDocLink(NoteBlockDoc target) => '[[${target.title}]]';
