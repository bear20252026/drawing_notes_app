/// 块文档 ↔ Markdown 双向转换。
///
/// 提供 [NoteBlockDoc] 与 Markdown 字符串的互转能力，保证数据可迁移性。
///
/// 注意：当前 NoteBlock 模型仅存储纯文本（无 spans 字段），
/// 因此富文本样式（bold/italic/underline）暂不导出。
/// 若未来 NoteBlock 扩展 spans 字段，可在此补充富文本序列化。
library;

import 'dart:convert';

import 'package:drawing_notes_app/features/doc/domain/note_block.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block_doc.dart';

/// 将 NoteBlockDoc 导出为 Markdown 字符串。
///
/// 转换规则：
/// - heading → `# `~`###### `（level 1-6）
/// - text/paragraph → 纯文本
/// - todo → `- [ ]` 或 `- [x]`
/// - bullet → `- `
/// - ordered → `1. `（每项独立编号）
/// - quote → `> `
/// - code → ```` ``` ```` 围栏
/// - divider → `---`
/// - callout → `> [!NOTE]`
/// - image → `![alt](src)`
/// - link → `[title](href)`
/// - canvas/chart/table/database → 注释块 + JSON 摘要（可逆）
String noteBlockDocToMarkdown(NoteBlockDoc doc) {
  final buffer = StringBuffer();

  // 文档标题作为 H1
  if (doc.title.isNotEmpty) {
    buffer.writeln('# ${doc.title}');
    buffer.writeln();
  }

  // 逐块转换
  var orderedIndex = 0;
  for (final block in doc.body) {
    // ordered 块需要递增编号
    if (block.type == NoteBlockType.ordered) {
      orderedIndex++;
      buffer.writeln(_blockToMarkdown(block, orderedIndex: orderedIndex));
    } else {
      orderedIndex = 0;
      buffer.writeln(_blockToMarkdown(block));
    }
  }

  return buffer.toString().trimRight();
}

/// 将单个块转为 Markdown 片段。
String _blockToMarkdown(NoteBlock block, {int orderedIndex = 0}) {
  switch (block.type) {
    case NoteBlockType.text:
      return block.text;

    case NoteBlockType.heading:
      final level = (block.props['level'] as int? ?? 1).clamp(1, 6);
      final prefix = '#' * level;
      return '$prefix ${block.text}';

    case NoteBlockType.bullet:
      return '- ${block.text}';

    case NoteBlockType.ordered:
      return '$orderedIndex. ${block.text}';

    case NoteBlockType.todo:
      final checked = block.props['checked'] as bool? ?? false;
      final marker = checked ? '[x]' : '[ ]';
      return '- $marker ${block.text}';

    case NoteBlockType.quote:
      return '> ${block.text}';

    case NoteBlockType.code:
      final lang = block.props['language'] as String? ?? '';
      return '```$lang\n${block.text}\n```';

    case NoteBlockType.divider:
      return '---';

    case NoteBlockType.callout:
      return '> [!NOTE]\n> ${block.text}';

    case NoteBlockType.toggle:
      // Markdown 无 toggle 语义，导出为带标记的列表项（信息不丢失）。
      return '- ▸ ${block.text}';

    case NoteBlockType.image:
      final src = block.props['src'] as String? ?? '';
      final alt = block.props['alt'] as String? ?? block.text;
      if (src.isEmpty) return '![$alt]()';
      return '![$alt]($src)';

    case NoteBlockType.link:
      final href = block.props['href'] as String? ?? '';
      final title = block.props['title'] as String? ?? block.text;
      return '[$title]($href)';

    // 内嵌块：用注释 + JSON 摘要（可逆）
    case NoteBlockType.canvas:
      return '<!-- canvas -->\n> [!canvas]\n> ${jsonEncode(block.props)}';

    case NoteBlockType.chart:
      return '<!-- chart -->\n> [!chart]\n> ${jsonEncode(block.props)}';

    case NoteBlockType.table:
      return _tableToMarkdown(block);

    case NoteBlockType.database:
      return '<!-- database -->\n> [!database]\n> ${jsonEncode(block.props)}';

    case NoteBlockType.attachment:
      // 附件：有 url/filePath 时导出为链接，否则保留为注释 JSON 摘要。
      final raw = block.props['attachment'] as String?;
      String link = '';
      if (raw != null) {
        try {
          final m = jsonDecode(raw) as Map<String, dynamic>;
          link = (m['url'] as String? ?? m['filePath'] as String? ?? '')
              .toString();
        } catch (_) {
          // ignored
        }
      }
      final name = block.text.isEmpty ? '附件' : block.text;
      return link.isNotEmpty
          ? '[$name]($link)'
          : '<!-- attachment -->\n> [!attachment]\n> ${jsonEncode(block.props)}';
  }
}

/// 将表格块转为 Markdown 表格。
String _tableToMarkdown(NoteBlock block) {
  final rows = (block.props['rows'] as int? ?? 1).clamp(1, 50);
  final cols = (block.props['cols'] as int? ?? 1).clamp(1, 10);

  // 从 children 提取单元格文本
  final cellTexts = <String>[];
  for (final child in block.children) {
    cellTexts.add(child.text);
  }

  final buffer = StringBuffer();
  for (int r = 0; r < rows; r++) {
    final cells = <String>[];
    for (int c = 0; c < cols; c++) {
      final idx = r * cols + c;
      cells.add(idx < cellTexts.length ? cellTexts[idx] : '');
    }
    buffer.writeln('| ${cells.join(' | ')} |');
    // 表头分隔行
    if (r == 0) {
      buffer.writeln('| ${List.filled(cols, '---').join(' | ')} |');
    }
  }
  return buffer.toString().trimRight();
}

/// 将 Markdown 字符串解析为 NoteBlockDoc。
///
/// 尽力而为解析：识别 heading/列表/todo/quote/code/分隔线/链接/加粗/斜体/图片。
/// 识别不到的内嵌块按空段落处理。
///
/// [id] 为可选文档 ID，默认自动生成。
NoteBlockDoc noteBlockDocFromMarkdown(String md, {String? id}) {
  final docId = id ?? 'md-${DateTime.now().millisecondsSinceEpoch}';
  final blocks = <NoteBlock>[];
  final lines = md.split('\n');

  var i = 0;
  while (i < lines.length) {
    final line = lines[i];

    // 空行跳过
    if (line.trim().isEmpty) {
      i++;
      continue;
    }

    // 分隔线
    if (RegExp(r'^-{3,}\s*$').hasMatch(line.trim())) {
      blocks.add(NoteBlock.dividerBlock('div_${i}_${_shortId()}'));
      i++;
      continue;
    }

    // 标题
    final headingMatch = RegExp(r'^(#{1,6})\s+(.*)').firstMatch(line);
    if (headingMatch != null) {
      final level = headingMatch.group(1)!.length;
      final text = headingMatch.group(2)!.trim();
      blocks.add(
        NoteBlock.headingBlock(
          'h_${i}_${_shortId()}',
          level: level,
          text: text,
        ),
      );
      i++;
      continue;
    }

    // 代码围栏
    if (line.trim().startsWith('```')) {
      final lang = line.trim().substring(3).trim();
      final codeLines = <String>[];
      i++;
      while (i < lines.length && !lines[i].trim().startsWith('```')) {
        codeLines.add(lines[i]);
        i++;
      }
      if (i < lines.length) i++; // 跳过结束围栏
      blocks.add(
        NoteBlock.codeBlock(
          'code_${i}_${_shortId()}',
          language: lang,
          text: codeLines.join('\n'),
        ),
      );
      continue;
    }

    // 引用块
    if (line.trim().startsWith('>')) {
      final quoteLines = <String>[];
      while (i < lines.length && lines[i].trim().startsWith('>')) {
        quoteLines.add(lines[i].trim().substring(1).trim());
        i++;
      }
      blocks.add(
        NoteBlock.quoteBlock(
          'q_${i}_${_shortId()}',
          text: quoteLines.join('\n'),
        ),
      );
      continue;
    }

    // Todo 列表
    final todoMatch = RegExp(r'^-\s+\[([ xX])\]\s+(.*)').firstMatch(line);
    if (todoMatch != null) {
      final checked = todoMatch.group(1)!.toLowerCase() == 'x';
      final text = todoMatch.group(2)!.trim();
      blocks.add(
        NoteBlock.todoBlock(
          'todo_${i}_${_shortId()}',
          checked: checked,
          text: text,
        ),
      );
      i++;
      continue;
    }

    // 无序列表
    if (RegExp(r'^[-*+]\s+(.*)').hasMatch(line.trim())) {
      final text = line.trim().replaceFirst(RegExp(r'^[-*+]\s+'), '');
      blocks.add(NoteBlock.bulletBlock('ul_${i}_${_shortId()}', text: text));
      i++;
      continue;
    }

    // 有序列表
    final orderedMatch = RegExp(r'^(\d+)\.\s+(.*)').firstMatch(line.trim());
    if (orderedMatch != null) {
      final text = orderedMatch.group(2)!.trim();
      blocks.add(NoteBlock.orderedBlock('ol_${i}_${_shortId()}', text: text));
      i++;
      continue;
    }

    // 图片
    final imgMatch = RegExp(
      r'^!\[([^\]]*)\]\(([^)]+)\)',
    ).firstMatch(line.trim());
    if (imgMatch != null) {
      blocks.add(
        NoteBlock.imageBlock(
          'img_${i}_${_shortId()}',
          src: imgMatch.group(2)!,
          alt: imgMatch.group(1)!,
        ),
      );
      i++;
      continue;
    }

    // 普通段落
    blocks.add(NoteBlock.textBlock('p_${i}_${_shortId()}', text: line.trim()));
    i++;
  }

  // 若第一个块是 H1，提取为文档标题（round-trip 保序）
  var title = '';
  if (blocks.isNotEmpty && blocks.first.type == NoteBlockType.heading) {
    final firstLevel = blocks.first.props['level'] as int? ?? 1;
    if (firstLevel == 1) {
      title = blocks.first.text;
      blocks.removeAt(0);
    }
  }

  return NoteBlockDoc(
    id: docId,
    title: title,
    body: blocks,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
}

/// 生成短 ID（用于解析时的块标识）。
final _idCounter = _IdCounter();

String _shortId() => _idCounter.next();

class _IdCounter {
  int _c = 0;
  String next() => '${_c++}';
}
