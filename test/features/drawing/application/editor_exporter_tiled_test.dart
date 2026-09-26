// 审计 2026-09-26 #19：EditorExporter 分页导出总编排端到端测试——
// 真 DrawingController → exportPdfWithOptions(tiled) → 逐页渲染 →
// isolate 合成 → 落盘全链路（生产等价输入），锁死「单测手选 scale
// 通过、生产恒单页」的断层复发（v1.17.20/22 的教训）。
//
// file_selector 的 getSavePath 经 mock 通道落到临时目录，真实写文件。
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/stroke.dart';
import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/features/drawing/application/editor_exporter.dart';
import 'package:drawing_notes_app/features/drawing/application/pdf_export_options.dart';

const MethodChannel _fileSelectorChannel = MethodChannel(
  'plugins.flutter.io/file_selector',
);

Stroke _penStroke(double x0, double y0) => Stroke(
  type: BrushType.pen,
  color: const Color(0xFF1A1A1A),
  width: 8,
  points: [
    StrokePoint(x0, y0, 0.3),
    StrokePoint(x0 + 80, y0 + 40, 0.9),
    StrokePoint(x0 + 120, y0 + 20, 0.4),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('editor_exporter_tiled');
    // getSavePath → 临时目录固定文件名（真实落盘；返回 null 即用户取消）。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_fileSelectorChannel, (call) async {
          if (call.method == 'getSavePath') {
            return '${tempDir.path}${Platform.pathSeparator}out.pdf';
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_fileSelectorChannel, null);
      tempDir.deleteSync(recursive: true);
    });
  });

  EditorExporter exporterOf(
    DrawingController controller,
    void Function(String) snack,
  ) => EditorExporter(
    // pageProvider = null → 独立画布（非分页笔记页）→ 走画布 tiled 分支。
    controller: controller,
    pageProvider: () => null,
    showSnack: snack,
  );

  List<File> writtenFiles() =>
      tempDir.listSync(recursive: true).whereType<File>().toList();

  test('生产等价输入：900×700 画布 → A4 分页 → 2 页 PDF 落盘（%PDF 头）', () async {
    // A4 595.28×841.89pt，固定输出 scale=1 → 每页承载 595.28×841.89
    // 世界单位；900 宽 → cols=2、700 高 → rows=1，共 2 页。
    // （历史回归锚：v1.17.20/22 该链路在生产路径恒产出 1×1 单页。）
    final document = DrawingDocument(
      id: 'tiled_e2e',
      title: '分页导出端到端',
      width: 900,
      height: 700,
    );
    document.layers.single.strokes
      ..add(_penStroke(10, 10))
      ..add(_penStroke(650, 500)); // 落在第 2 页范围的钢笔笔画
    final controller = DrawingController(document);
    addTearDown(controller.dispose);

    final progress = <({int done, int total})>[];
    final snacks = <String>[];

    await exporterOf(
      controller,
      snacks.add,
    ).exportPdfWithOptions(
      paper: PdfPaper.a4,
      quality: PdfQuality.standard,
      layout: PdfLayout.tiled,
      onProgress: (done, total) => progress.add((done: done, total: total)),
    );

    final files = writtenFiles();
    expect(files, hasLength(1), reason: 'PDF 应真实落盘到临时目录');
    final bytes = await files.single.readAsBytes();
    expect(bytes.length, greaterThan(4));
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    // 成功提示语义：2 页。
    expect(snacks, hasLength(1));
    expect(snacks.single, contains('2'));
    // 进度信号（审计 #23 页号对齐）：渲染页号 1→2（1-based 当前页），
    // 末尾合成信号 total+1 = 3/2（区分「渲染末页」与「正在合成」）。
    expect(
      progress,
      equals(const [
        (done: 1, total: 2),
        (done: 2, total: 2),
        (done: 3, total: 2),
      ]),
    );
  });

  test('isCancelled=true：首页渲染前静默中止（无文件、无进度、无 snack）', () async {
    final document = DrawingDocument(
      id: 'tiled_cancel',
      title: '取消导出',
      width: 900,
      height: 700,
    );
    document.layers.single.strokes.add(_penStroke(10, 10));
    final controller = DrawingController(document);
    addTearDown(controller.dispose);

    final progress = <({int done, int total})>[];
    final snacks = <String>[];

    await exporterOf(
      controller,
      snacks.add,
    ).exportPdfWithOptions(
      paper: PdfPaper.a4,
      quality: PdfQuality.standard,
      layout: PdfLayout.tiled,
      onProgress: (done, total) => progress.add((done: done, total: total)),
      isCancelled: () => true,
    );

    expect(writtenFiles(), isEmpty);
    expect(progress, isEmpty, reason: '取消发生在首帧渲染前，无进度信号');
    expect(snacks, isEmpty, reason: '用户主动取消不发 snack（审计 #9 语义）');
  });

  test('confirmTiles=false：预览确认阶段用户取消，无文件', () async {
    final document = DrawingDocument(
      id: 'tiled_confirm_no',
      title: '确认取消',
      width: 900,
      height: 700,
    );
    document.layers.single.strokes.add(_penStroke(10, 10));
    final controller = DrawingController(document);
    addTearDown(controller.dispose);

    final progress = <({int done, int total})>[];
    final snacks = <String>[];
    var confirmCalled = false;

    await exporterOf(
      controller,
      snacks.add,
    ).exportPdfWithOptions(
      paper: PdfPaper.a4,
      quality: PdfQuality.standard,
      layout: PdfLayout.tiled,
      onProgress: (done, total) => progress.add((done: done, total: total)),
      confirmTiles: (tiles) async {
        confirmCalled = true;
        return false;
      },
    );

    expect(confirmCalled, isTrue, reason: '分页确认回调应收到切片网格');
    expect(progress, isEmpty);
    expect(writtenFiles(), isEmpty);
  });

  test('超过 200 页上限：超限提示分支，无文件、无进度', () async {
    // 120000 宽 → ceil(120000 / 595.28) = 202 列 > 200 上限 →
    // sliceContentIntoPages 的 maxPages 前置拦截返回空表（审计 #27）。
    final document = DrawingDocument(
      id: 'tiled_overflow',
      title: '超大内容',
      width: 120000,
      height: 700,
    );
    document.layers.single.strokes.add(_penStroke(10, 10));
    final controller = DrawingController(document);
    addTearDown(controller.dispose);

    final progress = <({int done, int total})>[];
    final snacks = <String>[];

    await exporterOf(
      controller,
      snacks.add,
    ).exportPdfWithOptions(
      paper: PdfPaper.a4,
      quality: PdfQuality.standard,
      layout: PdfLayout.tiled,
      onProgress: (done, total) => progress.add((done: done, total: total)),
    );

    expect(writtenFiles(), isEmpty);
    expect(progress, isEmpty, reason: '上限在网格物化前拦截，不进入渲染循环');
    expect(snacks, hasLength(1));
    expect(snacks.single, contains('200'));
  });
}
