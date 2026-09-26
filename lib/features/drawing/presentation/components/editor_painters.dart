// 绘图展示层画笔集合（F9 自 editor_components.dart 拆出，2026-09-24）：
// 连接线/形状/吸附线/框选/网格/图表/尾迹等 CustomPainter。位于 components/
// 子目录。使用方继续 import editor_components.dart（桶兼容）或直接本文件。

import 'dart:math' as math;
import 'package:flutter/foundation.dart' show listEquals, mapEquals;
import 'package:flutter/material.dart';
import 'package:drawing_notes_app/core/theme/apple_design.dart';
import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/features/drawing/rendering/shape_binding_geometry.dart';
import 'package:drawing_notes_app/core/canvas_model/page_chart_item.dart';
import 'package:drawing_notes_app/core/canvas_model/page_connector.dart';
import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';

({double scale, double rotation, Offset offset}) _snapshotViewportOf(
  DrawingController controller,
) => (
  scale: controller.viewScale,
  rotation: controller.viewRotation,
  offset: controller.viewOffset,
);

/// 连接线渲染器（D1：节点关联标注，借鉴 Relatum 连线）。
///
/// 在页面混排对象（文字/图片块）之间画连线，坐标随画布视口变换。
class ConnectorPainter extends CustomPainter {
  /// 直接持有调用方集合的引用，不再逐次 `List/Map.unmodifiable` 拷贝
  /// （渲染性能 2026-09-07）。前提：调用方（editor_page_canvas_surface
  /// 的 frameTick 重建）每次 build 传入新建的快照 map 与只读的
  /// session 列表，数据不可变；本 painter 不修改它们。
  ConnectorPainter({
    required this.connectors,
    required this.itemPositions,
    required this.controller,
  }) : _viewport = _snapshotViewportOf(controller);

  final List<PageConnector> connectors;
  final Map<String, Offset> itemPositions;
  final DrawingController controller;
  final ({double scale, double rotation, Offset offset}) _viewport;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppleColor.actionBlue.withValues(alpha: 0.53)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    for (final c in connectors) {
      final from = _itemPosition(c.fromItemId);
      final to = _itemPosition(c.toItemId);
      if (from == null || to == null) continue;
      // 画布坐标 -> 视图坐标。
      final vFrom = controller.canvasToView(from);
      final vTo = controller.canvasToView(to);
      canvas.drawLine(vFrom, vTo, paint);
      // 箭头（指向 to 端的小三角）。
      final angle = (vTo - vFrom).direction;
      const arrowLen = 10.0;
      final arrow = Path()
        ..moveTo(vTo.dx, vTo.dy)
        ..lineTo(
          vTo.dx - arrowLen * math.cos(angle - 0.4),
          vTo.dy - arrowLen * math.sin(angle - 0.4),
        )
        ..lineTo(
          vTo.dx - arrowLen * math.cos(angle + 0.4),
          vTo.dy - arrowLen * math.sin(angle + 0.4),
        )
        ..close();
      canvas.drawPath(arrow, Paint()..color = AppleColor.actionBlue);
    }
  }

  /// 查询导出时捕获的混排对象位置（画布坐标），无则返回 null。
  Offset? _itemPosition(String id) => itemPositions[id];

  @override
  bool shouldRepaint(ConnectorPainter oldDelegate) =>
      oldDelegate._viewport != _viewport ||
      oldDelegate.controller != controller ||
      !listEquals(oldDelegate.connectors, connectors) ||
      !mapEquals(oldDelegate.itemPositions, itemPositions);
}

/// 形状元素渲染器（借鉴 Excalidraw 图形工具）。
///
/// 按 [PageShapeItem.shapeType] 绘制矩形/椭圆/菱形/箭头/直线，
/// 支持描边色、填充色与线宽；坐标基于元素外接框（0,0 → width,height）。
class ShapePainter extends CustomPainter {
  const ShapePainter({required this.shape, required this.viewScale});

  final PageShapeItem shape;
  final double viewScale;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = Color(shape.color)
      ..style = PaintingStyle.stroke
      // 线宽不随画布缩放（保持视觉一致，Excalidraw 同款行为）。
      ..strokeWidth = shape.strokeWidth
      ..strokeCap = StrokeCap.round;
    final fill = shape.fillColor != null
        ? (Paint()
            ..color = Color(shape.fillColor!).withValues(alpha: 0.25)
            ..style = PaintingStyle.fill)
        : null;

    final rect = Offset.zero & size;
    final center = size.center(Offset.zero);

    // 手绘风格（借鉴 Excalidraw/rough.js）：seeded 随机抖动顶点，
    // 绘制 2 次轻微偏移的描边，形成"手绘不完美"的粗糙边缘。
    final rough = shape.rough;

    Path dashPath(Path path) {
      if (!shape.dash) return path;
      final out = Path();
      for (final metric in path.computeMetrics()) {
        var d = 0.0;
        while (d < metric.length) {
          out.addPath(metric.extractPath(d, d + 8), Offset.zero);
          d += 16;
        }
      }
      return out;
    }

    final rng = math.Random(shape.id.hashCode);
    Offset j(Offset p) => rough
        ? p + Offset(rng.nextDouble() * 4 - 2, rng.nextDouble() * 4 - 2)
        : p;
    void drawStroke(Path path) {
      if (!rough) {
        canvas.drawPath(dashPath(path), stroke);
        return;
      }
      // 手绘：两条轻微偏移的描边叠加（rough.js 多重描边思路）。
      canvas.drawPath(dashPath(path), stroke);
      final rough2 = Path.from(path);
      // 整体再偏移一次（2px），强化手绘感。
      final shift = Offset(
        rng.nextDouble() * 3 - 1.5,
        rng.nextDouble() * 3 - 1.5,
      );
      canvas.drawPath(dashPath(rough2.shift(shift)), stroke);
    }

    // 手绘粗糙填充（借鉴 Excalidraw/rough.js）：rough 且有填充色时，
    // 用一组斜线阴影填充（而非纯色），形成"手绘涂色"质感。
    void roughFill(Path clipPath) {
      if (!shape.rough || shape.fillColor == null) return;
      final hatch = Paint()
        ..color = Color(shape.fillColor!).withValues(alpha: 0.55)
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round;
      final rng2 = math.Random(shape.id.hashCode ^ 0x5A);
      final angle = 0.7 + rng2.nextDouble() * 0.2; // 斜线角度微随机
      final spacing = 7.0;
      canvas.save();
      canvas.clipPath(clipPath);
      final diag = math.sqrt(
        size.width * size.width + size.height * size.height,
      );
      for (var d = -diag; d < diag; d += spacing) {
        final dx = math.cos(angle) * d;
        final dy = math.sin(angle) * d;
        canvas.drawLine(
          Offset(dx, dy),
          Offset(
            dx + math.cos(angle + math.pi / 2) * diag * 2,
            dy + math.sin(angle + math.pi / 2) * diag * 2,
          ),
          hatch,
        );
      }
      canvas.restore();
    }

    // 显式端点是画布坐标（相对外接框），本绘制层处于 viewScale 换算后的
    // 视图坐标——必须乘 viewScale，否则缩放≠100% 时线性元素端点错位
    // （fallback 对角线本来就是视图坐标，无需换算）。
    Offset endpoint(Offset? local, Offset fallback) =>
        local != null ? local * viewScale : fallback;

    // 虚线样式（借鉴 Excalidraw 线样式面板）：dash 时用虚线绘制描边。
    switch (shape.shapeType) {
      case ShapeType.rect:
        // 仅填充模式绘制内部颜色；非填充模式中间保持透明纸色，
        // 避免默认 Paint()（黑色实心）造成"绘制中中间全黑"（问题6）。
        if (fill != null) {
          fill.color = Color(shape.fillColor!);
          if (shape.rough) {
            roughFill(Path()..addRect(rect));
          } else {
            canvas.drawRect(rect, fill);
          }
        }
        drawStroke(
          Path()
            ..moveTo(j(rect.topLeft).dx, j(rect.topLeft).dy)
            ..lineTo(j(rect.topRight).dx, j(rect.topRight).dy)
            ..lineTo(j(rect.bottomRight).dx, j(rect.bottomRight).dy)
            ..lineTo(j(rect.bottomLeft).dx, j(rect.bottomLeft).dy)
            ..close(),
        );
      case ShapeType.ellipse:
        if (fill != null) {
          fill.color = Color(shape.fillColor!);
          if (shape.rough) {
            roughFill(Path()..addOval(rect));
          } else {
            canvas.drawOval(rect, fill);
          }
        }
        drawStroke(Path()..addOval(rect));
      case ShapeType.diamond:
        final diamond = Path()
          ..moveTo(j(Offset(center.dx, 0)).dx, j(Offset(center.dx, 0)).dy)
          ..lineTo(
            j(Offset(size.width, center.dy)).dx,
            j(Offset(size.width, center.dy)).dy,
          )
          ..lineTo(
            j(Offset(center.dx, size.height)).dx,
            j(Offset(center.dx, size.height)).dy,
          )
          ..lineTo(j(Offset(0, center.dy)).dx, j(Offset(0, center.dy)).dy)
          ..close();
        if (fill != null) {
          fill.color = Color(shape.fillColor!);
          if (shape.rough) {
            roughFill(diamond);
          } else {
            canvas.drawPath(diamond, fill);
          }
        }
        drawStroke(diamond);
      case ShapeType.line:
        // 与 ShapeRenderer.drawLocal 对齐：优先使用保存的真实端点，
        // 旧文档无端点时回退为"左下→右上"对角线。
        final lineStart = endpoint(shape.lineStart, Offset(0, size.height));
        final lineEnd = endpoint(shape.lineEnd, Offset(size.width, 0));
        drawStroke(
          Path()
            ..moveTo(j(lineStart).dx, j(lineStart).dy)
            ..lineTo(j(lineEnd).dx, j(lineEnd).dy),
        );
      case ShapeType.arrow:
        final start = endpoint(shape.lineStart, Offset(0, size.height));
        final end = endpoint(shape.lineEnd, Offset(size.width, 0));
        // 箭头三角（指向 end 端，按末端线段方向计算）。
        const len = 14.0;
        if (shape.elbow) {
          // 弯折箭头（对齐 Excalidraw elbow arrow）：先水平再垂直三段式。
          final corner = Offset((start.dx + end.dx) / 2, start.dy);
          drawStroke(
            Path()
              ..moveTo(j(start).dx, j(start).dy)
              ..lineTo(j(corner).dx, j(corner).dy)
              ..lineTo(j(end).dx, j(end).dy),
          );
          final lastSegment = end - corner;
          final angle = lastSegment.direction;
          final elbowArrow = Path()
            ..moveTo(end.dx, end.dy)
            ..lineTo(
              end.dx - len * math.cos(angle - 0.4),
              end.dy - len * math.sin(angle - 0.4),
            )
            ..lineTo(
              end.dx - len * math.cos(angle + 0.4),
              end.dy - len * math.sin(angle + 0.4),
            )
            ..close();
          drawStroke(elbowArrow);
        } else {
          drawStroke(
            Path()
              ..moveTo(j(start).dx, j(start).dy)
              ..lineTo(j(end).dx, j(end).dy),
          );
          final angle = (end - start).direction;
          drawStroke(
            Path()
              ..moveTo(end.dx, end.dy)
              ..lineTo(
                end.dx - len * math.cos(angle - 0.4),
                end.dy - len * math.sin(angle - 0.4),
              )
              ..lineTo(
                end.dx - len * math.cos(angle + 0.4),
                end.dy - len * math.sin(angle + 0.4),
              )
              ..close(),
          );
        }
    }
  }

  @override
  bool shouldRepaint(ShapePainter oldDelegate) =>
      oldDelegate.shape != shape || oldDelegate.viewScale != viewScale;
}

/// 线性元素（直线/箭头）绘制 + 线段命中测试（审计二-5，2026-09-06）。
///
/// 渲染复用 [ShapePainter]；命中改为「点到线段距离 ≤ 线宽/2 + 6px」，
/// 取代外接框矩形判定——细斜线外接框的大片空白不再拦截点击，也不再
/// 挡住叠在其后的元素。仅当 CustomPaint 无 child 时本 hitTest 才生效，
/// 因此选中态的端点手柄必须作为兄弟节点而非 child 叠加。
class LinearShapePainter extends ShapePainter {
  const LinearShapePainter({required super.shape, required super.viewScale});

  @override
  bool hitTest(Offset position) {
    // painter 不接收 size；端点坐标系 = 外接框 × viewScale（与 paint 一致）。
    final w = shape.width * viewScale;
    final h = shape.height * viewScale;
    final start = shape.lineStart != null
        ? shape.lineStart! * viewScale
        : Offset(0, h);
    final end = shape.lineEnd != null
        ? shape.lineEnd! * viewScale
        : Offset(w, 0);
    return ShapeBindingGeometry.distanceToSegment(position, start, end) <=
        shape.strokeWidth / 2 + ShapeBindingGeometry.linearHitSlack * viewScale;
  }
}

/// 对齐参考线绘制器（借鉴 Excalidraw 对齐可视化）。
///
/// 拖动元素接近对齐位置时，在画布上画出参考线（垂直线/水平线），
/// 让用户直观看到"吸附到哪里"。
class SnapGuidePainter extends CustomPainter {
  SnapGuidePainter({required this.guides, required this.controller})
    : _viewport = _snapshotViewportOf(controller);

  final List<({bool vertical, double pos})> guides;
  final DrawingController controller;
  final ({double scale, double rotation, Offset offset}) _viewport;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color =
          const Color(0xFFFF5252) // 醒目红（Excalidraw 同款参考线色）
      ..strokeWidth = 1.2;
    final canvasPoint = Offset.zero;
    for (final g in guides) {
      final viewPos = controller.canvasToView(
        g.vertical
            ? Offset(g.pos, canvasPoint.dy)
            : Offset(canvasPoint.dx, g.pos),
      );
      if (g.vertical) {
        canvas.drawLine(
          Offset(viewPos.dx, 0),
          Offset(viewPos.dx, size.height),
          paint,
        );
      } else {
        canvas.drawLine(
          Offset(0, viewPos.dy),
          Offset(size.width, viewPos.dy),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(SnapGuidePainter oldDelegate) =>
      oldDelegate._viewport != _viewport ||
      oldDelegate.controller != controller ||
      !listEquals(oldDelegate.guides, guides);
}

/// 框选矩形绘制器（借鉴 Excalidraw 多选可视化）。
///
/// 框选时显示半透明蓝色矩形，直观呈现多选范围。
class MarqueePainter extends CustomPainter {
  MarqueePainter({required this.rect, required this.controller})
    : _viewport = _snapshotViewportOf(controller);

  // 审计 #31：Paint 配置恒定 → static final 共享，不再每帧分配。
  static final Paint _fillPaint = Paint()
    ..color = AppleColor.actionBlue.withValues(alpha: 0.2)
    ..style = PaintingStyle.fill;
  static final Paint _strokePaint = Paint()
    ..color = AppleColor.actionBlue
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;

  final Rect rect; // 画布坐标
  final DrawingController controller;
  final ({double scale, double rotation, Offset offset}) _viewport;

  @override
  void paint(Canvas canvas, Size size) {
    final topLeft = controller.canvasToView(rect.topLeft);
    final bottomRight = controller.canvasToView(rect.bottomRight);
    final viewRect = Rect.fromPoints(topLeft, bottomRight);
    canvas.drawRect(viewRect, _fillPaint); // 半透明蓝填充
    // 虚线框选（问题10）：与其他白板软件一致，用虚线勾勒框选区域，
    // 与正式选区实线区分。用 PathMetrics 手工分段，避免引入新依赖。
    final outline = Path()..addRect(viewRect);
    final dashed = Path();
    for (final metric in outline.computeMetrics()) {
      for (var offset = 0.0; offset < metric.length; offset += 12) {
        dashed.addPath(metric.extractPath(offset, offset + 8), Offset.zero);
      }
    }
    canvas.drawPath(dashed, _strokePaint);
  }

  @override
  bool shouldRepaint(MarqueePainter oldDelegate) =>
      oldDelegate._viewport != _viewport ||
      oldDelegate.controller != controller ||
      oldDelegate.rect != rect;
}

/// 网格绘制器（审计三-4 重做，2026-09-06）。
///
/// 点阵画在**画布坐标**（经 canvasToView 投影），平移缩放时纸动格子也动，
/// 修掉旧版「纸动了格子不动」的视图坐标错位；步长固定 20px 画布单位，
/// 与 `_snapToGrid` 拖动吸附共用同一网格（网格即吸附档位的视觉真相）。
/// 缩放过密时步长自动翻倍，保持点阵密度可读（对齐 Excalidraw 网格分级）。
class GridPainter extends CustomPainter {
  GridPainter({required this.controller})
    : _viewport = _snapshotViewportOf(controller);

  final DrawingController controller;
  final ({double scale, double rotation, Offset offset}) _viewport;

  @override
  void paint(Canvas canvas, Size size) {
    var step = 20.0;
    while (step * controller.viewScale < 14) {
      step *= 2;
    }
    // 视口四角逆变换到画布坐标，取外接矩形即点阵覆盖范围（含旋转）。
    final corners = <Offset>[
      controller.viewToCanvas(Offset.zero),
      controller.viewToCanvas(Offset(size.width, 0)),
      controller.viewToCanvas(Offset(0, size.height)),
      controller.viewToCanvas(Offset(size.width, size.height)),
    ];
    var left = corners.first.dx;
    var top = corners.first.dy;
    var right = left;
    var bottom = top;
    for (final corner in corners.skip(1)) {
      left = math.min(left, corner.dx);
      top = math.min(top, corner.dy);
      right = math.max(right, corner.dx);
      bottom = math.max(bottom, corner.dy);
    }
    final paint = Paint()
      ..color = const Color(0x1A000000)
      ..style = PaintingStyle.fill;
    final firstX = (left / step).ceilToDouble() * step;
    final firstY = (top / step).ceilToDouble() * step;
    for (var x = firstX; x <= right; x += step) {
      for (var y = firstY; y <= bottom; y += step) {
        canvas.drawCircle(controller.canvasToView(Offset(x, y)), 1.2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(GridPainter oldDelegate) =>
      oldDelegate._viewport != _viewport ||
      oldDelegate.controller != controller;
}

/// 图表渲染器（借鉴 Excalidraw charts）：柱状图/折线图。
class ChartPainter extends CustomPainter {
  ChartPainter({required this.chart, required this.viewScale})
    : _labelPainter = TextPainter(
        text: TextSpan(
          text: chart.data.map((v) => v.round().toString()).join(', '),
          // canvas content layer（domain 豁免）：图表数值标签随缩放绘制，
          // 不用 UI 排版梯子；9px 为画布内密排标注。
          style: const TextStyle(fontSize: 9, color: Colors.black54),
        ),
        textDirection: TextDirection.ltr,
      );

  final PageChartItem chart;
  final double viewScale;

  /// 数值标签（渲染性能 2026-09-07）：paint 每次新建 TextPainter 拼
  /// 标签纯浪费——标签文本只随 [chart.data] 变化，在构造时预建一次；
  /// layout 依赖 paint 时的实际宽度，按宽度记忆化（宽度不变则复用）。
  /// painter 实例随每次 build 重建，数据变化自然换新实例，无需手动失效。
  final TextPainter _labelPainter;
  double? _labelLaidOutWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final data = chart.data;
    if (data.isEmpty) return;
    final paint = Paint()
      ..color = Color(chart.color)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final maxV = data.fold<double>(0, (m, v) => v > m ? v : m);
    final maxY = maxV <= 0 ? 1.0 : maxV;
    final left = 0.0;
    final bw = size.width / data.length;
    final chartBottom = size.height - 8;

    if (chart.chartType == ChartType.bar) {
      final fill = Paint()..color = Color(chart.color).withValues(alpha: 0.5);
      for (var i = 0; i < data.length; i++) {
        final h = (data[i] / maxY) * (size.height - 8);
        final r = Rect.fromLTWH(
          left + i * bw + bw * 0.15,
          chartBottom - h,
          bw * 0.7,
          h,
        );
        canvas.drawRect(r, fill);
        canvas.drawRect(r, paint);
      }
    } else {
      final path = Path();
      for (var i = 0; i < data.length; i++) {
        final px = left + i * bw + bw / 2;
        final py = chartBottom - (data[i] / maxY) * (size.height - 8);
        if (i == 0) {
          path.moveTo(px, py);
        } else {
          path.lineTo(px, py);
        }
      }
      canvas.drawPath(path, paint);
      // 数据点圆点。
      final dot = Paint()
        ..color = Color(chart.color)
        ..style = PaintingStyle.fill;
      for (var i = 0; i < data.length; i++) {
        final px = left + i * bw + bw / 2;
        final py = chartBottom - (data[i] / maxY) * (size.height - 8);
        canvas.drawCircle(Offset(px, py), 3, dot);
      }
    }
    // 数值标签（顶部）：TextPainter 构造时预建，宽度不变时复用 layout。
    if (_labelLaidOutWidth != size.width) {
      _labelPainter.layout(maxWidth: size.width);
      _labelLaidOutWidth = size.width;
    }
    _labelPainter.paint(canvas, Offset.zero);
  }

  @override
  bool shouldRepaint(ChartPainter oldDelegate) =>
      oldDelegate.chart != chart || oldDelegate.viewScale != viewScale;
}

/// 拖动轨迹绘制器（借鉴 Excalidraw animatedTrail）。
///
/// 拖动元素时绘制渐隐轨迹线：越早的点越透明，形成"尾迹"视觉引导。
class TrailPainter extends CustomPainter {
  TrailPainter({required this.points, required this.controller})
    : _viewport = _snapshotViewportOf(controller);

  final List<Offset> points; // 画布坐标增量序列
  final DrawingController controller;
  final ({double scale, double rotation, Offset offset}) _viewport;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    // 累计画布坐标（增量 -> 绝对位置，相对画布中心）。
    var acc = Offset.zero;
    final pts = <Offset>[acc];
    for (final d in points) {
      acc += d;
      pts.add(acc);
    }
    // 审计 #31：Paint 复用（配置固定、循环内仅改 color），段数从
    // N 次 Paint 分配降为 1 次——拖动轨迹高频重绘路径上的小分配。
    final paint = Paint()
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var i = 1; i < pts.length; i++) {
      final opacity = 0.05 + 0.35 * (i / pts.length); // 越新越明显
      paint.color = AppleColor.actionBlue.withValues(alpha: opacity);
      final a = controller.canvasToView(pts[i - 1]);
      final b = controller.canvasToView(pts[i]);
      canvas.drawLine(a, b, paint);
    }
  }

  @override
  bool shouldRepaint(TrailPainter oldDelegate) =>
      oldDelegate._viewport != _viewport ||
      oldDelegate.controller != controller ||
      !listEquals(oldDelegate.points, points);
}
