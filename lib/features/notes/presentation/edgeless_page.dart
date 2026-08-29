// 由 Claude 团队生成 | Drawing Notes App
// EdgelessPage：无限画布（1:1 AFFiNE edgeless）页面。
//
// 提供：pan/zoom 相机、note 帧渲染（只读预览）、拖帧、选中、双击进入编辑器、
// 新增帧、适应画布等。依赖 M8-1（EdgelessDoc/EdgelessCamera/NoteFrame）、
// EdgelessController（手势翻译）与 NoteFramePreview（帧内容）。
// 只依赖 notes，不 import drawing/chart 实现层（架构规则 3）。

import 'package:flutter/foundation.dart' show listEquals, mapEquals;
import 'package:flutter/material.dart';

import 'package:drawing_notes_app/features/notes/domain/edgeless_connector.dart';
import 'package:drawing_notes_app/features/notes/domain/edgeless_doc.dart';
import 'package:drawing_notes_app/features/notes/domain/edgeless_group.dart';
import 'package:drawing_notes_app/features/notes/domain/note_block.dart';
import 'package:drawing_notes_app/features/notes/domain/note_block_doc.dart';
import 'package:drawing_notes_app/features/notes/presentation/edgeless_controller.dart';
import 'package:drawing_notes_app/features/notes/presentation/note_editor_page.dart';
import 'package:drawing_notes_app/features/notes/presentation/note_frame_preview.dart';

/// Edgeless 无限画布页。
///
/// 输入初始 [initialDoc] 与变更回调 [onChanged]；双击某帧进入 [NoteEditorPage]
/// 编辑该帧内容（返回后通过 [controller.updateFrameDoc] 写回）。
class EdgelessPage extends StatefulWidget {
  const EdgelessPage({
    super.key,
    required this.initialDoc,
    this.onChanged,
    this.embeddedBlockBuilder,
  });

  final EdgelessDoc initialDoc;
  final void Function(EdgelessDoc doc)? onChanged;

  /// 内嵌块（画布/图表等）的外接定制 builder。
  ///
  /// 透传给帧内打开 NoteEditorPage 时的内嵌块渲染。
  final Widget? Function(NoteBlock block)? embeddedBlockBuilder;

  @override
  State<EdgelessPage> createState() => _EdgelessPageState();
}

class _EdgelessPageState extends State<EdgelessPage> {
  late final EdgelessController _controller;
  Size _viewport = const Size(800, 600);
  @override
  void initState() {
    super.initState();
    _controller = EdgelessController(doc: widget.initialDoc, onChanged: widget.onChanged);
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  EdgelessCamera get _camera => _controller.camera;

  /// 世界坐标系 → 屏幕坐标系的矩阵。
  Matrix4 _cameraMatrix(Size viewport) {
    final z = _camera.zoom;
    final cx = viewport.width / 2;
    final cy = viewport.height / 2;
    final offX = cx - _camera.panX * z;
    final offY = cy - _camera.panY * z;
    return Matrix4.translationValues(offX, offY, 0)..scaleByDouble(z, z, 1, 1);
  }

  // ── 手势 ──────────────────────────────────────────────────

  void _onTapUp(TapUpDetails d) => _controller.tapAt(d.localPosition, _viewport);

  void _onDoubleTap(TapDownDetails d) {
    final world = _controller.screenToWorld(d.localPosition, _viewport);
    final frame = _controller.hitTest(world);
    if (frame != null) {
      _openFrameEditor(frame.id, frame.doc);
    }
  }

  void _onScaleStart(ScaleStartDetails d) =>
      _controller.beginGesture(d.localFocalPoint, d.pointerCount, _viewport);

  void _onScaleUpdate(ScaleUpdateDetails d) =>
      _controller.updateGesture(d.localFocalPoint, d.scale, d.pointerCount, _viewport);

  void _onScaleEnd(ScaleEndDetails _) => _controller.endGesture();

  Future<void> _openFrameEditor(String frameId, NoteBlockDoc doc) async {
    final updated = await Navigator.of(context).push<NoteBlockDoc>(
      MaterialPageRoute(
        builder: (_) => NoteEditorPage(
          document: doc,
          onSave: (d) {},
          embeddedBlockBuilder: widget.embeddedBlockBuilder,
        ),
      ),
    );
    if (updated != null) {
      _controller.updateFrameDoc(frameId, updated);
    }
  }

  void _addFrame() {
    _controller.addFrame(NoteBlockDoc.empty('new_${DateTime.now().microsecondsSinceEpoch}'));
  }

  void _toggleMultiSelect() {
    _controller.toggleMultiSelectMode();
  }

  void _toggleConnect() {
    if (_controller.connectMode) {
      _controller.cancelConnect();
      return;
    }
    final sel = _controller.selectedFrameId;
    if (sel == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选中一个帧作为连线起点')),
      );
      return;
    }
    _controller.beginConnect(sel);
  }

  void _fitTo() {
    final frames = _controller.doc.frames;
    if (frames.isEmpty) {
      _controller.fitTo(const Rect.fromLTWH(0, 0, 1000, 1000), _viewport);
      return;
    }
    // 计算所有帧的包围盒
    var rect = frames.first.rect;
    for (final f in frames) {
      rect = rect.expandToInclude(f.rect);
    }
    _controller.fitTo(rect, _viewport, padding: 48);
  }

  void _zoom(double factor) {
    _controller.zoomAt(factor, focusWorld: _controller.screenToWorld(
      Offset(_viewport.width / 2, _viewport.height / 2),
      _viewport,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edgeless'),
        actions: [
          IconButton(
            tooltip: '新增帧',
            icon: const Icon(Icons.note_add_outlined),
            onPressed: _addFrame,
          ),
          IconButton(
            tooltip: '适应',
            icon: const Icon(Icons.fit_screen_outlined),
            onPressed: _fitTo,
          ),
          IconButton(
            tooltip: '缩小',
            icon: const Icon(Icons.zoom_out),
            onPressed: () => _zoom(1 / 1.2),
          ),
          IconButton(
            tooltip: '放大',
            icon: const Icon(Icons.zoom_in),
            onPressed: () => _zoom(1.2),
          ),
          IconButton(
            tooltip: _controller.connectMode ? '取消连线' : '连线模式',
            isSelected: _controller.connectMode,
            icon: const Icon(Icons.call_made),
            onPressed: _toggleConnect,
          ),
          IconButton(
            tooltip: _controller.multiSelectMode ? '退出多选' : '多选(编组)',
            isSelected: _controller.multiSelectMode,
            icon: const Icon(Icons.done_all),
            onPressed: _toggleMultiSelect,
          ),
          IconButton(
            tooltip: '编组',
            icon: const Icon(Icons.group_work_outlined),
            onPressed: _controller.selectedFrameIds.length >= 2
                ? () => _controller.groupSelection()
                : null,
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          _viewport = Size(constraints.maxWidth, constraints.maxHeight);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: _onTapUp,
            onDoubleTapDown: _onDoubleTap,
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            onScaleEnd: _onScaleEnd,
            child: ClipRect(
              child: Stack(
                children: [
                  // 网格背景（在世界坐标系中，随相机平移/缩放）
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _EdgelessGridPainter(
                        color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                  // 世界内容
                  Transform(
                    alignment: Alignment.topLeft,
                    transform: _cameraMatrix(_viewport),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // 连接线层：绘制在帧下方（AFFiNE `affine:connector`）
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _ConnectorPainter(
                              connectors: _controller.connectors,
                              framesById: _controller.framesById,
                            ),
                          ),
                        ),
                        for (final f in _controller.framesSortedByZ)
                          Positioned(
                            key: ValueKey('frame_${f.id}'),
                            left: f.x,
                            top: f.y,
                            width: f.w,
                            height: f.h,
                            child: _FrameCard(
                              frame: f,
                              selected: _controller.isSelected(f.id),
                              onEdit: () => _openFrameEditor(f.id, f.doc),
                              onRemove: () => _controller.removeFrame(f.id),
                              onConnect: () => _controller.beginConnect(f.id),
                              onResize: (topLeft, w, h) => _controller.resizeFrame(
                                f.id,
                                topLeft: topLeft,
                                w: w,
                                h: h,
                              ),
                              onSetBackground: () {
                                final idx = _kFrameBackgrounds.indexOf(f.background);
                                final next = _kFrameBackgrounds[
                                    (idx + 1) % _kFrameBackgrounds.length];
                                _controller.setFrameBackground(f.id, next);
                              },
                            ),
                          ),
                        // 群组框层：绘制在帧上方（AFFiNE `affine:group` 外接框）
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _GroupPainter(
                              groups: _controller.groups,
                              framesById: _controller.framesById,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 连线模式横幅
                  if (_controller.connectMode)
                    Positioned(
                      top: 8,
                      left: 8,
                      right: 8,
                      child: _ConnectBanner(
                        sourceId: _controller.connectSourceFrameId!,
                        onCancel: _controller.cancelConnect,
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// AFFiNE note 帧默认背景色预设（白 + 常用 pastel）。
const List<String> _kFrameBackgrounds = [
  '#FFFFFF',
  '#FFF8E1',
  '#E3F2FD',
  '#E8F5E9',
  '#FBE9E7',
  '#F3E5F5',
  '#FFF3E0',
  '#E0F7FA',
];

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
        ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2)
        : Border.all(color: Colors.black26, width: 1);
    final body = Container(
      decoration: BoxDecoration(
        color: _bgColor(),
        border: border,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.black.withValues(alpha: 0.06),
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      frame.doc.title.isNotEmpty ? frame.doc.title : '未命名',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                // 帧背景色（AFFiNE note 帧背景预设）
                InkWell(
                  onTap: onSetBackground,
                  borderRadius: BorderRadius.circular(16),
                  child: Tooltip(
                    message: '帧背景色',
                    child: Container(
                      width: 20,
                      height: 20,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: _bgColor(),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black26),
                      ),
                      child: const Icon(Icons.format_color_fill, size: 12, color: Colors.black54),
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
              child: NoteFramePreview(doc: frame.doc, showTitle: false),
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

/// 帧角手柄枚举。
enum _Corner { topLeft, topRight, bottomLeft, bottomRight }

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
            color: Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: Colors.white, width: 1.5),
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
        widget.onResize(stl + totalDelta, sw - totalDelta.dx, sh - totalDelta.dy);
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

  /// CSS hex → Color；解析失败回退为品牌紫。
  static Color _colorOf(String hex) {
    final v = int.tryParse(hex.replaceFirst('#', ''), radix: 16) ?? 0x7C4DFF;
    return Color(0xFF000000 | v);
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final c in connectors) {
      final from = framesById[c.fromFrameId];
      final to = framesById[c.toFrameId];
      if (from == null || to == null) continue;
      final a = connectorAnchorPoint(
          Rect.fromLTWH(from.x, from.y, from.w, from.h), c.fromAnchor);
      final b = connectorAnchorPoint(
          Rect.fromLTWH(to.x, to.y, to.w, to.h), c.toAnchor);
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
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Colors.black87,
            ),
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
  _GroupPainter({required this.groups, required this.framesById});

  final List<EdgelessGroup> groups;
  final Map<String, NoteFrame> framesById;

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
        RRect.fromRectAndRadius(
            bounds.inflate(6), const Radius.circular(10)),
        Paint()..color = color.withValues(alpha: 0.06),
      );
      // 圆角边框
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            bounds.inflate(6), const Radius.circular(10)),
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
        final chipRect =
            Rect.fromLTWH(bounds.left + 2, bounds.top - tp.height - 2, tp.width + 10, tp.height + 4);
        canvas.drawRRect(
          RRect.fromRectAndRadius(chipRect, const Radius.circular(4)),
          Paint()..color = Colors.white.withValues(alpha: 0.92),
        );
        tp.paint(canvas,
            Offset(chipRect.left + 5, chipRect.top + 2));
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
          color: const Color(0xFF7C4DFF),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            const Icon(Icons.call_made, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '连线模式：点击另一帧创建连接（起点 $sourceId）',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
            IconButton(
              tooltip: '取消',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, color: Colors.white, size: 18),
              onPressed: onCancel,
            ),
          ],
        ),
      ),
    );
  }
}
