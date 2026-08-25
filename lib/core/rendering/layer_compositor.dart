import 'dart:ui' as ui;
import 'dart:ui' show Offset, Rect;

import '../../features/drawing/domain/layer.dart';
import '../../features/drawing/domain/stroke.dart';
import 'ink_layer_painter.dart';
import 'stroke_picture_cache.dart';
import 'stroke_renderer.dart';

/// 图层的离屏渲染缓存。
///
/// 性能设计：把图层的全部笔画提前合成为一张位图 [image]，
/// 每次重绘时只需 drawImage 一次，避免逐笔刷反复重建 Path，
/// 保证画布"跟手不卡顿"（Phase 1 验收的核心指标）。
///
/// 缓存失效策略：任何改变图层内容的操作（新增笔画、撤销、合并、
/// 选区变换等）都会把对应图层的 [dirty] 置为 true，重建后清除。
class LayerRenderCache {
  ui.Image? image;
  bool dirty = true;

  /// 增量重建的脏矩形（null = 整层重建）。
  /// 只对新笔画包围盒区域重建，区域外保持旧内容（性能优化）。
  Rect? dirtyRegion;

  void dispose() {
    image?.dispose();
    image = null;
  }
}

/// 图层内容合成器：负责把某图层的笔画列表光栅化为位图。
class LayerCompositor {
  /// [pictureCache] 非 null 时启用笔画集合的 Picture 缓存
  /// （借鉴 scribe_canvas cachedPicture 的 O(1) 重绘思想）：
  /// 全量重建时命中指纹直接 drawPicture，避免逐笔画重建轮廓。
  /// null = 回退旧路径（增量/逐笔画绘制），保证可随时回滚。
  const LayerCompositor({this.pictureCache});

  /// 可选的笔画集合 Picture 缓存（null = 关闭，走原路径）。
  final StrokePictureCache? pictureCache;

  /// 把 [layer] 的笔画光栅化到 [width]x[height] 的透明位图上。
  ///
  /// [width]/[height] 即画布逻辑尺寸（像素）。
  /// 橡皮擦笔画使用 clear 混合模式，在同一层内实现透明擦除。
  /// [region] 非空时执行增量脏矩形重建：先绘制 [base]（旧位图，保留
  /// 区域外内容），再只在 [region] 内重绘相交笔画（性能优化）。
  /// [base] 仅增量模式使用，全量重建时传 null。
  Future<ui.Image> rasterize(
    Layer layer,
    int width,
    int height, {
    Rect? region,
    ui.Image? base,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    // 同色高亮笔依赖整层离屏合成，局部重绘会把新高亮再次与旧位图
    // srcOver 叠加，破坏“不叠色”承诺。因此此类图层始终全量重建。
    final hasHighlighter = layer.strokes.any(
      (stroke) => stroke.type == BrushType.marker,
    );
    final effectiveRegion = hasHighlighter ? null : region;
    final effectiveBase = hasHighlighter ? null : base;

    // saveLayer 必须覆盖整个画布（而非仅脏矩形）：
    // 1) base（旧位图）画入后，区域外内容随 restore 原样保留；
    // 2) 橡皮擦的 clear 才能作用于底图（clear 只清除 saveLayer 内合成内容）。
    // 性能收益在 CPU 端：clipRect(region) 只重绘脏矩形内的笔画。
    final fullBounds = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
    canvas.saveLayer(fullBounds, ui.Paint());
    // 增量重建：先画旧位图作为底（全图），区域外内容保持不变。
    if (effectiveBase != null) {
      canvas.drawImage(effectiveBase, Offset.zero, ui.Paint());
    }
    // 只重绘脏矩形内的笔画（渲染裁剪）。
    final paintBounds = effectiveRegion ?? fullBounds;
    if (effectiveRegion != null) {
      canvas.clipRect(paintBounds);
      for (final stroke in layer.strokes) {
        final sb = StrokeRenderer.strokeBounds(stroke);
        if (sb == null || !sb.overlaps(paintBounds)) continue;
        StrokeRenderer.drawStroke(canvas, stroke);
      }
    } else {
      // 全量重建：优先走 Picture 缓存（无 marker 时），命中直接
      // drawPicture（O(1) 重绘）；未命中/未启用则逐笔画绘制原路径。
      final cached = pictureCache;
      if (cached != null && !hasHighlighter) {
        final pic = cached.pictureFor(
          layer.strokes,
          size: ui.Size(width.toDouble(), height.toDouble()),
        );
        if (pic != null) {
          canvas.drawPicture(pic);
        } else {
          InkLayerPainter.paintStrokes(canvas, fullBounds, layer.strokes);
        }
      } else {
        InkLayerPainter.paintStrokes(canvas, fullBounds, layer.strokes);
      }
    }
    canvas.restore();

    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(width, height);
      picture.dispose();
      return image;
    } catch (e) {
      // 极端情况下光栅化失败（内存不足等），记录并抛出让上层处理。
      picture.dispose();
      rethrow;
    }
  }
}

/// 文档级渲染快照：为 CustomPainter 提供"图层位图 + 显示属性"的只读视图。
///
/// 注意：这里只持有 [ui.Image] 的引用，不负责其生命周期
/// （生命周期由 DrawingController 管理）。
class LayerPaintView {
  const LayerPaintView({
    required this.image,
    required this.visible,
    required this.opacity,
  });

  final ui.Image? image;
  final bool visible;
  final double opacity;
}
