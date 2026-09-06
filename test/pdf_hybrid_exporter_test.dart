import 'dart:ui';

import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/features/drawing/rendering/pdf_hybrid_exporter.dart';
import 'package:drawing_notes_app/features/drawing/rendering/stroke_renderer.dart';
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/stroke.dart';
import 'package:flutter_test/flutter_test.dart';

Stroke _penStroke() => Stroke(
  type: BrushType.pen,
  color: const Color(0xFF1A1A1A),
  width: 8,
  points: const [
    StrokePoint(50, 50, 0.3),
    StrokePoint(90, 70, 0.9),
    StrokePoint(130, 60, 0.4),
  ],
);

Stroke _markerStroke() => Stroke(
  type: BrushType.marker,
  color: const Color(0xFFFFD54F),
  width: 24,
  points: const [StrokePoint(40, 40, 0.5), StrokePoint(160, 40, 0.5)],
);

void main() {
  test('strokeToSvgPath 生成闭合的 M…L…Z 矢量路径', () {
    final svg = StrokeRenderer.strokeToSvgPath(_penStroke());

    expect(svg, isNotNull);
    expect(svg, startsWith('M '));
    expect(svg, endsWith(' Z'));
    expect(svg, contains(' L '));
  });

  test('strokeToSvgPath 支持坐标偏移（对齐光栅层）', () {
    final plain = StrokeRenderer.strokeToSvgPath(_penStroke())!;
    final shifted = StrokeRenderer.strokeToSvgPath(
      _penStroke(),
      offset: const Offset(-50, -50),
    )!;

    // 偏移前后首点坐标应精确相差 50（轮廓首点由 perfect_freehand 生成，
    // 并非原始输入点，因此比较差值而非硬编码坐标）。
    double firstX(String svg) =>
        double.parse(RegExp(r'^M ([-0-9.]+)').firstMatch(svg)!.group(1)!);
    double firstY(String svg) => double.parse(
      RegExp(r'^M [-0-9.]+ ([-0-9.]+)').firstMatch(svg)!.group(1)!,
    );
    expect(firstX(shifted), closeTo(firstX(plain) - 50, 0.01));
    expect(firstY(shifted), closeTo(firstY(plain) - 50, 0.01));
  });

  test('shouldRasterize 判定：高亮/铅笔光栅化，钢笔矢量', () {
    expect(PdfHybridExporter.shouldRasterize(_markerStroke()), isTrue);
    expect(PdfHybridExporter.shouldRasterize(_penStroke()), isFalse);
    expect(
      PdfHybridExporter.shouldRasterize(
        Stroke(
          type: BrushType.pencil,
          color: const Color(0xFF444444),
          width: 6,
          points: const [StrokePoint(0, 0, 1), StrokePoint(10, 10, 1)],
        ),
      ),
      isTrue,
    );
  });

  test('混合导出生成含矢量笔画与光栅层的 PDF', () async {
    final document = DrawingDocument(id: 'pdf_hybrid', title: '混合导出');
    document.layers.single.strokes
      ..add(_penStroke())
      ..add(_markerStroke());
    final controller = DrawingController(document);
    addTearDown(controller.dispose);

    final rasterPng = await controller.renderToPng(
      excludedTypes: const {BrushType.pen},
    );
    expect(rasterPng, isNotNull);

    final bytes = await PdfHybridExporter.export(
      bounds: const Rect.fromLTWH(0, 0, 200, 150),
      rasterPng: rasterPng!,
      vectorStrokes: [_penStroke()],
    );

    expect(bytes, isNotEmpty);
    // PDF 魔数：%PDF。
    final header = String.fromCharCodes(bytes.take(4));
    expect(header, '%PDF');
  });

  test('jpegQuality 压缩路径：JPEG 光栅层导出成功（%PDF）', () async {
    final document = DrawingDocument(id: 'pdf_jpeg', title: 'JPEG 导出');
    document.layers.single.strokes.add(_markerStroke());
    final controller = DrawingController(document);
    addTearDown(controller.dispose);

    final rasterPng = await controller.renderToPng();
    expect(rasterPng, isNotNull);

    final bytes = await PdfHybridExporter.export(
      bounds: const Rect.fromLTWH(0, 0, 200, 150),
      rasterPng: rasterPng!,
      vectorStrokes: const [],
      jpegQuality: 80,
    );

    expect(bytes, isNotEmpty);
    expect(
      String.fromCharCodes(bytes.take(4)),
      '%PDF',
      reason: 'JPEG 压缩路径同样产出合法 PDF',
    );
  });
}
