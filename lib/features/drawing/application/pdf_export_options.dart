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

/// 独立画布布局档位（v1.17.20）：导出成一页超大页面，还是按纸张切成
/// 常规多页（可打印、不受 PDF 14400pt 页面上限约束、每页光栅小不卡顿）。
enum PdfLayout {
  /// 单页大图（既有行为零变化）：页尺寸 = 内容边界/纸张适配。
  single,

  /// 按纸张分页：内容包围盒按纸张纵横比切片，每页一张常规纸。
  tiled,
}

extension PdfLayoutLabel on PdfLayout {
  String get label => switch (this) {
    PdfLayout.single => '单页大图',
    PdfLayout.tiled => '按纸张分页',
  };
}

/// 分页导出页数上限：超过提示改用更大纸张/缩小内容（防止对超大包围盒
/// 生成上千页的失控导出）。
const int kPdfTiledMaxPages = 200;

/// 分页导出输出缩放口径（v1.17.23 审计修复）：固定 1.0——世界 px 与纸张
/// pt 1:1，每页光栅 = 纸张分辨率（renderToPng 1px/pt，与单页大图档的
/// 实际密度一致）。
///
/// 绝不可复用 [fitContentOnPaper]：它保证整幅内容放进一张纸
///（`content·s ≤ 纸宽`），代入切片公式得 `cols = rows = 1`——
/// v1.17.20/22 的分页链路因此恒产出单页（审计 2026-09-26 #1）。
/// 分页的语义就是把大内容摊到多张常规纸上，必须用固定输出 scale。
const double kPdfTiledOutputScale = 1.0;

/// 无限画布分页切片（纯函数）：内容包围盒按纸张纵横比切成 ceil 网格页。
///
/// [pageSize] 为纸张 pt 尺寸，[scale] 为内容→纸张缩放系数；每页承载的
/// 世界尺寸 = 纸张 pt ÷ scale。返回世界坐标页矩形（行优先），页与页首尾
/// 相接不重叠；[content] 为空或参数非法时返回空表。
///
/// [columnMajor]（v1.17.22 页序档位）：false = 先横后纵（行优先，默认）；
/// true = 先纵后横（列优先——纵向长内容如时间线/笔记流按书写方向排页）。
///
/// [maxPages]（v1.17.23 审计修复 #27）：非 null 且 `rows × cols` 超限时
/// **在物化前**直接返回空表——切片网格不物化，防超大包围盒生成海量
/// Rect 卡主 isolate；null = 不限制。
List<ui.Rect> sliceContentIntoPages(
  ui.Rect content, {
  required ui.Size pageSize,
  required double scale,
  bool columnMajor = false,
  int? maxPages,
}) {
  if (content.width <= 0 ||
      content.height <= 0 ||
      pageSize.width <= 0 ||
      pageSize.height <= 0 ||
      scale <= 0) {
    return const [];
  }
  final pageW = pageSize.width / scale;
  final pageH = pageSize.height / scale;
  final cols = (content.width / pageW).ceil().clamp(1, 1 << 20);
  final rows = (content.height / pageH).ceil().clamp(1, 1 << 20);
  if (maxPages != null && rows * cols > maxPages) {
    return const [];
  }
  ui.Rect tile(int r, int c) => ui.Rect.fromLTWH(
    content.left + c * pageW,
    content.top + r * pageH,
    pageW,
    pageH,
  );
  if (columnMajor) {
    return [
      for (var c = 0; c < cols; c++)
        for (var r = 0; r < rows; r++) tile(r, c),
    ];
  }
  return [
    for (var r = 0; r < rows; r++)
      for (var c = 0; c < cols; c++) tile(r, c),
  ];
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
