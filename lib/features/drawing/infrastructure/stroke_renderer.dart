import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:perfect_freehand/perfect_freehand.dart' hide StrokePoint;

import 'package:drawing_notes_app/features/drawing/domain/stroke.dart';
import 'package:drawing_notes_app/features/drawing/infrastructure/pencil_shader.dart';

/// 笔画渲染器：将原始输入点转为连续、填充式的压感笔触轮廓。
///
/// 早期实现将笔画按压力拆成若干中心线段。粗笔书写时，一个高频压力变化就
/// 可能形成仅含一个采样点的片段，视觉上会变成“一个点一个点的大圆”。这里
/// 使用 perfect_freehand 的 MIT 轮廓算法，把完整点列生成单一封闭路径，因此
/// 粗笔、快速转向与压感变化都保持连续的触笔感。
class StrokeRenderer {
  const StrokeRenderer._();

  /// 已完成笔画的轮廓 Path 惰性缓存。
  ///
  /// 键为笔画对象本身（identity），用 Expando 持有：笔画被替换/回收时
  /// 缓存条目随 GC 释放，不会造成文档长期驻留泄漏。条目内按是否使用压感
  /// 分槽，且以 [Stroke.geometryRevision] 校验，点列替换后自动重建。
  static final Expando<_StrokeOutlineCacheEntry> _outlineCache = Expando(
    'strokeOutlineCache',
  );

  /// 保留给脏矩形计算和兼容调用的最低压感线宽系数。
  static const double minWidthFactor = 0.25;

  /// 返回已完成笔画的轮廓：命中缓存直接复用，未命中则计算并缓存。
  ///
  /// [isComplete] 为 false 时点列仍在变化，缓存无意义，直接现算。
  static Path? _cachedOutline(
    Stroke stroke, {
    required bool usePressure,
    required bool isComplete,
  }) {
    if (!isComplete) {
      return strokeOutline(stroke, usePressure: usePressure, isComplete: false);
    }

    var entry = _outlineCache[stroke];
    if (entry == null || entry.revision != stroke.geometryRevision) {
      entry = _StrokeOutlineCacheEntry(stroke.geometryRevision);
      _outlineCache[stroke] = entry;
    }

    if (usePressure) {
      return entry.withPressure ??= strokeOutline(
        stroke,
        usePressure: true,
        isComplete: true,
      );
    }
    return entry.withoutPressure ??= strokeOutline(
      stroke,
      usePressure: false,
      isComplete: true,
    );
  }

  /// 测试辅助：返回缓存中已完成的轮廓（未命中返回 null），
  /// 用于验证缓存命中与失效行为。
  @visibleForTesting
  static Path? cachedOutlineFor(
    Stroke stroke, {
    required bool usePressure,
  }) {
    final entry = _outlineCache[stroke];
    if (entry == null || entry.revision != stroke.geometryRevision) return null;
    return usePressure ? entry.withPressure : entry.withoutPressure;
  }

  /// 绘制一条笔画。
  ///
  /// [isComplete] 为 false 时用于实时预览：笔尖会平滑地略滞后于输入，减少
  /// 高频采样的抖动；收笔后的位图合成使用 true，精确落在最后一个输入点。
  static void drawStroke(
    Canvas canvas,
    Stroke stroke, {
    Color? colorOverride,
    double? opacityOverride,
    bool usePressure = true,
    bool isComplete = true,
  }) {
    final points = stroke.points;
    if (points.isEmpty) return;

    final color = colorOverride ?? stroke.color;
    final opacity = _effectiveOpacity(stroke, opacityOverride);
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true
      ..color = color.withValues(alpha: color.a * opacity)
      ..blendMode = stroke.type == BrushType.eraser
          ? BlendMode.clear
          : BlendMode.srcOver;

    // 铅笔启用颗粒着色器：用石墨纹理替代纯色填充。
    // 着色器未就绪（加载失败/不支持编译的环境）时回退到普通低透明度绘制。
    if (stroke.type == BrushType.pencil && PencilShader.isReady) {
      final shader = PencilShader.create(
        color: color,
        grainScale: (stroke.width * 0.45).clamp(2.0, 10.0),
        opacity: color.a * opacity,
      );
      if (shader != null) {
        paint
          ..color = const Color(0xFFFFFFFF) // shader 自带颜色与透明度
          ..shader = shader
          ..maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            (stroke.width * 0.12).clamp(0.5, 4.0),
          );
      }
    }

    final outline = _cachedOutline(
      stroke,
      usePressure: usePressure,
      isComplete: isComplete,
    );
    if (outline == null) return;
    canvas.drawPath(outline, paint);
  }

  /// 绘制仅用于运行时指示的激光尾迹。
  ///
  /// 激光使用恒宽轮廓与双层光效：模糊彩色外层提供可见性，较窄亮色内芯
  /// 提供“发光”触感。它的生命周期由控制器管理，不会被加入文档图层。
  static void drawLaserStroke(
    Canvas canvas,
    Stroke stroke, {
    int firstPointIndex = 0,
    double opacity = 1,
    bool isComplete = true,
  }) {
    if (stroke.points.isEmpty || opacity <= 0) return;
    final start = firstPointIndex.clamp(0, stroke.points.length - 1);
    final visibleStroke = Stroke(
      points: stroke.points.sublist(start),
      color: stroke.color,
      width: stroke.width,
      type: BrushType.laser,
    );
    final outerOutline = strokeOutline(
      visibleStroke,
      usePressure: false,
      isComplete: isComplete,
    );
    if (outerOutline == null) return;

    final outer = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true
      ..color = stroke.color.withValues(alpha: stroke.color.a * opacity * 0.62)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, stroke.width * 0.42)
      ..blendMode = BlendMode.plus;
    canvas.drawPath(outerOutline, outer);

    // 内芯使用所选颜色（修复问题2：激光中间为白色、颜色不醒目的缺陷）。
    // 参考 Saber 激光的双层同色发光思路：外层模糊营造光晕，内芯同色
    // 高不透明度保证激光清晰醒目。
    final innerStroke = Stroke(
      points: visibleStroke.points,
      color: stroke.color.withValues(alpha: 1),
      width: (stroke.width * 0.42).clamp(1.0, 100.0),
      type: BrushType.laser,
    );
    drawStroke(
      canvas,
      innerStroke,
      opacityOverride: opacity * 0.92,
      usePressure: false,
      isComplete: isComplete,
    );
  }

  /// 构建可缓存、可测试的闭合笔触轮廓。
  ///
  /// 对单击点采用显式圆形，确保所有输入设备均可产生墨点。多点笔画由
  /// `perfect_freehand` 生成平滑轮廓，真实压感来自 [StrokePoint.pressure]；
  /// 无压感指针则由调用方传入的速度模拟压力提供稳定回退。
  static Path? strokeOutline(
    Stroke stroke, {
    bool usePressure = true,
    bool isComplete = true,
  }) {
    final points = stroke.points;
    if (points.isEmpty) return null;
    if (points.length == 1) {
      final radius =
          _diameterAt(stroke, usePressure ? points.first.pressure : 1) / 2;
      return Path()
        ..addOval(Rect.fromCircle(center: points.first.offset, radius: radius));
    }

    final outline = _outlinePolygon(
      stroke,
      usePressure: usePressure,
      isComplete: isComplete,
    );
    if (outline == null) return null;

    final path = Path()..moveTo(outline.first.dx, outline.first.dy);
    for (var i = 1; i < outline.length; i++) {
      path.lineTo(outline[i].dx, outline[i].dy);
    }
    return path..close();
  }

  /// 生成笔画的轮廓点列（不构造 Path），供 PDF 矢量导出复用。
  ///
  /// 与 [strokeOutline] 共享同一 `perfect_freehand` 轮廓算法；
  /// 单击点以 32 边形近似圆，保证 SVG/PDF 中也能形成闭合填充。
  static List<Offset>? _outlinePolygon(
    Stroke stroke, {
    bool usePressure = true,
    bool isComplete = true,
  }) {
    final points = stroke.points;
    if (points.isEmpty) return null;

    final input = <PointVector>[
      for (final point in points)
        PointVector(
          point.x,
          point.y,
          usePressure ? point.pressure.clamp(0.0, 1.0) : null,
        ),
    ];
    final outline = getStroke(
      input,
      options: StrokeOptions(
        size: stroke.width,
        thinning: _thinningFor(stroke, usePressure),
        smoothing: _smoothingFor(stroke),
        streamline: _streamlineFor(stroke),
        simulatePressure: !usePressure,
        isComplete: isComplete,
        start: StrokeEndOptions.start(cap: true),
        end: StrokeEndOptions.end(cap: true),
      ),
    );
    if (outline.isEmpty) return null;
    return outline;
  }

  /// 将笔画轮廓转为 SVG path 数据（`d` 属性），供 PDF 矢量绘制使用。
  ///
  /// 单击点返回 32 边形圆；多点笔画返回 `M … L … Z` 闭合填充路径。
  /// [offset] 用于把画布坐标平移到页面坐标（光栅层坐标系）。
  /// 导出失败（无有效点）时返回 null。
  static String? strokeToSvgPath(
    Stroke stroke, {
    bool usePressure = true,
    Offset offset = Offset.zero,
  }) {
    final points = stroke.points;
    if (points.isEmpty) return null;

    final List<Offset> polygon;
    if (points.length == 1) {
      final radius =
          _diameterAt(stroke, usePressure ? points.first.pressure : 1) / 2;
      final center = points.first.offset + offset;
      const segments = 32;
      polygon = [
        for (var i = 0; i < segments; i++)
          center +
              Offset(
                radius * math.cos(2 * math.pi * i / segments),
                radius * math.sin(2 * math.pi * i / segments),
              ),
      ];
    } else {
      final outline = _outlinePolygon(stroke, usePressure: usePressure);
      if (outline == null) return null;
      polygon = [for (final point in outline) point + offset];
    }

    final buffer = StringBuffer()
      ..write('M ${_fmt(polygon.first.dx)} ${_fmt(polygon.first.dy)}');
    for (final point in polygon.skip(1)) {
      buffer.write(' L ${_fmt(point.dx)} ${_fmt(point.dy)}');
    }
    buffer.write(' Z');
    return buffer.toString();
  }

  static String _fmt(double value) {
    final rounded = value.roundToDouble();
    if ((value - rounded).abs() < 0.005) return rounded.toInt().toString();
    return value.toStringAsFixed(2);
  }

  static double _effectiveOpacity(Stroke stroke, double? override) {
    if (override != null) return override;
    // 铅笔以较低不透明度形成与钢笔可感知的石墨感，而不是只换一个图标。
    return stroke.type == BrushType.pencil
        ? stroke.opacity * 0.78
        : stroke.opacity;
  }

  static double _thinningFor(Stroke stroke, bool usePressure) {
    if (!usePressure ||
        stroke.type == BrushType.marker ||
        stroke.type == BrushType.laser ||
        stroke.type == BrushType.eraser) {
      return 0;
    }
    return switch (stroke.type) {
      BrushType.pen => 0.52,
      BrushType.pencil => 0.32,
      BrushType.marker || BrushType.laser || BrushType.eraser => 0,
    };
  }

  static double _smoothingFor(Stroke stroke) => switch (stroke.type) {
    BrushType.pen => 0.74,
    BrushType.pencil => 0.66,
    BrushType.marker => 0.58,
    BrushType.laser => 0.70,
    BrushType.eraser => 0.52,
  };

  static double _streamlineFor(Stroke stroke) => switch (stroke.type) {
    BrushType.pen => 0.46,
    BrushType.pencil => 0.38,
    BrushType.marker => 0.34,
    BrushType.laser => 0.70,
    BrushType.eraser => 0.30,
  };

  static double _diameterAt(Stroke stroke, double pressure) {
    if (stroke.type == BrushType.marker ||
        stroke.type == BrushType.laser ||
        stroke.type == BrushType.eraser) {
      return stroke.width;
    }
    final p = pressure.clamp(0.0, 1.0);
    return stroke.width * (minWidthFactor + (1 - minWidthFactor) * p);
  }

  /// 计算一条笔画的保守包围盒，用于增量脏矩形重建。
  ///
  /// 轮廓会在原始点列外扩至最多一个基础线宽半径，另加入抗锯齿和曲线过冲
  /// 余量，防止粗笔快速转向时被局部重建裁剪。
  static Rect? strokeBounds(Stroke stroke) {
    final points = stroke.points;
    if (points.isEmpty) return null;
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;
    double maxSpacing = 0;
    for (var i = 0; i < points.length; i++) {
      final point = points[i];
      minX = minX < point.x ? minX : point.x;
      minY = minY < point.y ? minY : point.y;
      maxX = maxX > point.x ? maxX : point.x;
      maxY = maxY > point.y ? maxY : point.y;
      if (i > 0) {
        final spacing = (points[i - 1].offset - point.offset).distance;
        maxSpacing = maxSpacing > spacing ? maxSpacing : spacing;
      }
    }
    final radius = stroke.width / 2;
    final overshoot = maxSpacing * 0.25;
    const antialias = 2.0;
    final inset = radius + overshoot + antialias;
    return Rect.fromLTRB(
      minX - inset,
      minY - inset,
      maxX + inset,
      maxY + inset,
    );
  }
}

/// StrokeRenderer 轮廓缓存的单个条目：按笔画几何版本校验，
/// 分别缓存带压感与不带压感的完成轮廓。
class _StrokeOutlineCacheEntry {
  _StrokeOutlineCacheEntry(this.revision);

  /// 创建条目时的笔画几何版本；不一致时整条目重建。
  int revision;

  Path? withPressure;
  Path? withoutPressure;
}
