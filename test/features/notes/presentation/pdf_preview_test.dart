// 由 Claude 团队生成 | Drawing Notes App
// PdfAttachmentPreview / AttachmentBlockView PDF 分支的 widget 测试。
// 注入 fake PdfPreviewRenderer，避免依赖 pdfrx 原生库。

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:drawing_notes_app/core/storage/pdf_preview_renderer.dart';
import 'package:drawing_notes_app/features/doc/domain/note_attachment.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block.dart';
import 'package:drawing_notes_app/features/doc/presentation/attachment_block_view.dart';
import 'package:drawing_notes_app/features/notes/presentation/pdf_preview.dart';

class _FakeRenderer implements PdfPreviewRenderer {
  _FakeRenderer(this.page, {this.shouldThrow = false});
  final PdfPreviewPage? page;
  final bool shouldThrow;

  @override
  Future<PdfPreviewPage?> renderPage(
    String filePath, {
    int pageNumber = 1,
    double maxWidth = 320,
  }) async {
    if (shouldThrow) throw Exception('boom');
    return page;
  }
}

Uint8List _onePixelPng() {
  final image = img.Image(width: 1, height: 1);
  image.setPixelRgba(0, 0, 8, 8, 8, 255);
  return Uint8List.fromList(img.encodePng(image));
}

NoteAttachment _pdfAttachment({String filePath = '', String url = ''}) =>
    NoteAttachment(
      id: 'p1',
      name: '报告.pdf',
      kind: AttachmentKind.pdf,
      mimeType: 'application/pdf',
      byteSize: 2048,
      filePath: filePath,
      url: url,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  group('PdfAttachmentPreview', () {
    testWidgets('渲染成功：显示内嵌 Image 与打开按钮', (tester) async {
      final page = PdfPreviewPage(
        pngBytes: _onePixelPng(),
        width: 1,
        height: 1,
      );
      await tester.pumpWidget(
        _wrap(
          PdfAttachmentPreview(
            attachment: _pdfAttachment(filePath: 'C:\\tmp\\a.pdf'),
            renderer: _FakeRenderer(page),
            onOpen: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('打开 PDF'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('渲染失败：回退为不可用占位', (tester) async {
      await tester.pumpWidget(
        _wrap(
          PdfAttachmentPreview(
            attachment: _pdfAttachment(filePath: 'C:\\tmp\\a.pdf'),
            renderer: _FakeRenderer(null),
            onOpen: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      expect(find.text('PDF 内嵌预览不可用'), findsOneWidget);
      expect(find.text('打开 PDF'), findsOneWidget);
    });

    testWidgets('渲染器抛异常：同样回退但不崩溃', (tester) async {
      await tester.pumpWidget(
        _wrap(
          PdfAttachmentPreview(
            attachment: _pdfAttachment(filePath: 'C:\\tmp\\a.pdf'),
            renderer: _FakeRenderer(null, shouldThrow: true),
            onOpen: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(Image), findsNothing);
      expect(find.text('打开 PDF'), findsOneWidget);
    });
  });

  group('AttachmentBlockView PDF 分支', () {
    testWidgets('注入渲染器且本地有文件：渲染 PdfAttachmentPreview', (tester) async {
      final page = PdfPreviewPage(
        pngBytes: _onePixelPng(),
        width: 1,
        height: 1,
      );
      await tester.pumpWidget(
        _wrap(
          AttachmentBlockView(
            block: NoteBlock(
              id: 'att1',
              type: NoteBlockType.attachment,
              props: {
                'attachment': jsonEncode(
                  _pdfAttachment(filePath: 'C:\\tmp\\x.pdf').toJson(),
                ),
              },
            ),
            pdfRenderer: _FakeRenderer(page),
            onChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('报告.pdf'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('无本地文件：回退占位卡片', (tester) async {
      await tester.pumpWidget(
        _wrap(
          AttachmentBlockView(
            block: NoteBlock(
              id: 'att1',
              type: NoteBlockType.attachment,
              props: {
                'attachment': jsonEncode(
                  _pdfAttachment(url: 'https://cd/x.pdf').toJson(),
                ),
              },
            ),
            pdfRenderer: _FakeRenderer(null),
            onChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('报告.pdf'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(find.textContaining('PDF 内嵌预览不可用'), findsOneWidget);
    });
  });
}
