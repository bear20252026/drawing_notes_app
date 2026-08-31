// P3-3 契约测试：AttachmentBlockView 附件块视图。
// 渲染文件/PDF/书签卡片，编辑备注写回 props['attachment'] 的 JSON。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block.dart';
import 'package:drawing_notes_app/features/doc/domain/note_attachment.dart';
import 'package:drawing_notes_app/features/doc/presentation/attachment_block_view.dart';

void main() {
  NoteBlock buildBlock(NoteAttachment a) => NoteBlock(
        id: 'att1',
        type: NoteBlockType.attachment,
        props: {'attachment': jsonEncode(a.toJson())},
      );

  NoteAttachment pdf() => NoteAttachment(
        id: 'p1',
        name: '报告.pdf',
        kind: AttachmentKind.pdf,
        mimeType: 'application/pdf',
        byteSize: 2048,
        url: 'https://cdn.example.com/report.pdf',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );

  testWidgets('渲染 PDF 卡片：名称 + 子标题 + 内嵌预览', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: AttachmentBlockView(block: buildBlock(pdf()))),
    ));
    expect(find.text('报告.pdf'), findsOneWidget);
    expect(find.textContaining('PDF'), findsWidgets);
    expect(find.text('打开 PDF'), findsOneWidget);
  });

  testWidgets('渲染书签卡片：展示链接', (tester) async {
    final bm = NoteAttachment(
      id: 'b1',
      name: '官网',
      kind: AttachmentKind.bookmark,
      url: 'https://example.com',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: AttachmentBlockView(block: buildBlock(bm))),
    ));
    expect(find.text('官网'), findsOneWidget);
    expect(find.text('https://example.com'), findsWidgets);
    expect(find.text('打开链接'), findsOneWidget);
  });

  testWidgets('渲染文件卡片：显示大小，无内嵌', (tester) async {
    final f = NoteAttachment(
      id: 'f1',
      name: 'data.zip',
      kind: AttachmentKind.file,
      byteSize: 1024,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: AttachmentBlockView(block: buildBlock(f))),
    ));
    expect(find.text('data.zip'), findsOneWidget);
    expect(find.textContaining('1 KB'), findsOneWidget);
  });

  testWidgets('编辑备注写回新块', (tester) async {
    NoteBlock? last;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: AttachmentBlockView(
        block: buildBlock(pdf()),
        onChanged: (b) => last = b,
      )),
    ));
    await tester.tap(find.byTooltip('编辑描述'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '季度报告');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(last, isNotNull);
    final decoded = AttachmentBlockView.decodeAttachment(last!);
    expect(decoded!.description, '季度报告');
  });
}
