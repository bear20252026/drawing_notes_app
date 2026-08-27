import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/features/drawing/domain/page_chart_item.dart';
import 'package:drawing_notes_app/features/drawing/domain/page_connector.dart';
import 'package:drawing_notes_app/features/drawing/domain/shape_item.dart';
import 'package:drawing_notes_app/features/drawing/domain/text_item.dart';

/// 编辑器纯展示组件集（架构重构 R1：从 editor_page 外移的零耦合组件）。
///
/// 设计原则（见 docs/ARCHITECTURE_REVISION.md）：
/// - 本文件内组件**不持有编辑器状态**，全部通过构造参数传入；
/// - 不读写文件、不调用存储层——纯展示/渲染职责；
/// - 每个组件 ≤100 行，职责单一，可独立测试。

/// 快捷键帮助条目（键位 + 说明）。
class ShortcutRow extends StatelessWidget {
  const ShortcutRow({super.key, required this.shortcut, required this.action});

  final String shortcut;
  final String action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Text(
              shortcut,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(action)),
        ],
      ),
    );
  }
}

/// 连接线渲染器（D1：节点关联标注，借鉴 Relatum 连线）。
///
/// 在页面混排对象（文字/图片块）之间画连线，坐标随画布视口变换。
class ConnectorPainter extends CustomPainter {
  ConnectorPainter({
    required Iterable<PageConnector> connectors,
    required Map<String, Offset> itemPositions,
    required this.controller,
  }) : connectors = List.unmodifiable(connectors),
       itemPositions = Map.unmodifiable(itemPositions);

  final List<PageConnector> connectors;
  final Map<String, Offset> itemPositions;
  final DrawingController controller;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x8842A5F5)
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
      canvas.drawPath(arrow, Paint()..color = const Color(0xFF42A5F5));
    }
  }

  /// 查询导出时捕获的混排对象位置（画布坐标），无则返回 null。
  Offset? _itemPosition(String id) => itemPositions[id];

  @override
  bool shouldRepaint(ConnectorPainter oldDelegate) => true;
}

/// 番茄钟专注计时浮层（D2，借鉴 Relatum 学习工具）。
///
/// 默认 25 分钟专注计时，支持开始/暂停/重置；到时触发 [onFinished]。
class PomodoroTimer extends StatefulWidget {
  const PomodoroTimer({super.key, this.onFinished});

  final VoidCallback? onFinished;

  /// 默认专注时长：25 分钟。
  static const Duration defaultDuration = Duration(minutes: 25);

  @override
  State<PomodoroTimer> createState() => _PomodoroTimerState();
}

class _PomodoroTimerState extends State<PomodoroTimer> {
  late Duration _remaining = PomodoroTimer.defaultDuration;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _toggle() {
    if (_timer != null) {
      _timer!.cancel();
      _timer = null;
    } else {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() {
          _remaining -= const Duration(seconds: 1);
          if (_remaining <= Duration.zero) {
            _remaining = Duration.zero;
            _timer!.cancel();
            _timer = null;
            widget.onFinished?.call();
          }
        });
      });
    }
    setState(() {});
  }

  void _reset() {
    _timer?.cancel();
    _timer = null;
    setState(() => _remaining = PomodoroTimer.defaultDuration);
  }

  @override
  Widget build(BuildContext context) {
    final mins = _remaining.inMinutes.toString().padLeft(2, '0');
    final secs = (_remaining.inSeconds % 60).toString().padLeft(2, '0');
    final running = _timer != null;
    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(20),
      color: const Color(0xDDFFFFFF),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.timer_outlined, size: 16),
            const SizedBox(width: 4),
            Text(
              '$mins:$secs',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: running ? '暂停' : '开始',
              icon: Icon(running ? Icons.pause : Icons.play_arrow, size: 18),
              visualDensity: VisualDensity.compact,
              onPressed: _toggle,
            ),
            IconButton(
              tooltip: '重置',
              icon: const Icon(Icons.refresh, size: 18),
              visualDensity: VisualDensity.compact,
              onPressed: _reset,
            ),
          ],
        ),
      ),
    );
  }
}

/// 分页预览组件（D3：长笔记多页预览，借鉴 Umo Editor 分页模式）。
///
/// 把文字块按 A4 页面高度（逻辑像素）分页渲染，
/// 每页显示页眉（标题+页码）与内容，超出页高的内容流到下一页。
class PaginationPreview extends StatelessWidget {
  const PaginationPreview({super.key, required this.textItems});

  final List<PageTextItem> textItems;

  /// A4 页面逻辑高度（对应画布 2480x3508 的近似高度）。
  static const double _pageHeight = 800;

  /// 单行文字估算高度。
  static const double _lineHeight = 28;

  @override
  Widget build(BuildContext context) {
    // 分页：按估算行数把文字块分配到多页。
    final pages = <List<PageTextItem>>[];
    var current = <PageTextItem>[];
    var used = 60.0; // 页顶留白
    for (final t in textItems) {
      final lines = (t.text.length / 18).ceil().clamp(1, 20);
      final h = _lineHeight * lines + 12;
      if (used + h > _pageHeight && current.isNotEmpty) {
        pages.add(current);
        current = <PageTextItem>[];
        used = 60.0;
      }
      current.add(t);
      used += h;
    }
    if (current.isNotEmpty) pages.add(current);

    return ListView.builder(
      itemCount: pages.length,
      itemBuilder: (context, i) {
        final items = pages[i];
        return Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.grey.shade400),
            boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26)],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '第 ${i + 1} 页 / 共 ${pages.length} 页',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ],
              ),
              const Divider(height: 12),
              for (final t in items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    t.text,
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(t.color),
                      fontWeight: t.bold ? FontWeight.bold : FontWeight.normal,
                      fontStyle: t.italic ? FontStyle.italic : FontStyle.normal,
                      decoration: t.underline
                          ? TextDecoration.underline
                          : (t.strikethrough
                                ? TextDecoration.lineThrough
                                : TextDecoration.none),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
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
        drawStroke(
          Path()
            ..moveTo(j(Offset(0, size.height)).dx, j(Offset(0, size.height)).dy)
            ..lineTo(j(Offset(size.width, 0)).dx, j(Offset(size.width, 0)).dy),
        );
      case ShapeType.arrow:
        final start = shape.lineStart ?? Offset(0, size.height);
        final end = shape.lineEnd ?? Offset(size.width, 0);
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

/// 对齐参考线绘制器（借鉴 Excalidraw 对齐可视化）。
///
/// 拖动元素接近对齐位置时，在画布上画出参考线（垂直线/水平线），
/// 让用户直观看到"吸附到哪里"。
class SnapGuidePainter extends CustomPainter {
  const SnapGuidePainter({required this.guides, required this.controller});

  final List<({bool vertical, double pos})> guides;
  final DrawingController controller;

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
  bool shouldRepaint(SnapGuidePainter oldDelegate) => true;
}

/// 框选矩形绘制器（借鉴 Excalidraw 多选可视化）。
///
/// 框选时显示半透明蓝色矩形，直观呈现多选范围。
class MarqueePainter extends CustomPainter {
  const MarqueePainter({required this.rect, required this.controller});

  final Rect rect; // 画布坐标
  final DrawingController controller;

  @override
  void paint(Canvas canvas, Size size) {
    final topLeft = controller.canvasToView(rect.topLeft);
    final bottomRight = controller.canvasToView(rect.bottomRight);
    final viewRect = Rect.fromPoints(topLeft, bottomRight);
    canvas.drawRect(
      viewRect,
      Paint()
        ..color =
            const Color(0x3342A5F5) // 半透明蓝填充
        ..style = PaintingStyle.fill,
    );
    // 虚线框选（问题10）：与其他白板软件一致，用虚线勾勒框选区域，
    // 与正式选区实线区分。用 PathMetrics 手工分段，避免引入新依赖。
    final outline = Path()..addRect(viewRect);
    final dashed = Path();
    for (final metric in outline.computeMetrics()) {
      for (var offset = 0.0; offset < metric.length; offset += 12) {
        dashed.addPath(metric.extractPath(offset, offset + 8), Offset.zero);
      }
    }
    canvas.drawPath(
      dashed,
      Paint()
        ..color = const Color(0xFF42A5F5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(MarqueePainter oldDelegate) => true;
}

/// 网格绘制器（借鉴 Excalidraw 画布导航）。
///
/// 在画布上绘制 20px 网格（浅灰线），帮助对齐与布局参考。
class GridPainter extends CustomPainter {
  const GridPainter({required this.controller});

  final DrawingController controller;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x1A000000)
      ..strokeWidth = 1;
    const step = 20.0;
    // 视图坐标绘制网格（随画布缩放平移）。
    for (var x = 0.0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(GridPainter oldDelegate) => true;
}

/// 图表渲染器（借鉴 Excalidraw charts）：柱状图/折线图。
class ChartPainter extends CustomPainter {
  const ChartPainter({required this.chart, required this.viewScale});

  final PageChartItem chart;
  final double viewScale;

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
    // 数值标签（顶部）。
    final tp = TextPainter(
      text: TextSpan(
        text: data.map((v) => v.round().toString()).join(', '),
        style: const TextStyle(fontSize: 9, color: Colors.black54),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width);
    tp.paint(canvas, Offset(0, 0));
  }

  @override
  bool shouldRepaint(ChartPainter oldDelegate) =>
      oldDelegate.chart != chart || oldDelegate.viewScale != viewScale;
}

/// 拖动轨迹绘制器（借鉴 Excalidraw animatedTrail）。
///
/// 拖动元素时绘制渐隐轨迹线：越早的点越透明，形成"尾迹"视觉引导。
class TrailPainter extends CustomPainter {
  TrailPainter({required this.points, required this.controller});

  final List<Offset> points; // 画布坐标增量序列
  final DrawingController controller;

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
    for (var i = 1; i < pts.length; i++) {
      final opacity = 0.05 + 0.35 * (i / pts.length); // 越新越明显
      final paint = Paint()
        ..color = const Color(0xFF42A5F5).withValues(alpha: opacity)
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      final a = controller.canvasToView(pts[i - 1]);
      final b = controller.canvasToView(pts[i]);
      canvas.drawLine(a, b, paint);
    }
  }

  @override
  bool shouldRepaint(TrailPainter oldDelegate) => true;
}
