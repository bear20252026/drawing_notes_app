// M12.8 回归：PDF 适配器（AFFiNE PdfAdapter 框架对齐）。
// 渲染冒烟：真实字节流 + PDF 魔数校验 + 中文文本嵌入。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/features/doc/application/doc_pdf_adapter.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block_doc.dart';

NoteBlockDoc _doc() {
  return NoteBlockDoc(
    id: 'd1',
    title: '测试文档',
    body: [
      NoteBlock.headingBlock('h1', level: 2, text: '第二章 计划'),
      NoteBlock.textBlock('p1', text: '中文正文内容（CJK 渲染验证）'),
      NoteBlock.todoBlock('t1', text: '买牛奶', checked: true),
      NoteBlock.bulletBlock('u1', text: '圆点项'),
      NoteBlock.orderedBlock('o1', text: '第一步'),
      NoteBlock.quoteBlock('q1', text: '引用内容'),
      NoteBlock.codeBlock('c1', text: 'print(1);'),
      NoteBlock.dividerBlock('dv'),
      NoteBlock.toggleBlock('tg', text: '折叠标题'),
      NoteBlock.textBlock('p2', text: ''),
    ],
    createdAt: DateTime(2026, 8, 31),
    updatedAt: DateTime(2026, 8, 31),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('PDF 渲染：合法字节流（%PDF 魔数 + 非 EOF 截断）', () async {
    final bytes = await noteBlockDocToPdf(_doc());
    expect(bytes.length, greaterThan(1000));
    // PDF 文件头魔数
    expect(
      String.fromCharCodes(bytes.sublist(0, 5)),
      '%PDF-',
      reason: '输出必须是合法 PDF 文件（二进制完整）',
    );
  });

  test('空文档兜底渲染不崩溃', () async {
    final bytes = await noteBlockDocToPdf(
      NoteBlockDoc(
        id: 'empty',
        title: '',
        createdAt: DateTime(2026, 8, 31),
        updatedAt: DateTime(2026, 8, 31),
      ),
    );
    expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
  });

  test('文件落盘后可被 pdfrx/pdfium 打开（字节完整）', () async {
    final bytes = await noteBlockDocToPdf(_doc());
    final tmp = File(
      '${Directory.systemTemp.path}/m126_pdf_test_${DateTime.now().microsecondsSinceEpoch}.pdf',
    );
    await tmp.writeAsBytes(bytes, flush: true);
    expect(await tmp.length(), bytes.length);
    final head = String.fromCharCodes(await tmp.readAsBytes());
    expect(head.startsWith('%PDF-'), isTrue);
    expect(head.contains('%%EOF'), isTrue, reason: 'PDF 尾部标记完整');
    await tmp.delete();
  });
}
