// 由 Claude 团队生成 | Drawing Notes App
// EdgelessPage：无限画布（1:1 AFFiNE edgeless）页面。
//
// 提供：pan/zoom 相机、note 帧渲染（只读预览）、拖帧、选中、双击进入编辑器、
// 新增帧、适应画布等。依赖 M8-1（EdgelessDoc/EdgelessCamera/NoteFrame）、
// EdgelessController（手势翻译）与 NoteFramePreview（帧内容）。
// 只依赖 notes，不 import drawing/chart 实现层（架构规则 3）。

import 'package:flutter/foundation.dart' show listEquals, mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:drawing_notes_app/core/theme/apple_design.dart';
import 'package:drawing_notes_app/features/notes/domain/edgeless_connector.dart';
import 'package:drawing_notes_app/features/notes/domain/edgeless_doc.dart';
import 'package:drawing_notes_app/features/notes/domain/edgeless_group.dart';
import 'package:drawing_notes_app/features/notes/domain/edgeless_stroke.dart';
import 'package:drawing_notes_app/features/notes/domain/note_block.dart';
import 'package:drawing_notes_app/features/notes/domain/note_block_doc.dart';
import 'package:drawing_notes_app/features/notes/presentation/edgeless_command_palette.dart';
import 'package:drawing_notes_app/features/notes/presentation/edgeless_controller.dart';
import 'package:drawing_notes_app/features/doc/doc_controller.dart';
import 'package:drawing_notes_app/features/doc/doc_editor.dart';
import 'package:drawing_notes_app/features/doc/doc_page.dart';
import 'package:drawing_notes_app/features/notes/presentation/note_frame_preview.dart';
part 'edgeless_page_widgets.dart';

/// Edgeless 无限画布页。
///
/// 输入初始 [initialDoc] 与变更回调 [onChanged]；双击某帧进入 [DocEditor]
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
  /// 透传给帧内打开 DocEditor 时的内嵌块渲染。
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
    _controller = EdgelessController(
      doc: widget.initialDoc,
      onChanged: widget.onChanged,
    );
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

  void _onTapUp(TapUpDetails d) {
    switch (_controller.tool) {
      case EdgelessTool.eraser:
        _controller.eraseAt(d.localPosition, _viewport);
      case EdgelessTool.sticky:
        _controller.stickyAt(d.localPosition, _viewport);
      case EdgelessTool.select:
      case EdgelessTool.brush:
      case EdgelessTool.shape:
        _controller.tapAt(d.localPosition, _viewport);
    }
  }

  void _onDoubleTap(TapDownDetails d) {
    final world = _controller.screenToWorld(d.localPosition, _viewport);
    final frame = _controller.hitTest(world);
    if (frame != null) {
      _openFrameEditor(frame.id, frame.doc);
    }
  }

  void _onScaleStart(ScaleStartDetails d) =>
      _controller.beginGesture(d.localFocalPoint, d.pointerCount, _viewport);

  Offset? _lastFocal;

  void _onScaleUpdate(ScaleUpdateDetails d) {
    _lastFocal = d.localFocalPoint;
    _controller.updateGesture(
      d.localFocalPoint,
      d.scale,
      d.pointerCount,
      _viewport,
    );
  }

  void _onScaleEnd(ScaleEndDetails _) =>
      _controller.endGesture(lastLocalFocal: _lastFocal, viewport: _viewport);

  Future<void> _openFrameEditor(String frameId, NoteBlockDoc doc) async {
    // M12：帧内文档改为跳转独立笔记页（DocPage），不再内嵌——
    // 修复"在画板中输字即冻结"的内嵌编辑问题。
    final updated = await Navigator.of(context).push<NoteBlockDoc>(
      MaterialPageRoute(
        builder: (_) => DocPage(
          document: doc,
          controller: DocController(onSave: (_) {}),
        ),
      ),
    );
    if (updated != null) {
      _controller.updateFrameDoc(frameId, updated);
    }
  }

  void _addFrame() {
    _controller.addFrame(
      NoteBlockDoc.empty('new_${DateTime.now().microsecondsSinceEpoch}'),
    );
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先选中一个帧作为连线起点')));
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

  /// 视野适配到当前所选帧集的包围盒。
  void _fitSelection() {
    final ids = _controller.selectedFrameIds;
    if (ids.isEmpty) return;
    final frames = _controller.doc.frames
        .where((f) => ids.contains(f.id))
        .toList();
    if (frames.isEmpty) return;
    var rect = frames.first.rect;
    for (final f in frames) {
      rect = rect.expandToInclude(f.rect);
    }
    _controller.fitTo(rect, _viewport, padding: 48);
  }

  /// 打开 ⌘K 命令面板。
  void _openCommandPalette() {
    showEdgelessCommandPalette(
      context,
      controller: _controller,
      onFitContent: _fitTo,
      onFitSelection: _fitSelection,
    );
  }

  /// 全局键盘快捷键：Ctrl/Cmd+K 打开命令面板。
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final kb = HardwareKeyboard.instance;
    final isCmd = kb.isMetaPressed || kb.isControlPressed;
    if (isCmd && event.logicalKey == LogicalKeyboardKey.keyK) {
      _openCommandPalette();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _zoom(double factor) {
    _controller.zoomAt(
      factor,
      focusWorld: _controller.screenToWorld(
        Offset(_viewport.width / 2, _viewport.height / 2),
        _viewport,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Edgeless'),
          actions: [
            IconButton(
              tooltip: '命令面板 (Ctrl+K)',
              icon: const Icon(Icons.keyboard_command_key),
              onPressed: _openCommandPalette,
            ),
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
                          color: Theme.of(
                            context,
                          ).colorScheme.outlineVariant.withValues(alpha: 0.4),
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
                          // 笔迹/形状层（M11：brush / shape / eraser 工具）
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _ElementPainter(
                                strokes: _controller.doc.strokes,
                                shapes: _controller.doc.shapes,
                                activeStroke: _controller.activeStroke,
                                shapeOrigin: _controller.shapeOrigin,
                                shapeKind: _controller.shapeKind,
                                lastFocalWorld: _lastFocal == null
                                    ? null
                                    : _controller.screenToWorld(
                                        _lastFocal!,
                                        _viewport,
                                      ),
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
                                onResize: (topLeft, w, h) =>
                                    _controller.resizeFrame(
                                      f.id,
                                      topLeft: topLeft,
                                      w: w,
                                      h: h,
                                    ),
                                onSetBackground: () {
                                  final idx = _kFrameBackgrounds.indexOf(
                                    f.background,
                                  );
                                  final next =
                                      _kFrameBackgrounds[(idx + 1) %
                                          _kFrameBackgrounds.length];
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
                                chipBgColor: Theme.of(
                                  context,
                                ).colorScheme.surface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // AFFiNE 风格左侧工具面板（M11）
                    const Positioned(
                      left: 8,
                      top: 0,
                      bottom: 0,
                      child: Center(child: _ToolPanel()),
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

/// 帧角手柄枚举。
enum _Corner { topLeft, topRight, bottomLeft, bottomRight }
