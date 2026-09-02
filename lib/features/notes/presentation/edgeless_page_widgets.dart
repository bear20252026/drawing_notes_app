part of 'edgeless_page.dart';

// 画布卡片/角柄/横幅/工具面板/绘制器（自 edgeless_page.dart 拆出）。

/// 单帧卡片。
class _FrameCard extends StatelessWidget {
  const _FrameCard({
    required this.frame,
    required this.selected,
    required this.onEdit,
    required this.onRemove,
    required this.onConnect,
    required this.onResize,
    required this.onSetBackground,
  });

  final NoteFrame frame;
  final bool selected;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  /// 拖拽帧角（世界坐标）调整尺寸；[topLeft] 为 null 表示左上不动。
  final void Function(Offset? topLeft, double w, double h) onResize;

  /// 循环切换下一档帧背景色。
  final VoidCallback onSetBackground;

  /// 以当前帧为起点进入连线模式（仅选中态可见）。
  final VoidCallback onConnect;

  Color _bgColor() {
    final hex = frame.background.replaceAll('#', '');
    final value = int.tryParse(hex, radix: 16) ?? 0xFFFFFF;
    return Color(0xFF000000 | value);
  }

  @override
  Widget build(BuildContext context) {
    final border = selected
        ? Border.all(color: AppleColor.actionBlue, width: 2)
        : Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 1,
          );
    // 帧=纸面（AFFiNE note 帧）：文字墨色随纸面亮度自适应，保证深色模式下浅纸仍是深字可读。
    final paper = _bgColor();
    final ink = paper.computeLuminance() > 0.5
        ? AppleColor
              .ink // 亮纸用墨色正文
        : AppleColor.surfaceWhite; // 暗纸用白色正文
    final body = Container(
      decoration: BoxDecoration(
        color: _bgColor(),
        border: border,
        borderRadius: BorderRadius.circular(AppleRadius.md),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: ink.withValues(alpha: 0.08),
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      frame.doc.title.isNotEmpty ? frame.doc.title : '未命名',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppleType.captionStyle(
                        ink,
                      ).copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                // 帧背景色（AFFiNE note 帧背景预设）
                InkWell(
                  onTap: onSetBackground,
                  borderRadius: BorderRadius.circular(AppleRadius.lg),
                  child: Tooltip(
                    message: '帧背景色',
                    child: Container(
                      width: 20,
                      height: 20,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: _bgColor(),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      child: Icon(
                        Icons.format_color_fill,
                        size: 12,
                        color: ink.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ),
                if (selected)
                  IconButton(
                    tooltip: '连线',
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    icon: const Icon(Icons.call_made),
                    onPressed: onConnect,
                  ),
                IconButton(
                  tooltip: '编辑内容',
                  visualDensity: VisualDensity.compact,
                  iconSize: 16,
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: onEdit,
                ),
                IconButton(
                  tooltip: '删除帧',
                  visualDensity: VisualDensity.compact,
                  iconSize: 16,
                  icon: const Icon(Icons.close),
                  onPressed: onRemove,
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(2),
              child: NoteFramePreview(
                doc: frame.doc,
                showTitle: false,
                inkColor: ink,
              ),
            ),
          ),
        ],
      ),
    );
    if (!selected) return body;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        body,
        for (final corner in _Corner.values)
          _CornerHandle(
            key: ValueKey(corner),
            frame: frame,
            corner: corner,
            onResize: onResize,
          ),
      ],
    );
  }
}

/// 选中帧四角缩放手柄：拖拽（世界坐标）调整帧尺寸与左上角。
class _CornerHandle extends StatefulWidget {
  const _CornerHandle({
    super.key,
    required this.frame,
    required this.corner,
    required this.onResize,
  });

  final NoteFrame frame;
  final _Corner corner;
  final void Function(Offset? topLeft, double w, double h) onResize;

  @override
  State<_CornerHandle> createState() => _CornerHandleState();
}

class _CornerHandleState extends State<_CornerHandle> {
  static const double _size = 16;
  Offset? _startTopLeft;
  double? _startW;
  double? _startH;
  Offset _acc = Offset.zero;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final f = widget.frame;
    final pos = _cornerPos(widget.corner, f);
    return Positioned(
      left: pos.dx - _size / 2,
      top: pos.dy - _size / 2,
      width: _size,
      height: _size,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (d) {
          _dragging = true;
          _startTopLeft = Offset(f.x, f.y);
          _startW = f.w;
          _startH = f.h;
          _acc = Offset.zero;
          setState(() {});
        },
        onPanUpdate: (d) {
          if (_dragging) _emit(_acc + d.delta);
        },
        onPanEnd: (_) => _dragging = false,
        child: Container(
          decoration: BoxDecoration(
            color: AppleColor.actionBlue,
            borderRadius: BorderRadius.circular(AppleRadius.xs),
            border: Border.all(
              color: Theme.of(context).colorScheme.surface,
              width: 1.5,
            ),
          ),
        ),
      ),
    );
  }

  void _emit(Offset totalDelta) {
    final sw = _startW ?? widget.frame.w;
    final sh = _startH ?? widget.frame.h;
    final stl = _startTopLeft ?? Offset(widget.frame.x, widget.frame.y);
    switch (widget.corner) {
      case _Corner.topLeft:
        widget.onResize(
          stl + totalDelta,
          sw - totalDelta.dx,
          sh - totalDelta.dy,
        );
      case _Corner.topRight:
        widget.onResize(
          Offset(stl.dx, stl.dy + totalDelta.dy),
          sw + totalDelta.dx,
          sh - totalDelta.dy,
        );
      case _Corner.bottomLeft:
        widget.onResize(
          Offset(stl.dx + totalDelta.dx, stl.dy),
          sw - totalDelta.dx,
          sh + totalDelta.dy,
        );
      case _Corner.bottomRight:
        widget.onResize(stl, sw + totalDelta.dx, sh + totalDelta.dy);
    }
  }

  Offset _cornerPos(_Corner corner, NoteFrame f) {
    switch (corner) {
      case _Corner.topLeft:
        return Offset(f.x, f.y);
      case _Corner.topRight:
        return Offset(f.x + f.w, f.y);
      case _Corner.bottomLeft:
        return Offset(f.x, f.y + f.h);
      case _Corner.bottomRight:
        return Offset(f.x + f.w, f.y + f.h);
    }
  }
}

/// 世界坐标网格背景画师。
class _EdgelessGridPainter extends CustomPainter {
  _EdgelessGridPainter({required this.color});

  final Color color;

  /// 可视世界范围（草拟的大范围，随相机缩放可见区自然变化）。
  static const double _minX = -4000;
  static const double _maxX = 4000;
  static const double _minY = -4000;
  static const double _maxY = 4000;
  static const double _step = 64;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var x = _minX; x <= _maxX; x += _step) {
      canvas.drawLine(Offset(x, _minY), Offset(x, _maxY), paint);
    }
    for (var y = _minY; y <= _maxY; y += _step) {
      canvas.drawLine(Offset(_minX, y), Offset(_maxX, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _EdgelessGridPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// 世界坐标连接线画师：在帧下方绘制 `affine:connector` 连线。
/// 端点坐标由帧的当前矩形即时推导，帧移动/缩放后自动跟随。
class _ConnectorPainter extends CustomPainter {
  _ConnectorPainter({required this.connectors, required this.framesById});

  final List<NoteConnector> connectors;
  final Map<String, NoteFrame> framesById;

  /// CSS hex → Color；解析失败回退为 Apple actionBlue。
  static Color _colorOf(String hex) {
    final v = int.tryParse(hex.replaceFirst('#', ''), radix: 16) ?? 0x0066CC;
    return Color(0xFF000000 | v);
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final c in connectors) {
      final from = framesById[c.fromFrameId];
      final to = framesById[c.toFrameId];
      if (from == null || to == null) continue;
      final a = connectorAnchorPoint(
        Rect.fromLTWH(from.x, from.y, from.w, from.h),
        c.fromAnchor,
      );
      final b = connectorAnchorPoint(
        Rect.fromLTWH(to.x, to.y, to.w, to.h),
        c.toAnchor,
      );
      final color = _colorOf(c.color);

      final line = Paint()
        ..color = color
        ..strokeWidth = c.width
        ..style = PaintingStyle.stroke;
      canvas.drawLine(a, b, line);

      // 两端锚点圆点
      final dot = Paint()..color = color;
      canvas.drawCircle(a, c.width + 1.5, dot);
      canvas.drawCircle(b, c.width + 1.5, dot);

      // 可选标签（绘制于线段中点）
      final label = c.label;
      if (label != null && label.isNotEmpty) {
        final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
        final tp = TextPainter(
          text: TextSpan(
            text: label,
            style: AppleType.captionStyle(
              color,
            ).copyWith(fontWeight: FontWeight.w500),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: 200);
        tp.paint(canvas, mid - Offset(tp.width / 2, tp.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ConnectorPainter oldDelegate) =>
      !listEquals(connectors, oldDelegate.connectors) ||
      !mapEquals(framesById, oldDelegate.framesById);
}

/// 世界坐标群组框画师：在帧上方绘制 `affine:group` 外接框（圆角边框 + 半透明填充 + 组名角标）。
/// 组外接矩形由成员帧矩形并集即时推导，帧移动/缩放后边框自动跟随。
class _GroupPainter extends CustomPainter {
  _GroupPainter({
    required this.groups,
    required this.framesById,
    this.chipBgColor,
  });

  final List<EdgelessGroup> groups;
  final Map<String, NoteFrame> framesById;
  final Color? chipBgColor;

  static Color _colorOf(String hex) {
    final v = int.tryParse(hex.replaceFirst('#', ''), radix: 16) ?? 0x4CAF50;
    return Color(0xFF000000 | v);
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final g in groups) {
      final rects = <Rect>[];
      var anyMissing = false;
      for (final fid in g.frameIds) {
        final f = framesById[fid];
        if (f == null) {
          anyMissing = true;
          break;
        }
        rects.add(Rect.fromLTWH(f.x, f.y, f.w, f.h));
      }
      if (anyMissing || rects.isEmpty) continue;
      final bounds = groupBoundsOf(rects)!;
      final color = _colorOf(g.color);

      // 半透明填充
      canvas.drawRRect(
        RRect.fromRectAndRadius(bounds.inflate(6), const Radius.circular(10)),
        Paint()..color = color.withValues(alpha: 0.06),
      );
      // 圆角边框
      canvas.drawRRect(
        RRect.fromRectAndRadius(bounds.inflate(6), const Radius.circular(10)),
        Paint()
          ..color = color.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );

      // 组名角标（左上）
      final label = g.name;
      if (label != null && label.isNotEmpty) {
        final tp = TextPainter(
          text: TextSpan(
            text: label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final chipRect = Rect.fromLTWH(
          bounds.left + 2,
          bounds.top - tp.height - 2,
          tp.width + 10,
          tp.height + 4,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(chipRect, const Radius.circular(4)),
          Paint()
            ..color = (chipBgColor ?? AppleColor.surfaceWhite).withValues(
              alpha: 0.92,
            ),
        );
        tp.paint(canvas, Offset(chipRect.left + 5, chipRect.top + 2));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GroupPainter oldDelegate) =>
      !listEquals(groups, oldDelegate.groups) ||
      !mapEquals(framesById, oldDelegate.framesById);
}

/// 连线模式顶部横幅：提示用户点击另一帧创建连接，或点空白取消。
class _ConnectBanner extends StatelessWidget {
  const _ConnectBanner({required this.sourceId, required this.onCancel});

  final String sourceId;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: AppleColor.blockPurple,
          borderRadius: BorderRadius.circular(AppleRadius.full),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.call_made,
              color: AppleColor.surfaceWhite,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '连线模式：点击另一帧创建连接（起点 $sourceId）',
                style: AppleType.controlStyle(AppleColor.surfaceWhite),
              ),
            ),
            IconButton(
              tooltip: '取消',
              visualDensity: VisualDensity.compact,
              icon: const Icon(
                Icons.close,
                color: AppleColor.surfaceWhite,
                size: 18,
              ),
              onPressed: onCancel,
            ),
          ],
        ),
      ),
    );
  }
}

/// AFFiNE 风格左侧工具面板：选择/便签/画笔/橡皮/形状。
class _ToolPanel extends StatelessWidget {
  const _ToolPanel();

  @override
  Widget build(BuildContext context) {
    final controller = context
        .findAncestorStateOfType<_EdgelessPageState>()!
        ._controller;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeBg =
        (isDark ? const Color(0xFFB5CCFF) : AppleColor.actionBlue).withValues(
          alpha: 0.18,
        );

    Widget toolButton(EdgelessTool tool, IconData icon, String tooltip) {
      final active = controller.tool == tool;
      return Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => controller.setTool(tool),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: active ? activeBg : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 20,
              color: active ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          toolButton(EdgelessTool.select, Icons.pan_tool_outlined, '选择'),
          const SizedBox(height: 4),
          toolButton(EdgelessTool.sticky, Icons.sticky_note_2_outlined, '便签'),
          const SizedBox(height: 4),
          toolButton(EdgelessTool.brush, Icons.brush_outlined, '画笔'),
          const SizedBox(height: 4),
          toolButton(
            EdgelessTool.eraser,
            Icons.cleaning_services_outlined,
            '橡皮',
          ),
          const SizedBox(height: 4),
          PopupMenuButton<EdgelessShapeKind>(
            tooltip: '形状',
            onSelected: (kind) => controller.setShapeKind(kind),
            itemBuilder: (context) => const [
              PopupMenuItem(value: EdgelessShapeKind.rect, child: Text('矩形')),
              PopupMenuItem(
                value: EdgelessShapeKind.ellipse,
                child: Text('椭圆'),
              ),
            ],
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: controller.tool == EdgelessTool.shape
                    ? activeBg
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.category_outlined,
                size: 20,
                color: controller.tool == EdgelessTool.shape
                    ? scheme.primary
                    : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 笔迹/形状绘制（世界坐标系内，随相机变换）。
class _ElementPainter extends CustomPainter {
  _ElementPainter({
    required this.strokes,
    required this.shapes,
    this.activeStroke,
    this.shapeOrigin,
    this.shapeKind = EdgelessShapeKind.rect,
    this.lastFocalWorld,
  });

  final List<EdgelessStroke> strokes;
  final List<EdgelessShape> shapes;
  final EdgelessStroke? activeStroke;
  final Offset? shapeOrigin;
  final EdgelessShapeKind shapeKind;
  final Offset? lastFocalWorld;

  @override
  void paint(Canvas canvas, Size size) {
    for (final shape in shapes) {
      final fill =
          _parseColor(shape.color) ?? AppleColor.actionBlue.withValues(
            alpha: 0.20,
          );
      final paint = Paint()..color = fill;
      if (shape.kind == EdgelessShapeKind.ellipse) {
        canvas.drawOval(shape.rect, paint);
      } else {
        final rrect = RRect.fromRectAndRadius(
          shape.rect,
          const Radius.circular(4),
        );
        canvas.drawRRect(rrect, paint);
      }
    }
    for (final stroke in strokes) {
      _paintStroke(canvas, stroke);
    }
    if (activeStroke != null) {
      _paintStroke(canvas, activeStroke!);
    }
    if (shapeOrigin != null && lastFocalWorld != null) {
      final rect = Rect.fromPoints(shapeOrigin!, lastFocalWorld!);
      final paint = Paint()
        ..color = AppleColor.actionBlue.withValues(alpha: 0.20)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      if (shapeKind == EdgelessShapeKind.ellipse) {
        canvas.drawOval(rect, paint);
      } else {
        canvas.drawRect(rect, paint);
      }
    }
  }

  void _paintStroke(Canvas canvas, EdgelessStroke stroke) {
    if (stroke.pointCount < 2) return;
    final paint = Paint()
      ..color = _parseColor(stroke.color) ?? AppleColor.ink
      ..strokeWidth = stroke.width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final path = Path()..moveTo(stroke.points[0], stroke.points[1]);
    for (var i = 1; i < stroke.pointCount; i++) {
      path.lineTo(stroke.points[i * 2], stroke.points[i * 2 + 1]);
    }
    canvas.drawPath(path, paint);
  }

  Color? _parseColor(String css) {
    var hex = css.replaceFirst('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    if (hex.length != 8) return null;
    final value = int.tryParse(hex, radix: 16);
    return value == null ? null : Color(value);
  }

  @override
  bool shouldRepaint(covariant _ElementPainter old) =>
      old.strokes != strokes ||
      old.shapes != shapes ||
      old.activeStroke != activeStroke ||
      old.shapeOrigin != shapeOrigin ||
      old.lastFocalWorld != lastFocalWorld;
}
