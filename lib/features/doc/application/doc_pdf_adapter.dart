// 由 Claude 团队生成 | Drawing Notes App
// PDF 适配器（M12.8，AFFiNE Backlinks 批：PDF Export 对齐）。
//
// 框架参照 AFFiNE PR #14057 的 PdfAdapter（MIT，pdfmake 方案）：
// 文档快照 → PDF 文档定义 → 生成字节流。Dart 生态等价实现为官方
// `pdf` 包；中文渲染复用项目已打包的离线 CJK 字体
// （assets/fonts/DroidSansFallbackFull.ttf，与画布 PDF 导出共用）。
//
// 覆盖范围与 AFFiNE PR 对齐：标题（H1-H6）、段落、无序/有序列表（编号）、
// 待办复选框、代码块、引用、提示（callout）、分割线；
// 画布/图表/表格/数据库等嵌入块以占位说明导出。

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:drawing_notes_app/features/notes/domain/note_block.dart';
import 'package:drawing_notes_app/features/notes/domain/note_block_doc.dart';

/// 将块文档渲染为 PDF 字节流（A4，中文内嵌字体）。
Future<Uint8List> noteBlockDocToPdf(NoteBlockDoc doc) async {
  final fontData = await rootBundle.load(
    'assets/fonts/DroidSansFallbackFull.ttf',
  );
  final cjk = pw.Font.ttf(fontData);
  final theme = pw.ThemeData.withFont(
    base: cjk,
    bold: cjk,
    italic: cjk,
    boldItalic: cjk,
  );

  final pdf = pw.Document(theme: theme);
  final title = doc.title.trim().isEmpty ? '未命名' : doc.title.trim();

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(48, 56, 48, 56),
      build: (context) => [
        pw.Text(
          title,
          style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 12),
        if (doc.body.isEmpty)
          pw.Text('（空文档）')
        else
          ..._buildBlocks(doc.body, 0),
      ],
    ),
  );
  return pdf.save();
}

/// 递归构建块 → PDF widget 列表（[indentLevel] 控制嵌套缩进）。
List<pw.Widget> _buildBlocks(List<NoteBlock> blocks, int indentLevel) {
  final widgets = <pw.Widget>[];
  var orderedIndex = 0;
  for (final block in blocks) {
    widgets.addAll(
      _buildBlock(block, indentLevel, orderedIndex, (v) => orderedIndex = v),
    );
  }
  return widgets;
}

List<pw.Widget> _buildBlock(
  NoteBlock block,
  int indentLevel,
  int orderedIndex,
  void Function(int) setOrdered,
) {
  final indent = indentLevel * 16.0;
  final base = pw.TextStyle(fontSize: 11.5);
  final widgets = <pw.Widget>[];

  pw.Widget line(String text, {pw.TextStyle? style}) => pw.Padding(
    padding: pw.EdgeInsets.only(left: indent),
    child: pw.Text(text, style: style ?? base),
  );

  switch (block.type) {
    case NoteBlockType.heading:
      setOrdered(0);
      final level = ((block.props['level'] as int?) ?? 1).clamp(1, 6);
      widgets.add(
        pw.Padding(
          padding: pw.EdgeInsets.only(left: indent, top: 8, bottom: 4),
          child: pw.Text(
            block.text,
            style: pw.TextStyle(
              fontSize: switch (level) {
                1 => 19,
                2 => 16.5,
                _ => 14,
              },
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
      );
    case NoteBlockType.todo:
      setOrdered(0);
      final checked = block.props['checked'] == true;
      widgets.add(
        line(
          '${checked ? '[x]' : '[ ]'} ${block.text}',
          style: base.copyWith(
            decoration: checked ? pw.TextDecoration.lineThrough : null,
          ),
        ),
      );
    case NoteBlockType.bullet:
      setOrdered(0);
      widgets.add(line('• ${block.text}'));
    case NoteBlockType.ordered:
      final next = orderedIndex + 1;
      setOrdered(next);
      widgets.add(line('$next. ${block.text}'));
    case NoteBlockType.quote:
      setOrdered(0);
      widgets.add(
        pw.Padding(
          padding: pw.EdgeInsets.only(left: indent),
          child: pw.Container(
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                left: pw.BorderSide(color: PdfColors.blue300, width: 3),
              ),
            ),
            padding: const pw.EdgeInsets.only(left: 10),
            child: pw.Text(
              block.text,
              style: base.copyWith(color: PdfColors.grey800),
            ),
          ),
        ),
      );
    case NoteBlockType.callout:
      setOrdered(0);
      widgets.add(
        pw.Padding(
          padding: pw.EdgeInsets.only(left: indent),
          child: pw.Container(
            width: double.infinity,
            decoration: pw.BoxDecoration(
              color: PdfColors.amber50,
              borderRadius: pw.BorderRadius.circular(6),
            ),
            padding: const pw.EdgeInsets.all(10),
            child: pw.Text('💡 ${block.text}'),
          ),
        ),
      );
    case NoteBlockType.code:
      setOrdered(0);
      widgets.add(
        pw.Padding(
          padding: pw.EdgeInsets.only(left: indent),
          child: pw.Container(
            width: double.infinity,
            color: PdfColors.grey100,
            padding: const pw.EdgeInsets.all(10),
            child: pw.Text(block.text, style: base),
          ),
        ),
      );
    case NoteBlockType.divider:
      setOrdered(0);
      widgets.add(
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 8),
          child: pw.Divider(color: PdfColors.grey400),
        ),
      );
    case NoteBlockType.toggle:
      setOrdered(0);
      widgets.add(line('▸ ${block.text}'));
    case NoteBlockType.image:
      setOrdered(0);
      widgets.add(line('[图片]'));
    case NoteBlockType.link:
      setOrdered(0);
      widgets.add(line('[链接] ${block.text}'));
    case NoteBlockType.canvas:
      setOrdered(0);
      widgets.add(line('[内嵌画布]'));
    case NoteBlockType.chart:
      setOrdered(0);
      widgets.add(line('[内嵌图表]'));
    case NoteBlockType.table:
      setOrdered(0);
      widgets.add(line('[内嵌表格]'));
    case NoteBlockType.database:
      setOrdered(0);
      widgets.add(line('[内嵌数据库视图]'));
    case NoteBlockType.attachment:
      setOrdered(0);
      widgets.add(line('[附件] ${block.text}'));
    case NoteBlockType.text:
      setOrdered(0);
      widgets.add(
        pw.Padding(
          padding: pw.EdgeInsets.only(left: indent, bottom: 2),
          child: pw.Text(block.text.isEmpty ? ' ' : block.text),
        ),
      );
  }

  // 子块递归（嵌套缩进）
  if (block.children.isNotEmpty &&
      (block.type != NoteBlockType.toggle ||
          (block.props['expanded'] as bool? ?? true))) {
    widgets.addAll(_buildBlocks(block.children, indentLevel + 1));
  }
  return widgets;
}
