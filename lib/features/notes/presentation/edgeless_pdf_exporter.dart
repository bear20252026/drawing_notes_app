// 无限画布整图单页 PDF 导出（v1.17.17）。
//
// 语义：所见即所得（Excalidraw 同款）——全场景包围盒（帧 + 帧外墨迹/形状 +
// 连接线含标签）渲染为一页 PDF，页面尺寸 = 包围盒世界尺寸；包围盒长边超过
// 光栅预算（8192px，对齐 notebook 管线 picture.toImage 的单边 clamp 上限）
// 时按比例缩采样。
//
// 渲染路径：
// - 帧内块内容：复用 NoteFramePreview（与屏上 _FrameCard 同一 widget 渲染，
//   只取纸面——帧头按钮/阴影/选中描边/群组框属 UI 铬，不进 PDF）；
// - 墨迹/形状/连接线：离屏 CustomPaint 重绘（视觉规则与屏上 _ElementPainter /
//   _ConnectorPainter 一致，见各 painter 注释；屏上实现含视口剔除/手势预览态
//   等交互逻辑，不适合直接复用为一次性导出路径）；
// - 离屏栅格化：独立 RenderView + RenderObjectToWidgetAdapter 私有管线
//   （screenshot 同套路，无第三方依赖），devicePixelRatio = 缩采样系数；
// - PDF 合成：复用 PdfHybridExporter 单页管线（vectorStrokes 留空——
//   EdgelessStroke 折线与 core Stroke 模型不同构，v1 全光栅，页尺寸取世界
//   尺寸保证 PDF 内缩放比例正确）。
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:drawing_notes_app/core/theme/apple_design.dart';
import 'package:drawing_notes_app/features/drawing/rendering/pdf_hybrid_exporter.dart';
import 'package:drawing_notes_app/features/notes/domain/edgeless_connector.dart';
import 'package:drawing_notes_app/features/notes/domain/edgeless_doc.dart';
import 'package:drawing_notes_app/features/notes/domain/edgeless_stroke.dart'
    show EdgelessShape, EdgelessShapeKind, EdgelessStroke;
import 'package:drawing_notes_app/features/notes/presentation/note_frame_preview.dart';
import 'package:drawing_notes_app/l10n/app_localizations.dart';

/// 光栅层长边预算（世界单位→像素 1:1 起，超出即等比缩）。
///
/// 整画布一页的量级远超纸面页（A4 300dpi ≈ 2480px）：8192 预算下单张
/// 位图 8192²×4 ≈ 268MB，栅格化 + PNG 编码卡顿明显（v1.17.17 用户反馈）。
/// 降到 4096（67MB）——PDF 观感仍远超打印精度，卡顿线性缓解。
/// （notebook 管线单页仍是 8192——纸面页量级小，不受此约束。）
const double kEdgelessPdfMaxRasterLongEdge = 4096;

/// PDF 页尺寸长边上限（磅）：PDF 规范页面不得超过 14400pt（200 英寸），
/// 超限页面在部分查看器（Adobe 系等）会被**裁剪显示**——表现为「导出的
/// PDF 缺了一块内容」（v1.17.17 用户反馈）。页尺寸等比缩至限内即可：
/// 光栅位图分辨率由光栅预算决定、不受影响，仅页面度量单位缩小，视觉
/// 比例与内容完整度不变。
const double kEdgelessPdfMaxPageLongEdgePt = 14400;

/// 页面尺寸归一：长边超 14400pt 时等比缩至限内（返回以原点为基准的
/// 页面矩形）；纯函数供单测。
Rect edgelessPdfPageBounds(Rect bounds) {
  final longEdge = math.max(bounds.width, bounds.height);
  if (longEdge <= 0 || longEdge <= kEdgelessPdfMaxPageLongEdgePt) {
    return bounds;
  }
  final scale = kEdgelessPdfMaxPageLongEdgePt / longEdge;
  return Rect.fromLTWH(0, 0, bounds.width * scale, bounds.height * scale);
}

/// 全场景包围盒：帧 + 笔迹 + 形状 + 连接线（线段、端点圆点与标签）的并集。
///
/// 屏上 `_fitTo`（v1.17.16）只算帧 + 笔迹（视野语义）；导出是「所见即所
/// 得」语义，形状与连接线（含标签）同为可见内容，一并纳入。全空返回 null。
Rect? computeEdgelessSceneBounds(EdgelessDoc doc) {
  Rect? rect;
  void add(Rect b) {
    if (b.isEmpty) return;
    rect = rect?.expandToInclude(b) ?? b;
  }

  for (final f in doc.frames) {
    add(f.rect);
  }
  for (final s in doc.strokes) {
    add(s.bounds);
  }
  for (final shape in doc.shapes) {
    add(shape.rect);
  }
  if (doc.connectors.isNotEmpty) {
    final framesById = {for (final f in doc.frames) f.id: f};
    for (final c in doc.connectors) {
      final from = framesById[c.fromFrameId];
      final to = framesById[c.toFrameId];
      if (from == null || to == null) continue;
      final a = connectorAnchorPoint(from.rect, c.fromAnchor);
      final b = connectorAnchorPoint(to.rect, c.toAnchor);
      // 线段 + 两端圆点（半径 = width + 1.5，同 _ConnectorPainter）。
      var seg = Rect.fromPoints(a, b).inflate(c.width + 1.5);
      final label = c.label;
      if (label != null && label.isNotEmpty) {
        // 标签绘制于线段中点（同 _ConnectorPainter），竖直线段时标签可能
        // 横向超出线段——按标签实测尺寸并入包围盒（样式与屏上一致）。
        final tp = TextPainter(
          text: TextSpan(
            text: label,
            style: AppleType.captionStyle(
              parseEdgelessCssColor(c.color) ?? AppleColor.actionBlue,
            ).copyWith(fontWeight: FontWeight.w600),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: 200);
        final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
        seg = seg.expandToInclude(
          Rect.fromCenter(
            center: mid,
            width: tp.width + 4,
            height: tp.height + 4,
          ),
        );
        tp.dispose();
      }
      add(seg);
    }
  }
  return rect;
}

/// 缩采样系数：长边 ≤ [maxLongEdge] 时 1:1（页像素=世界单位），否则等比缩。
double edgelessRasterScale(
  Rect bounds, {
  double maxLongEdge = kEdgelessPdfMaxRasterLongEdge,
}) {
  final longEdge = math.max(bounds.width, bounds.height);
  if (longEdge <= 0 || longEdge <= maxLongEdge) return 1;
  return maxLongEdge / longEdge;
}

/// 无限画布整图单页 PDF 导出器。
class EdgelessPdfExporter {
  const EdgelessPdfExporter._();

  /// 导出整图为单页 PDF 字节；全空画布返回 null（调用方给出「无内容」提示）。
  ///
  /// [theme] / [locale] 由页面在导出前捕获（离屏树没有 MaterialApp 祖先，
  /// 用与屏上一致的主题与语言渲染，保证所见即所得）。
  static Future<Uint8List?> export(
    EdgelessDoc doc, {
    required ThemeData theme,
    Locale? locale,
    int? jpegQuality,
  }) async {
    final bounds = computeEdgelessSceneBounds(doc);
    if (bounds == null) return null;
    // 页尺寸归一（PDF 14400pt 上限）与光栅预算独立：光栅像素密度由
    // edgelessRasterScale 决定，页尺寸只影响 PDF 度量单位。
    final image = await _rasterizeWidget(
      _buildScene(doc, bounds, theme, locale),
      bounds.size,
      edgelessRasterScale(bounds),
    );
    final Uint8List png;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      png = data!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
    return PdfHybridExporter.export(
      bounds: edgelessPdfPageBounds(bounds),
      rasterPng: png,
      vectorStrokes: const [],
      jpegQuality: jpegQuality,
    );
  }

  /// 组装整页场景（自底向上与屏上 Stack 同序：连接线 → 墨迹/形状 → 帧；
  /// 群组框是选择辅助 UI 铬，不导出）。
  ///
  /// [Localizations.locale] 非空：locale 缺省（null）时省略包装，块预览
  /// 走内置中文回退文案（与 NoteFramePreview 的 Localizations 缺失分支一致）。
  static Widget _buildScene(
    EdgelessDoc doc,
    Rect bounds,
    ThemeData theme,
    Locale? locale,
  ) {
    Widget scene = Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        // 白纸底：PDF 页面底色与帧纸面一致（不受深色模式影响）。
        Positioned.fill(
          child: ColoredBox(color: AppleColor.surfaceWhite),
        ),
        Positioned.fill(
          child: CustomPaint(
            painter: _ExportConnectorPainter(
              connectors: doc.connectors,
              framesById: {for (final f in doc.frames) f.id: f},
              origin: bounds.topLeft,
            ),
          ),
        ),
        Positioned.fill(
          child: CustomPaint(
            painter: _ExportElementPainter(
              strokes: doc.strokes,
              shapes: doc.shapes,
              origin: bounds.topLeft,
            ),
          ),
        ),
        for (final f in doc.framesSortedByZ)
          Positioned(
            left: f.x - bounds.left,
            top: f.y - bounds.top,
            width: f.w,
            height: f.h,
            child: _ExportFramePaper(
              frame: f,
              borderColor: theme.colorScheme.outlineVariant,
            ),
          ),
      ],
    );
    scene = Theme(data: theme, child: scene);
    if (locale != null) {
      scene = Localizations(
        locale: locale,
        delegates: AppLocalizations.localizationsDelegates,
        child: scene,
      );
    }
    return Directionality(textDirection: TextDirection.ltr, child: scene);
  }

  /// 离屏栅格化 [child] 为 [logicalSize]（逻辑像素）× [devicePixelRatio] 的位图。
  ///
  /// 独立 RenderView 私有管线：不影响在屏渲染；用毕整树 detach，交还 GC
  /// （管线中无 ui.Image 等需显式释放的原生资源）。
  static Future<ui.Image> _rasterizeWidget(
    Widget child,
    Size logicalSize,
    double devicePixelRatio,
  ) async {
    final binding = WidgetsBinding.instance;
    final view = binding.platformDispatcher.views.first;
    final owner = PipelineOwner(onNeedVisualUpdate: () {});
    final buildOwner = BuildOwner(focusManager: binding.focusManager);
    final boundary = RenderRepaintBoundary();
    final renderView = RenderView(
      view: view,
      configuration: ViewConfiguration(
        physicalConstraints: BoxConstraints.tight(
          logicalSize * devicePixelRatio,
        ),
        logicalConstraints: BoxConstraints.tight(logicalSize),
        devicePixelRatio: devicePixelRatio,
      ),
      child: boundary,
    );
    owner.rootNode = renderView;
    renderView.prepareInitialFrame();
    RenderObjectToWidgetAdapter<RenderBox>(
      container: boundary,
      child: child,
    ).attachToRenderTree(buildOwner);
    owner.flushLayout();
    owner.flushCompositingBits();
    owner.flushPaint();
    try {
      return await boundary.toImage(pixelRatio: devicePixelRatio);
    } finally {
      owner.rootNode = null;
      buildOwner.finalizeTree();
    }
  }
}

/// 帧纸面（导出版）：底色 + 墨色自适应 + 只读块内容。
///
/// 视觉对齐屏上 _FrameCard 的纸面部分（底色/圆角/边框/墨色规则同源）；
/// UI 铬（帧头按钮行、阴影、选中描边、角柄）不进 PDF。
class _ExportFramePaper extends StatelessWidget {
  const _ExportFramePaper({required this.frame, required this.borderColor});

  final NoteFrame frame;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    final value = int.tryParse(
          frame.background.replaceAll('#', ''),
          radix: 16,
        ) ??
        0xFFFFFF;
    final paper = Color(0xFF000000 | value);
    // 帧=纸面：文字墨色随纸面亮度自适应（同 _FrameCard）。
    final ink = paper.computeLuminance() > 0.5
        ? AppleColor.ink
        : AppleColor.surfaceWhite;
    return Container(
      decoration: BoxDecoration(
        color: paper,
        borderRadius: BorderRadius.circular(AppleRadius.md),
        border: Border.all(color: borderColor, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: NoteFramePreview(doc: frame.doc, showTitle: false, inkColor: ink),
    );
  }
}

/// 墨迹/形状导出画师（一次性离屏渲染，无缓存/剔除——屏上 _ElementPainter
/// 的视觉规则的导出镜像，交互预览态不参与）。
class _ExportElementPainter extends CustomPainter {
  _ExportElementPainter({
    required this.strokes,
    required this.shapes,
    required this.origin,
  });

  final List<EdgelessStroke> strokes;
  final List<EdgelessShape> shapes;

  /// 包围盒左上角（世界坐标）：画布先平移 −origin 把世界坐标映射到页坐标。
  final Offset origin;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(-origin.dx, -origin.dy);
    for (final shape in shapes) {
      final fill =
          parseEdgelessCssColor(shape.color) ??
          AppleColor.actionBlue.withValues(alpha: 0.20);
      final paint = Paint()..color = fill;
      if (shape.kind == EdgelessShapeKind.ellipse) {
        canvas.drawOval(shape.rect, paint);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            shape.rect,
            const Radius.circular(AppleRadius.xs),
          ),
          paint,
        );
      }
    }
    for (final stroke in strokes) {
      if (stroke.pointCount < 2) continue;
      final path = Path()
        ..moveTo(stroke.points[0], stroke.points[1]);
      for (var i = 1; i < stroke.pointCount; i++) {
        path.lineTo(stroke.points[i * 2], stroke.points[i * 2 + 1]);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color =
              parseEdgelessCssColor(stroke.color) ?? AppleColor.ink
          ..strokeWidth = stroke.width
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ExportElementPainter oldDelegate) => false;
}

/// 连接线导出画师（屏上 _ConnectorPainter 的导出镜像：线段 + 端点圆点 +
/// 中点标签，无 Expando 缓存——一次性渲染）。
class _ExportConnectorPainter extends CustomPainter {
  _ExportConnectorPainter({
    required this.connectors,
    required this.framesById,
    required this.origin,
  });

  final List<NoteConnector> connectors;
  final Map<String, NoteFrame> framesById;
  final Offset origin;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(-origin.dx, -origin.dy);
    for (final c in connectors) {
      final from = framesById[c.fromFrameId];
      final to = framesById[c.toFrameId];
      if (from == null || to == null) continue;
      final a = connectorAnchorPoint(from.rect, c.fromAnchor);
      final b = connectorAnchorPoint(to.rect, c.toAnchor);
      final color = parseEdgelessCssColor(c.color) ?? AppleColor.actionBlue;

      final line = Paint()
        ..color = color
        ..strokeWidth = c.width
        ..style = PaintingStyle.stroke;
      canvas.drawLine(a, b, line);

      final dot = Paint()..color = color;
      canvas.drawCircle(a, c.width + 1.5, dot);
      canvas.drawCircle(b, c.width + 1.5, dot);

      final label = c.label;
      if (label != null && label.isNotEmpty) {
        final tp = TextPainter(
          text: TextSpan(
            text: label,
            style: AppleType.captionStyle(
              color,
            ).copyWith(fontWeight: FontWeight.w600),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: 200);
        final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
        tp.paint(canvas, mid - Offset(tp.width / 2, tp.height / 2));
        tp.dispose();
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ExportConnectorPainter oldDelegate) => false;
}

/// CSS hex 颜色解析（`#RGB` 六位格式；失败返回 null 由调用方回退）。
///
/// 屏上各 painter 各持一份同构实现（_ElementPainter/_ConnectorPainter），
/// 导出侧为跨模型（墨迹/形状/连接线）共用而单置。
Color? parseEdgelessCssColor(String css) {
  var hex = css.replaceFirst('#', '');
  if (hex.length == 6) hex = 'FF$hex';
  if (hex.length != 8) return null;
  final value = int.tryParse(hex, radix: 16);
  return value == null ? null : Color(value);
}
