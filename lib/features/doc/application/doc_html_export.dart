// 由 Claude 团队生成 | Drawing Notes App
// HTML 导出（M12.6，AFFiNE Export 对齐第二批）。
// NoteBlockDoc → HTML。纯 Dart，无 IO 依赖，可单测。
// 与 doc_markdown_export.dart 平行：同一域模型、不同渲染目标。

import 'package:drawing_notes_app/features/doc/domain/note_block.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block_doc.dart';

/// 转义 HTML 特殊字符（防注入/破版）。
String escapeHtml(String raw) => raw
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// 将块文档转换为独立 HTML 文档（含内联样式，双击可浏览）。
String noteBlockDocToHtml(NoteBlockDoc doc) {
  final title = escapeHtml(doc.title.trim().isEmpty ? '未命名' : doc.title.trim());
  final buf = StringBuffer();
  buf.writeln('<!DOCTYPE html>');
  buf.writeln('<html lang="zh-CN">');
  buf.writeln('<head><meta charset="utf-8"><title>$title</title>');
  buf.writeln(
    '<style>body{font-family:system-ui,sans-serif;max-width:720px;'
    'margin:32px auto;padding:0 16px;line-height:1.7;color:#1d1d1f}'
    'h1{font-size:1.9em}blockquote{border-left:4px solid #0066cc;'
    'margin:8px 0;padding:4px 14px;background:#f5f7fa}'
    'pre{background:#f5f5f7;padding:12px;border-radius:8px;overflow:auto}'
    '.callout{background:#fff8e1;border-radius:8px;padding:10px 14px}'
    '.embed{color:#888;font-style:italic}</style>',
  );
  buf.writeln('</head><body>');
  buf.writeln('<h1>$title</h1>');

  void writeBlock(NoteBlock b) {
    final text = escapeHtml(b.text);
    switch (b.type) {
      case NoteBlockType.heading:
        final level = ((b.props['level'] as int?) ?? 1).clamp(1, 6);
        buf.writeln('<h$level>$text</h$level>');
      case NoteBlockType.todo:
        final checked = b.props['checked'] == true;
        buf.writeln(
          '<p><input type="checkbox" disabled${checked ? ' checked' : ''}> '
          '${checked ? '<s>$text</s>' : text}</p>',
        );
      case NoteBlockType.bullet:
        buf.writeln('<ul><li>$text</li></ul>');
      case NoteBlockType.ordered:
        buf.writeln('<ol><li>$text</li></ol>');
      case NoteBlockType.quote:
        buf.writeln('<blockquote>$text</blockquote>');
      case NoteBlockType.callout:
        buf.writeln('<div class="callout">💡 $text</div>');
      case NoteBlockType.toggle:
        buf.writeln('<p><strong>▸</strong> $text</p>');
      case NoteBlockType.code:
        buf.writeln('<pre><code>$text</code></pre>');
      case NoteBlockType.divider:
        buf.writeln('<hr>');
      case NoteBlockType.image:
        buf.writeln('<p class="embed">[图片]</p>');
      case NoteBlockType.link:
        buf.writeln('<p class="embed">[链接] $text</p>');
      case NoteBlockType.canvas:
        buf.writeln('<p class="embed">[内嵌画布] $text</p>');
      case NoteBlockType.chart:
        buf.writeln('<p class="embed">[内嵌图表]</p>');
      case NoteBlockType.table:
        buf.writeln('<p class="embed">[内嵌表格]</p>');
      case NoteBlockType.database:
        buf.writeln('<p class="embed">[内嵌数据库视图]</p>');
      case NoteBlockType.attachment:
        buf.writeln('<p class="embed">[附件] $text</p>');
      case NoteBlockType.text:
        if (b.text.isEmpty) {
          buf.writeln('<p><br></p>');
        } else {
          buf.writeln('<p>$text</p>');
        }
        break;
    }
    for (final child in b.children) {
      writeBlock(child);
    }
  }

  for (final block in doc.body) {
    writeBlock(block);
  }
  buf.writeln('</body></html>');
  return buf.toString();
}
