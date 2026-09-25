// v1.17.22 分页切片预览画师回归测试（painter 已从 part 私有类外提为
// 独立文件以便直接单测）。覆盖：空 tiles 早退、正常网格绘制、极小 tile
// （fit clamp + 极窄 Paragraph 约束）不崩溃、shouldRepaint 身份比较语义。
import 'dart:ui' show Canvas, PictureRecorder, Rect, Size;

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/features/drawing/presentation/pdf_tile_preview_painter.dart';

/// 构造 rows×cols 网格 tiles（世界 100×100 每页，原点 (0,0)，行优先）。
List<Rect> gridTiles(int rows, int cols) => [
  for (var r = 0; r < rows; r++)
    for (var c = 0; c < cols; c++)
      Rect.fromLTWH(c * 100.0, r * 100.0, 100, 100),
];

void main() {
  group('PdfTilePreviewPainter.paint', () {
    test('空 tiles：提前返回，不绘制不抛', () {
      final painter = PdfTilePreviewPainter(tiles: const []);
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 300, 340));

      expect(
        () => painter.paint(canvas, const Size(300, 340)),
        returnsNormally,
      );
      recorder.endRecording().dispose();
    });

    test('正常网格（2 行 × 3 列）：完整绘制流程不抛', () {
      final painter = PdfTilePreviewPainter(tiles: gridTiles(2, 3));
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 300, 340));

      expect(
        () => painter.paint(canvas, const Size(300, 340)),
        returnsNormally,
      );
      final picture = recorder.endRecording();
      expect(picture, isNotNull);
      picture.dispose();
    });

    test('极小 tile（fit clamp 0.001 生效）：极窄 Paragraph 约束不崩溃', () {
      // 超大世界范围 → fit 被 clamp 到下限 0.001，页号 Paragraph 以接近
      // 零宽 layout（ParagraphConstraints(width: r.width)）。
      final tiles = [
        const Rect.fromLTWH(0, 0, 100, 100),
        const Rect.fromLTWH(100000, 100000, 100, 100),
      ];
      final painter = PdfTilePreviewPainter(tiles: tiles);
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 300, 340));

      expect(
        () => painter.paint(canvas, const Size(300, 340)),
        returnsNormally,
      );
      recorder.endRecording().dispose();
    });

    test('负坐标 tiles（无限画布左上方向）：并集与映射不抛', () {
      final tiles = [
        const Rect.fromLTWH(-150, -50, 100, 100),
        const Rect.fromLTWH(-50, -50, 100, 100),
        const Rect.fromLTWH(-150, 50, 100, 100),
      ];
      final painter = PdfTilePreviewPainter(tiles: tiles);
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 300, 340));

      expect(
        () => painter.paint(canvas, const Size(300, 340)),
        returnsNormally,
      );
      recorder.endRecording().dispose();
    });
  });

  group('PdfTilePreviewPainter.shouldRepaint', () {
    test('同一 tiles 实例 → false（无需重绘）', () {
      final tiles = gridTiles(1, 2);
      final painter = PdfTilePreviewPainter(tiles: tiles);
      expect(
        painter.shouldRepaint(PdfTilePreviewPainter(tiles: tiles)),
        isFalse,
      );
    });

    test('不同实例（内容相同）→ true（列表身份比较语义）', () {
      final painter = PdfTilePreviewPainter(tiles: gridTiles(1, 2));
      expect(
        painter.shouldRepaint(PdfTilePreviewPainter(tiles: gridTiles(1, 2))),
        isTrue,
      );
    });
  });
}
