import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/features/drawing/rendering/ink_layer_painter.dart';
import 'package:drawing_notes_app/features/drawing/rendering/shape_renderer.dart';
import 'package:drawing_notes_app/features/drawing/rendering/stroke_renderer.dart';
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/selection.dart';
import 'package:drawing_notes_app/core/canvas_model/stroke.dart';
import 'package:drawing_notes_app/core/theme/apple_design.dart';

/// 画布渲染器：把"图层位图 + 活动笔画"绘制到屏幕上。
///
/// 绘制顺序（自底向上）：
/// 1. 画布背景（白色纸面，铺满整个画布区域）；
/// 2. 各可见图层位图（按图层顺序 + 各自透明度）；
/// 3. 正在绘制中的活动笔画（实时预览）；
/// 4. 选区高亮（半透明遮罩 + 边界线，Phase 4）。
///
/// 重绘机制（性能关键，修复"画笔延迟"的根因之一）：
/// - 通过 [repaint] 参数同时监听 [DrawingController]（低频状态变更）与
///   [DrawingController.frameTick]（高频绘制帧通知），任一触发即重绘画布；
/// - [shouldRepaint] 恒为 true：只要 build 传入新 painter 就重绘，
///   避免旧的 `controller != controller` 恒 false 导致画面迟迟不刷新。
///
/// 注意：本渲染器只做"绘制"，不处理手势；手势由编辑器页面负责。
class CanvasPainter extends CustomPainter {
  CanvasPainter({required this.controller})
    : super(repaint: Listenable.merge([controller, controller.frameTick]));

  final DrawingController controller;

  @override
  void paint(Canvas canvas, Size size) {
    final doc = controller.document;
    final scale = controller.viewScale;
    final offset = controller.viewOffset;
    // 无限绘图工作区的背景属于视口，不随世界坐标旋转或平移；分页笔记则
    // 由下方的有限纸张绘制其白色页面。
    if (doc.infinite) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = const Color(0xFFF4F5F7),
      );
    }

    // 变换基准点：画布文档中心（与 viewToCanvas/canvasToView 严格一致）。
    final center = doc.size.center(Offset.zero);

    // 视口变换（围绕画布中心缩放+旋转，再平移到视口）：
    //   view = R(rot)·(scale·(p - center)) + center + offset
    // 注意 canvas 变换"后写先生效"，故按逆序书写。
    canvas.save();
    canvas.translate(center.dx + offset.dx, center.dy + offset.dy);
    canvas.rotate(controller.viewRotation);
    canvas.scale(scale);
    canvas.translate(-center.dx, -center.dy);

    // 1. 分页笔记使用有限白色纸张与模板；无限绘图不绘制页面边界。
    final canvasRect = Rect.fromLTWH(
      0,
      0,
      doc.width.toDouble(),
      doc.height.toDouble(),
    );
    if (!doc.infinite) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(canvasRect, const Radius.circular(4)),
        Paint()..color = const Color(0xFFFFFFFF),
      );
      _paintPaperTemplate(canvas, doc);
    }

    // 2. 无限画布按可视区直接绘制矢量图层；分页笔记保留离屏位图缓存。
    if (doc.infinite) {
      controller.paintVectorLayers(canvas, canvas.getLocalClipBounds());
    } else {
      for (final view in controller.paintViews) {
        if (!view.visible || view.opacity <= 0) continue;
        final image = view.image;
        if (image == null) {
          // 矢量回退（2026-09-07 白纸缺陷修复）：位图未就绪——打开文档
          // 的首次光栅化进行中、全量重建窗口（旧位图已提前释放）或光栅
          // 化失败自愈期间——直接绘制笔画，保证既有内容始终可见；位图
          // 就绪后自动切回 O(1) 位图路径。隔离语义与 paintVectorLayers
          // 一致：半透明层或含橡皮擦时 saveLayer，防止 clear 清穿纸面。
          if (view.strokes.isEmpty) continue;
          final needsIsolation =
              view.opacity < 1 ||
              view.strokes.any((stroke) => stroke.type == BrushType.eraser);
          if (needsIsolation) {
            canvas.saveLayer(
              canvasRect,
              Paint()..color = Color.fromRGBO(0, 0, 0, view.opacity),
            );
          }
          InkLayerPainter.paintStrokes(canvas, canvasRect, view.strokes);
          if (needsIsolation) canvas.restore();
          continue;
        }
        final paint = Paint()
          ..color = Color.fromRGBO(0, 0, 0, view.opacity)
          ..filterQuality = FilterQuality.high;
        // 图层位图可能按长边封顶光栅化（LayerCompositor，内存治理）：
        // 以位图实际尺寸为 src、文档尺寸为 dst 统一缩放绘制。
        canvas.drawImageRect(
          image,
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
          Rect.fromLTWH(0, 0, doc.width.toDouble(), doc.height.toDouble()),
          paint,
        );
      }
    }

    // 3. 独立绘图文档的图片元素。位图由控制器惰性解码并缓存；首次加载
    // 完成后会仅刷新画布，避免整个编辑器因大图解码而卡顿。
    // U2 优化（2026-09-02，P1-14）：paint 每帧执行，List.of + sort 的
    // 分配与 O(n log n) 排序纯浪费——先 O(n) 检查是否已按 zOrder 有序
    // （新增图片走递增 zOrder，绝大多数帧已有序），仅乱序时才拷贝排序。
    final imageItems = doc.imageItems;
    var images = imageItems;
    for (var i = 1; i < imageItems.length; i++) {
      if (imageItems[i - 1].zOrder.compareTo(imageItems[i].zOrder) > 0) {
        images = List.of(imageItems)
          ..sort((a, b) => a.zOrder.compareTo(b.zOrder));
        break;
      }
    }
    for (final item in images) {
      final image = controller.documentImage(item);
      if (image == null) continue;
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Rect.fromLTWH(item.x, item.y, item.width, item.height),
        Paint()..filterQuality = FilterQuality.high,
      );
    }

    // 选中图片的可编辑边界：边框与手柄仅为运行时反馈，不会进入导出或文档数据。
    final selectedImage = controller.selectedDocumentImage;
    if (selectedImage != null) {
      _paintDocumentImageSelection(canvas, selectedImage.bounds);
    }

    // 4. 独立绘图文档的几何元素。笔记页形状由编辑器覆盖层承载，
    // 独立画布则必须直接在此处渲染，否则会出现“图标能点但画不出来”。
    for (final shape in doc.shapes) {
      ShapeRenderer.drawDocumentShape(
        canvas,
        controller.shapeForRendering(shape),
      );
    }

    // 选中形状的边界仅为运行时编辑反馈；绑定箭头使用已投影几何，故边界和
    // 实际显示/导出位置保持一致。锁定对象以琥珀色提示防误触状态。
    final selectedShape = controller.selectedDocumentShape;
    if (selectedShape != null) {
      final renderedShape = controller.shapeForRendering(selectedShape);
      _paintDocumentShapeSelection(
        canvas,
        Rect.fromLTWH(
          renderedShape.x,
          renderedShape.y,
          renderedShape.width,
          renderedShape.height,
        ),
        locked: selectedShape.locked,
      );
    }

    // 多选时显示跨笔画、形状和图片的统一包围盒。单对象仍保留上方的专属
    // 边框；混合包围盒只属于运行时反馈，不会进入导出或持久化数据。
    final mixedBounds = controller.selectedDocumentObjectsBounds;
    if (controller.selectedDocumentObjectCount > 1 && mixedBounds != null) {
      _paintSelectionFrame(
        canvas,
        mixedBounds,
        controller.mixedDocumentSelectionHasLockedObjects
            ? const Color(0xFFF59E0B)
            : AppleColor.actionBlue,
        inflate: 5,
        strokeWidth: 1.75,
        handleSize: 11,
        locked: controller.mixedDocumentSelectionHasLockedObjects,
      );
    }

    // 5. 活动笔画（正在画的这一笔实时预览）。
    // 高亮笔与已提交内容共享同一分层规则，避免收笔时视觉突变。
    final active = controller.activeStroke;
    if (active != null) {
      if (active.type == BrushType.eraser) {
        _paintPixelEraserPreview(canvas, active);
      } else if (active.type == BrushType.laser) {
        StrokeRenderer.drawLaserStroke(canvas, active, isComplete: false);
      } else {
        InkLayerPainter.paintActiveStroke(
          canvas,
          doc.infinite ? canvas.getLocalClipBounds() : canvasRect,
          active,
        );
      }
    }

    // 6. 临时荧光笔：仅用于演示/指示，不写入图层、导出或历史。
    final inkBounds = doc.infinite ? canvas.getLocalClipBounds() : canvasRect;
    for (final temporary in controller.temporaryMarkerStrokes) {
      InkLayerPainter.paintTemporaryMarker(
        canvas,
        inkBounds,
        temporary.stroke,
        opacity: temporary.opacity,
      );
    }

    // 7. 独立激光工具：从起笔端逐段退场，且永不进入保存或导出。
    for (final laser in controller.temporaryLaserStrokes) {
      StrokeRenderer.drawLaserStroke(
        canvas,
        laser.stroke,
        firstPointIndex: laser.firstPointIndex,
        opacity: laser.opacity,
      );
    }

    // 8. 选区高亮.
    _paintSelection(canvas);

    canvas.restore();
  }

  /// 绘制独立图片对象的选择边界与四角操作提示。
  void _paintDocumentImageSelection(Canvas canvas, Rect bounds) {
    _paintSelectionFrame(canvas, bounds, AppleColor.actionBlue);
  }

  /// 统一的选择框绘制：外框 + 四角手柄 + 可选锁定标记。
  ///
  /// 此前 image/shape/group 三处各写一份近似代码（仅边距/手柄尺寸/
  /// 锁定标记位置不同），现收敛到本方法。
  void _paintSelectionFrame(
    Canvas canvas,
    Rect bounds,
    Color color, {
    double inflate = 2,
    double strokeWidth = 1.5,
    double handleSize = 10,
    bool locked = false,
  }) {
    final border = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawRect(bounds.inflate(inflate), border);

    final handle = Paint()..color = const Color(0xFFFFFFFF);
    final handleBorder = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25;
    for (final corner in <Offset>[
      bounds.topLeft,
      bounds.topRight,
      bounds.bottomLeft,
      bounds.bottomRight,
    ]) {
      final handleRect = Rect.fromCenter(
        center: corner,
        width: handleSize,
        height: handleSize,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(handleRect, const Radius.circular(2)),
        handle,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(handleRect, const Radius.circular(2)),
        handleBorder,
      );
    }

    if (locked) {
      final marker = bounds.topCenter + Offset(0, -(inflate + 7));
      canvas.drawCircle(marker, 4, Paint()..color = color);
      canvas.drawCircle(marker, 1.5, Paint()..color = const Color(0xFFFFFFFF));
    }
  }

  /// 绘制独立形状对象的选择边界。锁定时保持可选择但使用琥珀色，向用户
  /// 明确说明需要先解锁才可变换或删除。
  void _paintDocumentShapeSelection(
    Canvas canvas,
    Rect bounds, {
    required bool locked,
  }) {
    final selectionColor = locked
        ? const Color(0xFFF59E0B)
        : AppleColor.actionBlue;
    _paintSelectionFrame(canvas, bounds, selectionColor, locked: locked);
    if (locked) {
      // 锁定形状额外在中心加实心点，与组选择框的顶部标记区分。
      final center = bounds.center;
      canvas.drawCircle(center, 5, Paint()..color = selectionColor);
      canvas.drawCircle(center, 2, Paint()..color = const Color(0xFFFFFFFF));
    }
  }

  /// 像素橡皮擦的实时视觉提示。
  ///
  /// 透明清除只能在与已有内容相同的合成层中正确生效；将它直接绘制到活动
  /// 预览层会出现黑色假线条。因此预览只显示轻量圆环，松开时实际透明擦除轨迹
  /// 再以 [BlendMode.clear] 提交到图层。
  void _paintPixelEraserPreview(Canvas canvas, Stroke stroke) {
    if (stroke.points.isEmpty) return;
    final point = stroke.points.last.offset;
    final paint = Paint()
      ..color = const Color(0xB0636B78)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(point, stroke.width / 2, paint);
  }

  /// 绘制纸张模板背景（仅空白页时跳过）。
  void _paintPaperTemplate(Canvas canvas, DrawingDocument doc) {
    final type = doc.paperType;
    if (type == PaperType.blank) return;

    final w = doc.width.toDouble();
    final h = doc.height.toDouble();
    final linePaint = Paint()
      ..color = const Color(0x4042A5F5)
      ..strokeWidth = 1;

    switch (type) {
      case PaperType.grid:
        // 网格：固定间距的纵横线。
        const step = 40.0;
        for (var x = 0.0; x <= w; x += step) {
          canvas.drawLine(Offset(x, 0), Offset(x, h), linePaint);
        }
        for (var y = 0.0; y <= h; y += step) {
          canvas.drawLine(Offset(0, y), Offset(w, y), linePaint);
        }
        break;
      case PaperType.lined:
        // 横线：顶部留白（标题区），下方等距横线。
        const margin = 60.0;
        const step = 48.0;
        for (var y = margin; y <= h; y += step) {
          canvas.drawLine(Offset(0, y), Offset(w, y), linePaint);
        }
        break;
      case PaperType.dot:
        // 点阵：固定间距的圆点。
        const step = 32.0;
        final dotPaint = Paint()
          ..color = const Color(0x5542A5F5)
          ..style = PaintingStyle.fill;
        for (var x = step / 2; x < w; x += step) {
          for (var y = step / 2; y < h; y += step) {
            canvas.drawCircle(Offset(x, y), 1.5, dotPaint);
          }
        }
        break;
      case PaperType.blank:
        break;
    }
  }

  /// 绘制选区：正式选区（[controller.selection]）用半透明蓝遮罩 + 实线；
  /// 正在绘制的草稿（矩形/套索进行中）用虚线轮廓实时预览。
  void _paintSelection(Canvas canvas) {
    final selection = controller.selection;
    final draft = controller.selectionDraft;

    if (selection.polygon.length >= 3) {
      final path = Path()..addPolygon(selection.polygon, true);
      // 半透明遮罩（四-2 统一：选框族蓝一律品牌 Action Blue）
      canvas.drawPath(
        path,
        Paint()
          ..color = AppleColor.actionBlue.withValues(alpha: 0.13)
          ..style = PaintingStyle.fill,
      );
      // 边界线（虚线感：用较粗 + 浅色模拟）
      canvas.drawPath(
        path,
        Paint()
          ..color = AppleColor.actionBlue
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      return;
    }

    // 草稿预览：矩形（两个点）或套索（多点）。
    if (draft.length >= 2) {
      List<Offset> pts;
      if (controller.selectionTool == SelectionTool.rect) {
        final a = draft.first;
        final b = draft.last;
        pts = [a, Offset(b.dx, a.dy), b, Offset(a.dx, b.dy)];
      } else {
        pts = draft;
      }
      final path = Path()..addPolygon(pts, true);
      canvas.drawPath(
        path,
        Paint()
          ..color = AppleColor.actionBlue.withValues(alpha: 0.53)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }
  }

  @override
  bool shouldRepaint(CanvasPainter oldDelegate) => true;
}

/// 画布小地图渲染器（借鉴 Relatum：整幅缩略图 + 当前视口框）。
///
/// 绘制内容：
/// 1. 各图层位图按 miniScale 缩放到小地图区域（白纸底）；
/// 2. 当前视口（可见区域）矩形框，随缩放/平移实时更新。
class MiniMapPainter extends CustomPainter {
  const MiniMapPainter({
    required this.controller,
    required this.miniScale,
    required this.viewport,
  });

  final DrawingController controller;
  final double miniScale;
  final Size viewport;

  @override
  void paint(Canvas canvas, Size size) {
    // 白纸底。
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFFFFFFFF),
    );

    // 各图层缩略（只画可见层）。
    for (final view in controller.paintViews) {
      final image = view.image;
      if (image == null || !view.visible || view.opacity <= 0) continue;
      // src 用位图实际尺寸（可能已按长边封顶），dst 映射到小地图区域。
      final src = Rect.fromLTWH(
        0,
        0,
        image.width.toDouble(),
        image.height.toDouble(),
      );
      final dst = Rect.fromLTWH(0, 0, size.width, size.height);
      canvas.drawImageRect(
        image,
        src,
        dst,
        Paint()
          ..color = Color.fromRGBO(0, 0, 0, view.opacity)
          ..filterQuality = FilterQuality.medium,
      );
    }

    // 当前视口框：视口中心对应的画布坐标 + 视口尺寸/缩放。
    final vc = Offset(viewport.width / 2, viewport.height / 2);
    final canvasCenter = controller.viewToCanvas(vc);
    // 视口尺寸在画布坐标下的范围（未旋转时精确；旋转时取外接框近似）。
    final w = viewport.width / controller.viewScale;
    final h = viewport.height / controller.viewScale;
    final rectOnCanvas = Rect.fromCenter(
      center: canvasCenter,
      width: w,
      height: h,
    );
    // 画布坐标 -> 小地图坐标。
    final rectOnMap = Rect.fromLTRB(
      rectOnCanvas.left * miniScale,
      rectOnCanvas.top * miniScale,
      rectOnCanvas.right * miniScale,
      rectOnCanvas.bottom * miniScale,
    );
    canvas.drawRect(
      rectOnMap,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = AppleColor.actionBlue,
    );
    canvas.drawRect(
      rectOnMap,
      Paint()
        ..style = PaintingStyle.fill
        ..color = const Color(0x2242A5F5),
    );
  }

  @override
  bool shouldRepaint(MiniMapPainter oldDelegate) => true;
}
