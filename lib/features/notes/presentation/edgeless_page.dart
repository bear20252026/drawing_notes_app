// 由 Claude 团队生成 | Drawing Notes App
// EdgelessPage：无限画布（1:1 AFFiNE edgeless）页面。
//
// 提供：pan/zoom 相机、note 帧渲染（只读预览）、拖帧、选中、双击进入编辑器、
// 新增帧、适应画布等。依赖 M8-1（EdgelessDoc/EdgelessCamera/NoteFrame）、
// EdgelessController（手势翻译）与 NoteFramePreview（帧内容）。
// 只依赖 notes，不 import drawing/chart 实现层（架构规则 3）。

import 'package:flutter/material.dart';

import 'package:drawing_notes_app/features/notes/domain/edgeless_doc.dart';
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
                        for (final f in _controller.framesSortedByZ)
                          Positioned(
                            key: ValueKey('frame_${f.id}'),
                            left: f.x,
                            top: f.y,
                            width: f.w,
                            height: f.h,
                            child: _FrameCard(
                              frame: f,
                              selected: f.id == _controller.selectedFrameId,
                              onEdit: () => _openFrameEditor(f.id, f.doc),
                              onRemove: () => _controller.removeFrame(f.id),
                            ),
                          ),
                      ],
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

/// 单帧卡片。
class _FrameCard extends StatelessWidget {
  const _FrameCard({
    required this.frame,
    required this.selected,
    required this.onEdit,
    required this.onRemove,
  });

  final NoteFrame frame;
  final bool selected;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

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
    return Container(
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
