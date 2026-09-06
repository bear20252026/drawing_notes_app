import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/layer.dart';
import 'package:drawing_notes_app/core/canvas_model/stroke.dart';
import 'package:drawing_notes_app/features/drawing/rendering/pdf_hybrid_exporter.dart';
import 'package:drawing_notes_app/features/notes/application/notebook_pdf_exporter.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';

/// W2 整本多页 PDF 导出测试。
///
/// 断言策略：PDF 头魔数 + `/Type /Page`（页对象，非 /Pages）出现次数
/// 与画布页数一致——pdf 包输出的页对象可数，足以验证"每页一页"语义。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Stroke penStroke(ui.Offset a, ui.Offset b) => Stroke(
    points: [StrokePoint(a.dx, a.dy, 1.0), StrokePoint(b.dx, b.dy, 1.0)],
    color: const ui.Color(0xFF000000),
    width: 4,
    type: BrushType.pen,
  );

  NotebookPage pageOf(String id, DrawingDocument doc) =>
      NotebookPage(id: id, title: '页 $id', document: doc);

  DrawingDocument docOf(String id) => DrawingDocument(
    id: id,
    title: id,
    width: 640,
    height: 480,
    layers: [
      Layer(
        id: 'layer_1',
        name: '图层 1',
        strokes: [
          penStroke(const ui.Offset(10, 10), const ui.Offset(200, 120)),
        ],
      ),
    ],
  );

  int countPdfPages(Uint8List bytes) {
    final text = String.fromCharCodes(bytes);
    // 页对象：/Type /Page 且后随非 's'（排除 /Type /Pages 页树节点），
    // 也排除 XObject 等其它 /Type 词条。
    return RegExp(r'/Type\s*/Page(?![A-Za-z])').allMatches(text).length;
  }

  test('多页导出：两个画布页 → PDF 两页', () async {
    final notebook = Notebook(id: 'nb', title: '整本测试')
      ..pages.addAll([pageOf('p1', docOf('p1')), pageOf('p2', docOf('p2'))]);

    final bytes = await NotebookPdfExporter.exportNotebook(notebook);

    expect(bytes, isNotEmpty);
    // PDF 头魔数。
    expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
    // 每个画布页对应一个 PDF 页对象。
    expect(countPdfPages(bytes), 2);
  });

  test('空页正文也能导出（只画白纸，不产生空异常）', () async {
    final notebook = Notebook(id: 'nb', title: '空白页整本')
      ..pages.add(
        NotebookPage(
          id: 'p1',
          title: '空白页',
          document: DrawingDocument(id: 'p1', title: '空白页'),
        ),
      );

    final bytes = await NotebookPdfExporter.exportNotebook(notebook);

    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
    expect(countPdfPages(bytes), 1);
  });

  test('PdfHybridExporter.exportMultiPage 直接驱动多页构建', () async {
    // 合法 1×1 PNG（pdf 包会嗅探图片格式，假字节会导致解码失败）。
    final recorder = ui.PictureRecorder();
    ui.Canvas(
      recorder,
    ).drawPaint(ui.Paint()..color = const ui.Color(0xFFFFFFFF));
    final image = await recorder.endRecording().toImage(1, 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final png = data!.buffer.asUint8List();

    final bytes = await PdfHybridExporter.exportMultiPage(
      pages: [
        for (var i = 0; i < 3; i++)
          PdfPageInput(
            bounds: const ui.Rect.fromLTWH(0, 0, 320, 240),
            rasterPng: png,
            vectorStrokes: const [],
          ),
      ],
    );

    expect(countPdfPages(bytes), 3);
  });
}
