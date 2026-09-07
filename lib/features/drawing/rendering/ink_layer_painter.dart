import 'dart:ui';

import 'package:drawing_notes_app/core/canvas_model/stroke.dart';
import 'package:drawing_notes_app/features/drawing/rendering/stroke_renderer.dart';

/// 文档墨迹的分层绘制策略。
///
/// 高亮笔不是普通的半透明线条。将同色高亮笔先绘入独立图层并以
/// [BlendMode.darken] 合成，可以避免交叠区域变脏，同时保证普通墨迹
/// 始终绘制在高亮笔上方。该实现独立于 Saber 的 GPLv3 源码。
class InkLayerPainter {
  const InkLayerPainter._();

  // ---- cull/plan 单槽缓存（渲染性能 2026-09-07）----
  // 活动绘制期间 paintStrokes 每帧执行：每次 cullStrokes 新建 List、
  // InkRenderPlan.fromStrokes 新分配纯属浪费。按 (strokes 引用, 长度,
  // 内容指纹, bounds) 缓存，输入未变则直接复用上次结果。
  // 失效前提（调用方现状）：canvas_painter / layer_compositor 等传入
  // 图层笔画列表的稳定引用，增删笔画必改变长度；点列替换走
  // Stroke.replacePoints（version 递增）；整条替换（移动/缩放重建对象）
  // 改变元素 identity——三者都进指纹。
  static Iterable<Stroke>? _cachedStrokes;
  static Rect _cachedBounds = Rect.zero;
  static int _cachedFingerprint = 0;
  static List<Stroke>? _cachedVisible;
  static InkRenderPlan? _cachedPlan;

  /// 内容指纹：元素 identity（捕获整条替换）+ version（捕获
  /// replacePoints 点列替换）+ 长度（捕获增删）。O(n) 整数运算。
  static int _fingerprintOf(Iterable<Stroke> strokes) {
    var result = 0;
    for (final stroke in strokes) {
      result = Object.hash(result, identityHashCode(stroke), stroke.version);
    }
    return result;
  }

  /// 绘制一个完整图层的笔画。
  ///
  /// 为确保文字/普通笔画可读，所有高亮笔始终先绘制；橡皮擦则保留在
  /// 普通队列中，依序以 [BlendMode.clear] 作用于已合成的内容。
  ///
  /// U2 视口剔除（2026-09-02，P1-8）：包围盒与 [bounds]（调用方的裁剪
  /// 范围）不相交的笔画直接跳过——包围盒由 StrokeRenderer 缓存，剔除
  /// 查询为 O(1)/条。所有调用方传入的都是裁剪/页界语义，剔除恒安全。
  static void paintStrokes(
    Canvas canvas,
    Rect bounds,
    Iterable<Stroke> strokes,
  ) {
    final fingerprint = _fingerprintOf(strokes);
    if (!identical(_cachedStrokes, strokes) ||
        _cachedBounds != bounds ||
        _cachedFingerprint != fingerprint ||
        _cachedVisible == null ||
        _cachedPlan == null) {
      _cachedVisible = cullStrokes(strokes, bounds);
      _cachedPlan = InkRenderPlan.fromStrokes(_cachedVisible!);
      _cachedStrokes = strokes;
      _cachedBounds = bounds;
      _cachedFingerprint = fingerprint;
    }
    final plan = _cachedPlan!;
    for (final strokesForColor in plan.markerGroups) {
      _paintMarkerColorGroup(canvas, bounds, strokesForColor);
    }
    for (final stroke in plan.normalStrokes) {
      StrokeRenderer.drawStroke(canvas, stroke);
    }
  }

  /// 纯函数剔除：返回包围盒与 [clip] 相交的笔画（可测试，无图形后端）。
  static List<Stroke> cullStrokes(Iterable<Stroke> strokes, Rect clip) {
    return strokes
        .where(
          (stroke) =>
              StrokeRenderer.strokeBounds(stroke)?.overlaps(clip) ??
              // 无点笔画（空点列）不产生视觉输出，剔除安全。
              false,
        )
        .toList(growable: false);
  }

  /// 绘制正在书写的单条笔画。
  static void paintActiveStroke(Canvas canvas, Rect bounds, Stroke stroke) {
    if (stroke.type == BrushType.marker) {
      _paintMarkerColorGroup(canvas, bounds, [stroke], isComplete: false);
      return;
    }
    StrokeRenderer.drawStroke(canvas, stroke, isComplete: false);
  }

  /// 绘制一条不会进入文档的临时荧光笔，并按 [opacity] 平滑淡出。
  ///
  /// 使用外层 alpha 合成，而非修改 marker 的颜色/笔画透明度，保证仍沿用
  /// 高亮笔的同色分组和 `darken` 混合规则。
  static void paintTemporaryMarker(
    Canvas canvas,
    Rect bounds,
    Stroke stroke, {
    required double opacity,
  }) {
    if (opacity <= 0) return;
    canvas.saveLayer(
      bounds,
      Paint()..color = Color.fromRGBO(0, 0, 0, opacity.clamp(0.0, 1.0)),
    );
    _paintMarkerColorGroup(canvas, bounds, [stroke]);
    canvas.restore();
  }

  static void _paintMarkerColorGroup(
    Canvas canvas,
    Rect bounds,
    Iterable<Stroke> strokes, {
    bool isComplete = true,
  }) {
    // 以白色半透明层与深色混合实现纸面上的真实荧光笔质感。所有同色
    // 笔画共享一个合成层，重叠部分不会因 srcOver 而反复增加不透明度。
    final layerPaint = Paint()
      ..blendMode = BlendMode.darken
      ..color = const Color(0x64FFFFFF);
    canvas.saveLayer(bounds, layerPaint);
    for (final stroke in strokes) {
      StrokeRenderer.drawStroke(
        canvas,
        stroke,
        colorOverride: stroke.color.withValues(alpha: 1),
        opacityOverride: 1,
        usePressure: false,
        isComplete: isComplete,
      );
    }
    canvas.restore();
  }
}

/// 可测试的墨迹渲染顺序。
///
/// 高亮笔按颜色分组后先绘制，普通墨迹随后绘制。该对象只描述顺序，
/// 不持有 Canvas 或位图资源，便于在无图形后端的测试环境中验证。
class InkRenderPlan {
  InkRenderPlan._({required this.markerGroups, required this.normalStrokes});

  final List<List<Stroke>> markerGroups;
  final List<Stroke> normalStrokes;

  factory InkRenderPlan.fromStrokes(Iterable<Stroke> strokes) {
    final markersByColor = <int, List<Stroke>>{};
    final normalStrokes = <Stroke>[];
    for (final stroke in strokes) {
      if (stroke.type == BrushType.marker) {
        final key = stroke.color.toARGB32();
        (markersByColor[key] ??= <Stroke>[]).add(stroke);
      } else {
        normalStrokes.add(stroke);
      }
    }
    return InkRenderPlan._(
      markerGroups: markersByColor.values.toList(growable: false),
      normalStrokes: normalStrokes,
    );
  }
}
