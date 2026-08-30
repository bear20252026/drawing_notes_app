// 由 Claude 团队生成 | Drawing Notes App
// Markdown 导出（M12.5，AFFiNE Export 对齐）：
// NoteBlockDoc → Markdown 纯文本转换。纯 Dart，无 IO 依赖，可单测。

import 'package:drawing_notes_app/features/notes/domain/note_block.dart';
import 'package:drawing_notes_app/features/notes/domain/note_block_doc.dart';

/// 将块文档转换为 Markdown 文本。
///
/// - 标题按 level 输出 #；待办输出 - [x]/- [ ]；有序列表按序号；
/// - 引用/提示（callout）输出 >；代码块输出 ``` 围栏；
/// - 分割线输出 ---；画布/图表/表格/数据库等嵌入块输出占位注释；
/// - 空文档兜底输出空段落。
String noteBlockDocToMarkdown(NoteBlockDoc doc) {
  final buf = StringBuffer();
  final title = doc.title.trim().isEmpty ? '未命名' : doc.title.trim();
  buf.writeln('# $title');
  buf.writeln();

  var orderedIndex = 0;
  var firstBlock = true;

  void writeBlock(NoteBlock b, int indentLevel) {
    final indent = '  ' * indentLevel;
    String line;
    switch (b.type) {
      case NoteBlockType.heading:
        final level = ((b.props['level'] as int?) ?? 1).clamp(1, 6);
        line = '${'#' * level} ${b.text}';
        orderedIndex = 0;
      case NoteBlockType.todo:
        final checked = b.props['checked'] == true;
        line = '$indent- ${checked ? '[x]' : '[ ]'} ${b.text}';
        orderedIndex = 0;
      case NoteBlockType.bullet:
        line = '$indent- ${b.text}';
        orderedIndex = 0;
      case NoteBlockType.ordered:
        orderedIndex++;
        line = '$indent$orderedIndex. ${b.text}';
      case NoteBlockType.quote:
        line = '> ${b.text}';
        orderedIndex = 0;
      case NoteBlockType.callout:
        line = '> [!NOTE]\n> ${b.text}';
        orderedIndex = 0;
      case NoteBlockType.code:
        final lang = (b.props['language'] as String?) ?? '';
        line = '```$lang\n${b.text}\n```';
        orderedIndex = 0;
      case NoteBlockType.divider:
        line = '---';
        orderedIndex = 0;
      case NoteBlockType.image:
        final alt = (b.props['alt'] as String?) ?? 'image';
        line = '![$alt](embed)';
        orderedIndex = 0;
      case NoteBlockType.link:
        line = '[${b.text.isEmpty ? '链接' : b.text}](url)';
        orderedIndex = 0;
      case NoteBlockType.canvas:
        line = '<!-- 内嵌画布：${b.text.isEmpty ? '（无标题）' : b.text} -->';
        orderedIndex = 0;
      case NoteBlockType.chart:
        line = '<!-- 内嵌图表 -->';
        orderedIndex = 0;
      case NoteBlockType.table:
        line = '<!-- 内嵌表格 -->';
        orderedIndex = 0;
      case NoteBlockType.database:
        line = '<!-- 内嵌数据库视图 -->';
        orderedIndex = 0;
      case NoteBlockType.attachment:
        line = '<!-- 附件：${b.text.isEmpty ? '（未命名）' : b.text} -->';
        orderedIndex = 0;
      case NoteBlockType.text:
        line = '$indent${b.text}';
        orderedIndex = 0;
    }
    if (!firstBlock) buf.writeln();
    buf.writeln(line);
    firstBlock = false;
    for (final child in b.children) {
      writeBlock(child, indentLevel + 1);
    }
  }

  for (final block in doc.body) {
    writeBlock(block, 0);
  }
  return buf.toString();
}

/// 文件名安全化：去除路径非法字符。
String sanitizeFileName(String raw) {
  final cleaned = raw
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return cleaned.isEmpty ? '未命名' : cleaned;
}
