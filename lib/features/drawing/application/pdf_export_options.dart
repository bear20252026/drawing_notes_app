library;

/// PDF 导出二级面板选项（纯 Dart，无 Widget/io 依赖，可单测锁定）。
///
/// 三组档位（用户拍板）：
/// - 纸张：A4 / Letter / 跟随画布（默认 A4）；
/// - 范围：当前页 / 全部页（分页画布天然多页；独立画布仅一页，面板隐藏该行）；
/// - 质量：无损（PNG）/ 标准（JPEG 80）/ 省流量（JPEG 60）。
import 'dart:ui' as ui;

import 'package:drawing_notes_app/core/canvas_model/stroke.dart';

/// 纸张档位（PDF 点：1pt = 1/72 英寸）。
enum PdfPaper {
  /// A4：210×297mm = 595.28×841.89pt。
  a4,

  /// Letter：8.5×11in = 612×792pt。
  letter,

  /// 跟随画布：页尺寸 = 内容边界（既有单页导出行为，零变化）。
  canvas,
}

/// 范围档位。
enum PdfRange {
  /// 仅当前页/当前画布。
  currentPage,

  /// 整本全部页（笔记本分页；独立画布无此选项）。
  allPages,
}

/// 质量档位（光栅层 JPEG 压缩；钢笔矢量永远无损）。
enum PdfQuality {
  /// PNG 无损（`jpegQuality: null`；含文本/形状时推荐）。
  lossless,

  /// JPEG 80（标准）。
  standard,

  /// JPEG 60（省流量）。
  saver,
}

/// 纸张尺寸（pt）。
extension PdfPaperSize on PdfPaper {
  /// A4 / Letter 的页面尺寸；[PdfPaper.canvas] 返回 null（调用方用画布边界）。
  ui.Size? get pageSize => switch (this) {
    PdfPaper.a4 => const ui.Size(595.28, 841.89),
    PdfPaper.letter => const ui.Size(612, 792),
    PdfPaper.canvas => null,
  };

  String get label => switch (this) {
    PdfPaper.a4 => 'A4',
    PdfPaper.letter => 'Letter',
    PdfPaper.canvas => '跟随画布',
  };
}

extension PdfRangeLabel on PdfRange {
  String get label => switch (this) {
    PdfRange.currentPage => '当前页',
    PdfRange.allPages => '全部页',
  };
}

extension PdfQualitySetting on PdfQuality {
  /// 引擎 `jpegQuality` 参数；null = PNG 无损。
  int? get jpegQuality => switch (this) {
    PdfQuality.lossless => null,
    PdfQuality.standard => 80,
    PdfQuality.saver => 60,
  };

  String get label => switch (this) {
    PdfQuality.lossless => '无损',
    PdfQuality.standard => '标准 80',
    PdfQuality.saver => '省流量 60',
  };

  /// 选项说明（面板副标题用）。
  String get hint => switch (this) {
    PdfQuality.lossless => 'PNG 无损，体积最大',
    PdfQuality.standard => 'JPEG 80，推荐',
    PdfQuality.saver => 'JPEG 60，体积最小',
  };
}

/// 纸张适配：将画布内容框等比放入纸张并居中。
///
/// 返回 `(scale, offset)`：内容点 `p` → 纸张点 `p * scale + offset`
///（`offset` 即信纸居中位移）。`scale` 钳制 ≤4（极小内容不爆分辨率）。
/// 跟随画布模式返回 `(1, Offset.zero)`（零变化）。
({double scale, ui.Offset offset}) fitContentOnPaper(
  PdfPaper paper, {
  required ui.Size content,
}) {
  if (paper == PdfPaper.canvas || content.width <= 0 || content.height <= 0) {
    return (scale: 1.0, offset: ui.Offset.zero);
  }
  final paperSize = paper.pageSize!;
  var scale = paperSize.width / content.width;
  final sy = paperSize.height / content.height;
  if (sy < scale) scale = sy;
  if (scale > 4) scale = 4;
  if (scale <= 0) scale = 1.0;
  return (
    scale: scale,
    offset: ui.Offset(
      (paperSize.width - content.width * scale) / 2,
      (paperSize.height - content.height * scale) / 2,
    ),
  );
}

/// 笔画纸张变换（纯函数）：点列 ×scale +位移，线宽 ×scale，
/// 颜色/类型/透明度/seed 原样保留（手绘质感一致）。
Stroke scaleStrokeForPaper(Stroke stroke, double scale, ui.Offset offset) {
  return Stroke(
    points: [
      for (final p in stroke.points)
        StrokePoint(
          p.x * scale + offset.dx,
          p.y * scale + offset.dy,
          p.pressure,
        ),
    ],
    color: stroke.color,
    width: stroke.width * scale,
    type: stroke.type,
    opacity: stroke.opacity,
    seed: stroke.seed,
  );
}
