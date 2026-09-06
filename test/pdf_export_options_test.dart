import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/canvas_model/stroke.dart';
import 'package:drawing_notes_app/features/drawing/application/pdf_export_options.dart';

/// PDF 二级面板选项数学单测（M12.5——纯函数，无 Widget/io 依赖）。
void main() {
  group('PdfPaper 纸张尺寸', () {
    test('A4 / Letter 点尺寸', () {
      expect(PdfPaper.a4.pageSize, const Size(595.28, 841.89));
      expect(PdfPaper.letter.pageSize, const Size(612, 792));
      expect(PdfPaper.canvas.pageSize, isNull);
    });
  });

  group('PdfQuality 压缩映射', () {
    test('无损 null / 标准 80 / 省流量 60', () {
      expect(PdfQuality.lossless.jpegQuality, isNull);
      expect(PdfQuality.standard.jpegQuality, 80);
      expect(PdfQuality.saver.jpegQuality, 60);
    });
  });

  group('fitContentOnPaper 纸张适配', () {
    test('跟随画布恒等（既有行为零变化）', () {
      final fit = fitContentOnPaper(
        PdfPaper.canvas,
        content: const Size(800, 600),
      );
      expect(fit.scale, 1.0);
      expect(fit.offset, Offset.zero);
    });

    test('等尺寸内容 scale=1 居中零位移', () {
      final fit = fitContentOnPaper(
        PdfPaper.a4,
        content: const Size(595.28, 841.89),
      );
      expect(fit.scale, closeTo(1.0, 1e-9));
      expect(fit.offset.dx, closeTo(0, 1e-9));
      expect(fit.offset.dy, closeTo(0, 1e-9));
    });

    test('大内容等比缩小并居中', () {
      final fit = fitContentOnPaper(
        PdfPaper.a4,
        content: const Size(1190.56, 841.89),
      );
      // 宽为瓶颈：scale=0.5；高居中：(841.89-420.945)/2。
      expect(fit.scale, closeTo(0.5, 1e-9));
      expect(fit.offset.dx, closeTo(0, 1e-9));
      expect(fit.offset.dy, closeTo(841.89 * 0.25, 1e-6));
    });

    test('极小内容放大钳制 ≤4', () {
      final fit = fitContentOnPaper(PdfPaper.a4, content: const Size(100, 100));
      expect(fit.scale, 4.0);
    });

    test('空内容回退恒等（防除零）', () {
      final fit = fitContentOnPaper(PdfPaper.a4, content: Size.zero);
      expect(fit.scale, 1.0);
    });
  });

  group('scaleStrokeForPaper 笔画变换', () {
    test('点列×scale+位移，线宽×scale，质感字段保留', () {
      final src = Stroke(
        points: const [StrokePoint(10, 20, 1.0), StrokePoint(30, 40, 0.5)],
        color: const Color(0xFF112233),
        width: 5,
        type: BrushType.pen,
        seed: 42,
      );
      final out = scaleStrokeForPaper(src, 2.0, const Offset(5, 7));
      expect(out.points[0].x, 25.0);
      expect(out.points[0].y, 47.0);
      expect(out.points[1].x, 65.0);
      expect(out.points[1].y, 87.0);
      expect(out.points[1].pressure, 0.5);
      expect(out.width, 10.0);
      expect(out.color, src.color);
      expect(out.type, BrushType.pen);
      expect(out.seed, 42);
      // 原笔画不动（纯函数）。
      expect(src.points[0].x, 10.0);
      expect(src.width, 5.0);
    });
  });
}
