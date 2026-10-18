import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/layer.dart';
import 'package:drawing_notes_app/core/canvas_model/stroke.dart';
// C-06（审计 2026-09-27）：NotebookPdfExporter 改实例类——媒体解密依赖
// 构造注入（测试注入生产同一全局单例，语义与此前 static 直取一致）。
import 'package:drawing_notes_app/core/security/media_crypto_service.dart';
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

  /// C-06：导出器实例（媒体解密依赖注入生产同一全局单例）。
  NotebookPdfExporter buildExporter() =>
      NotebookPdfExporter(mediaCrypto: MediaCryptoService.instance);

  test('多页导出：两个画布页 → PDF 两页', () async {
    final notebook = Notebook(id: 'nb', title: '整本测试')
      ..pages.addAll([pageOf('p1', docOf('p1')), pageOf('p2', docOf('p2'))]);

    final bytes = await buildExporter().exportNotebook(notebook);

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

    final bytes = await buildExporter().exportNotebook(notebook);

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

  // 审计 2026-09-26 #38：notes 整本导出路径的 footer 接线专项断言——
  // v1.17.22 的页脚特性只接了画布 tiled 路径，整本路径缺失；本组用例
  // 锁死「footer 开启 → CJK 字体真嵌入（FontFile2）+ 页数不变」。
  test('footer=false：无字体嵌入（Type1 默认字体现状回归锁）', () async {
    final notebook = Notebook(id: 'nb', title: '无页脚整本')
      ..pages.add(pageOf('p1', docOf('p1')));

    final bytes = await buildExporter().exportNotebook(notebook);

    expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
    expect(countPdfPages(bytes), 1);
    expect(
      String.fromCharCodes(bytes),
      isNot(contains('FontFile2')),
      reason: '默认 Type1 字体不嵌入文件（footer 关闭零开销）',
    );
  });

  test('footer=true：CJK 字体真嵌入（FontFile2）且页数不变', () async {
    final notebook = Notebook(id: 'nb', title: '页脚整本')
      ..pages.addAll([pageOf('p1', docOf('p1')), pageOf('p2', docOf('p2'))]);

    final bytes = await buildExporter().exportNotebook(
      notebook,
      footer: true,
    );

    expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
    expect(countPdfPages(bytes), 2, reason: '页脚不影响页集合');
    expect(
      String.fromCharCodes(bytes),
      contains('FontFile2'),
      reason: '中文标题页脚必须挂 CJK 字体主题（DroidSansFallbackFull 真字形嵌入）',
    );
  });

  // ---------------- 接线（R45）：注释说「已接线」不算，调用方传了才算 ----------------
  //
  // 背景（台账 §31）：导出器的 `[footer]` 注释写着「审计 2026-09-26 #38 接线」，
  // 而整本这条生产路径（`notebook_view_page_manage.dart`）当时**不传** footer ⇒ 整本 PDF
  // 一直没有页脚；偏偏本文件里的用例传了 `footer: true` ⇒ 绿灯把这个缺失常年盖住。
  // 所以这里不再测页脚长什么样（上面已有用例测），而是把**调用方有没有传参**变成判据。
  group('接线：lib/ 里每个整本导出调用点都得真的传 footer', () {
    /// (调用点, 是否传了 `footer: true`)。
    List<(String, bool)> callSites() {
      final out = <(String, bool)>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          // 注释行跳过：导出器的文档注释里就写着 `exportNotebook(`（正在解释这段历史），
          // 按整行匹配会把注释当成一个「没传参的调用点」⇒ 假红（trap 56 的第三种脸）。
          if (line.trimLeft().startsWith('//')) continue;
          if (!line.contains('exportNotebook(')) continue;
          if (line.contains('Future<Uint8List> exportNotebook(')) continue; // 方法声明
          final window = lines.skip(i).take(8).join('\n');
          out.add(
            ('${entity.path}:$i', window.contains('footer: true')),
          );
        }
      }
      return out;
    }

    test('分母下限：至少扫到那个生产调用点', () {
      expect(
        callSites().length,
        greaterThanOrEqualTo(1),
        reason: '扫不到任何 exportNotebook( 调用点 ⇒ 抽取失效，下一条判据会「空集通过」',
      );
    });

    test('判据：每个调用点都传了 footer: true（不传就没有页脚）', () {
      final missing = callSites().where((s) => !s.$2).map((s) => s.$1).toList();
      expect(
        missing,
        isEmpty,
        reason: '这些整本导出调用点没传 footer ⇒ 用户拿到的 PDF 没有页脚',
      );
    });
  });
}
