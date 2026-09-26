// 分页切片预览画师（v1.17.22）：把分页导出的 tiles 世界矩形网格按页序号
// 画进一个自适应缩放的预览框——白纸页 + 页界线 + 页号。
// 独立成文件以便直接单测（原为 editor_page_persistence part 内私有类）。
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import '../../../core/theme/apple_design.dart';

/// 分页切片预览画师（v1.17.22）：把 tiles 的世界矩形网格按页序号画进
/// 一个自适应缩放的预览框——白纸页 + 页界线 + 页号。
class PdfTilePreviewPainter extends CustomPainter {
  PdfTilePreviewPainter({required this.tiles});

  final List<ui.Rect> tiles;

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    if (tiles.isEmpty) return;
    // 全部 tiles 的并集（= 内容包围盒按整页对齐后的范围）。
    var union = tiles.first;
    for (final t in tiles.skip(1)) {
      union = union.expandToInclude(t);
    }
    const pad = 16.0;
    final availW = size.width - pad * 2;
    final availH = size.height - pad * 2;
    final fit = math
        .min(availW / union.width, availH / union.height)
        .clamp(0.001, 8.0);
    final offset = Offset(
      pad + (availW - union.width * fit) / 2,
      pad + (availH - union.height * fit) / 2,
    );

    ui.Rect map(ui.Rect world) => ui.Rect.fromLTWH(
      offset.dx + (world.left - union.left) * fit,
      offset.dy + (world.top - union.top) * fit,
      world.width * fit,
      world.height * fit,
    );

    // 画布底（世界范围外的空白区）。
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = AppleColor.surfaceWhite,
    );
    // 各页：白纸 + 灰界线 + 页号。
    // 审计 2026-09-26 #25：页纸白色统一走 AppleColor.surfaceWhite（与画布
    // 底同源，原此处双写 0xFFFFFFFF）；页号字号随页框显示尺寸自适应
    //（多页大内容 fit 缩小后页框不足 10px，固定字号会溢出页框互相重叠）。
    final pageFill = Paint()..color = AppleColor.surfaceWhite;
    final pageBorder = Paint()
      ..color = AppleColor.inkMuted.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 0; i < tiles.length; i++) {
      final r = map(tiles[i]);
      canvas.drawRect(r, pageFill);
      canvas.drawRect(r, pageBorder);
      final fontSize = math.min(10.0, math.max(3.0, r.shortestSide / 4));
      final textStyle = ui.TextStyle(color: AppleColor.ink, fontSize: fontSize);
      final builder = ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: fontSize))
        ..pushStyle(textStyle)
        ..addText('${i + 1}');
      final para = builder.build()
        ..layout(ui.ParagraphConstraints(width: math.max(r.width, 8)));
      canvas.drawParagraph(para, Offset(r.left + 2, r.top + 2));
    }
    // 内容包围盒虚线：页网格恒等于内容包围盒按整页对齐，这里画外框强调。
    canvas.drawRect(map(union), pageBorder);
  }

  @override
  bool shouldRepaint(covariant PdfTilePreviewPainter old) => old.tiles != tiles;
}
