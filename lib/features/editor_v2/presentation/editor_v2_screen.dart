// editor_v2——EditorV2Screen（批次 E——2026-08-21——2026 最佳实践）。
//
// 最小编辑器 UI（Canvas + 工具栏）——CUJ-01/02/04/05。
// 遵循：直接 Canvas 绘画（CustomPainter）+ RepaintBoundary。
// 纯 Flutter UI——业务逻辑在 EditorV2ViewModel。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:editor_core/editor_core.dart';

import '../../../core/storage/storage_service.dart';

import '../../../../core/theme/responsive.dart';
import '../application/editor_v2_viewmodel.dart';
import '../../../shared/widgets/apple_glass.dart';
import 'binding_hints_widget.dart';
import 'canvas_painter.dart';
import 'infinite_canvas_widget.dart';
import 'magnifier_overlay.dart';
import 'note_editor_widget.dart';
import 'sidebar_widget.dart';
import 'toolbar_widget.dart';

/// Editor V2 最小 Screen（CUJ-01/02/04/05）。
///
/// 架构（2026 最佳实践）：
/// - ViewModel（Riverpod）——不可变状态 + 命令分发
/// - Canvas（CustomPainter + RepaintBoundary）——直接绘画
/// - Toolbar（工具切换）——最小 UI
class EditorV2Screen extends ConsumerStatefulWidget {
  const EditorV2Screen({
    super.key,
    required this.documentId,
    this.mode = UnifiedEditorMode.whiteboard,
  });

  final String documentId;

  /// 统一编辑器模式（笔记/画板共用——Saber Editor 借鉴——2026-08-22——
  /// 默认 whiteboard（无限画布——向后兼容）——note 模式（分页普通画布）。
  final UnifiedEditorMode mode;

  @override
  ConsumerState<EditorV2Screen> createState() => _EditorV2ScreenState();
}

class _EditorV2ScreenState extends ConsumerState<EditorV2Screen>
    with WidgetsBindingObserver {
  /// 画布 RepaintBoundary Key——用于截图取色（P2 #30）。
  final GlobalKey _canvasKey = GlobalKey();

  /// 自动保存防抖计时器（V1/V2 迁移阶段2——2026-08-24）。
  Timer? _autoSaveTimer;
  static const _autoSaveDuration = Duration(milliseconds: 800);

  /// Notifier 引用（dispose 时 ref 不可用，提前捕获）。
  late final EditorV2Notifier _notifier;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _notifier = ref.read(editorV2NotifierProvider.notifier);
    // 初始化文档（CUJ-01 创建）。
    Future.microtask(() {
      _notifier.createDocument(widget.documentId);
      // note 模式：加载/初始化笔记文档（固定 ID——防止重建丢失内容）。
      if (widget.mode == UnifiedEditorMode.note) {
        _notifier.loadNoteDocument(widget.documentId);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 切到后台时立即保存。
    if (state == AppLifecycleState.paused) {
      _saveNow();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoSaveTimer?.cancel();
    _saveNow();
    _removeTextOverlay();
    _textController.dispose();
    _textFocus.dispose();
    super.dispose();
  }

  /// 安排一次防抖自动保存。
  void _scheduleAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(_autoSaveDuration, _saveNow);
  }

  /// 立即执行保存（供切后台、销毁时调用）。
  void _saveNow() {
    // 使用 _notifier 而非 ref.read()——dispose 后 ref 不可用。
    // 保存绘图文档（白板模式）。
    if (widget.mode != UnifiedEditorMode.note) {
      final json = _notifier.toJson();
      StorageService().saveJson(widget.documentId, json).catchError((e, _) {
        debugPrint('EditorV2: _saveNow draw error: $e');
        return '';
      });
    }
    // 保存笔记文档（note 模式）。
    if (widget.mode == UnifiedEditorMode.note) {
      _notifier.saveNoteDocument();
    }
  }

  /// 初始笔记文档（note 模式——Word 文档式——2026-08-22——
  /// 标题 + 一个空段落（直接打字——Word 式））。
  NoteDocument _initialNoteDocument(String documentId) {
    return NoteDocument(
      id: documentId,
      paragraphs: [
        const NoteParagraph(id: 'p1', content: ''),
      ],
    );
  }

  // ──────────────────── 文本输入 Overlay ────────────────────

  /// 就地文本输入（画布 text 工具——修复打字崩溃——2026-08-24）。
  ///
  /// 使用 Overlay 就地编辑，不使用 showDialog（避免模态对话框中断画布手势）。
  OverlayEntry? _textOverlayEntry;
  final TextEditingController _textController = TextEditingController();
  final FocusNode _textFocus = FocusNode();
  Offset _textInputPosition = Offset.zero;

  void _showTextInput(Offset position) {
    _removeTextOverlay();

    _textInputPosition = position;
    _textController.clear();
    _textOverlayEntry = OverlayEntry(
      builder: (ctx) => Positioned(
        left: position.dx,
        top: position.dy,
        child: Material(
          elevation: 4,
          child: Container(
            constraints: BoxConstraints(maxWidth: ctx.responsiveScale(280)),
            padding: EdgeInsets.all(ctx.responsiveScale(8)),
            decoration: BoxDecoration(
              color: Theme.of(ctx).colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                const BoxShadow(
                  color: Colors.black26,
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              controller: _textController,
              focusNode: _textFocus,
              autofocus: true,
              maxLines: null,
              decoration: const InputDecoration(
                hintText: '输入文字...',
                border: InputBorder.none,
              ),
              onSubmitted: (_) => _commitTextInput(),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_textOverlayEntry!);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _textFocus.requestFocus();
    });
  }

  void _commitTextInput() {
    final content = _textController.text.trim();
    if (content.isNotEmpty) {
      ref.read(editorV2NotifierProvider.notifier)
          .addText(content, _textInputPosition.dx, _textInputPosition.dy);
    }
    _removeTextOverlay();
  }

  void _removeTextOverlay() {
    if (_textOverlayEntry != null) {
      _textOverlayEntry!.remove();
      _textOverlayEntry = null;
    }
    _textController.clear();
  }

  // ──────────────────── P2 #30 取色放大镜 ────────────────────

  /// 从画布截图中采样像素颜色。
  Future<Color?> _sampleColorAt(Offset position) async {
    try {
      final boundary = _canvasKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return null;

      final image = await boundary.toImage(
        pixelRatio: MediaQuery.devicePixelRatioOf(context),
      );
      final byteData = await image.toByteData();
      if (byteData == null) return null;

      final buffer = byteData.buffer.asUint8List();
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final px = (position.dx * dpr).toInt();
      final py = (position.dy * dpr).toInt();
      final w = image.width;

      if (px < 0 || px >= w || py < 0 || py >= image.height) return null;

      final offset = (py * w + px) * 4;
      if (offset + 3 >= buffer.length) return null;

      final r = buffer[offset];
      final g = buffer[offset + 1];
      final b = buffer[offset + 2];
      final a = buffer[offset + 3];

      return Color.fromARGB(a, r, g, b);
    } catch (e) {
      debugPrint('ColorMagnifier: 采样失败 $e');
      return null;
    }
  }

  /// 从当前位置取色并更新放大镜。
  Future<void> _pickColorFromCanvas(Offset position) async {
    final color = await _sampleColorAt(position);
    if (color != null && mounted) {
      ref.read(editorV2NotifierProvider.notifier).setMagnifierColor(color);
    }
  }

  /// 获取当前位置的取色结果（用于放大镜显示）。
  PickedColor _getCurrentPickedColor(Offset position) {
    final state = ref.read(editorV2NotifierProvider);
    final c = state.currentColor;
    return PickedColor(
      r: (c.r * 255.0).round().clamp(0, 255),
      g: (c.g * 255.0).round().clamp(0, 255),
      b: (c.b * 255.0).round().clamp(0, 255),
      positionX: position.dx,
      positionY: position.dy,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(editorV2NotifierProvider);

    return Scaffold(
      drawer: context.isMobile ? const EditorV2Sidebar() : null,
      appBar: AppBar(
        title: Text(
          'Editor V2 - ${widget.documentId}',
          style: TextStyle(fontSize: context.responsiveScale(16)),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo),
            onPressed: state.canUndo
                ? () => ref.read(editorV2NotifierProvider.notifier).undo()
                : null,
            tooltip: 'Undo',
          ),
          IconButton(
            icon: const Icon(Icons.redo),
            onPressed: state.canRedo
                ? () => ref.read(editorV2NotifierProvider.notifier).redo()
                : null,
            tooltip: 'Redo',
          ),
        ],
      ),
      body: Row(
        children: [
          // tablet/desktop：固定显示侧边栏；mobile：不显示（用 Drawer）。
          if (!context.isMobile)
            const SizedBox(
              width: 240,
              child: EditorV2Sidebar(),
            ),
          Expanded(
            child: Column(
              children: [
                // ──── 工具栏：根据模式互斥显示（#23 修复——2026-08-24） ────
                if (widget.mode == UnifiedEditorMode.whiteboard) ...[
            // drawing 模式——绘图工具栏（含取色器按钮）。
            Padding(
              padding: EdgeInsets.fromLTRB(
                context.responsiveScale(12),
                context.responsiveScale(8),
                context.responsiveScale(12),
                context.responsiveScale(4),
              ),
              child: AppleGlassWidget.toolbar(
                child: EditorV2Toolbar(
                  currentTool: state.currentTool,
                  brushType: state.brushType,
                  currentShapeType: state.currentShapeType,
                  brushSize: state.brushSize,
                  strokeColorHex: state.strokeColorHex,
                  onToolChanged: (tool) =>
                      ref.read(editorV2NotifierProvider.notifier).setTool(tool),
                  onShapeTypeChanged: (type) =>
                      ref.read(editorV2NotifierProvider.notifier).setShapeType(type),
                  onBrushTypeChanged: (type) =>
                      ref.read(editorV2NotifierProvider.notifier).setBrushType(type),
                  onBrushSizeChanged: (size) =>
                      ref.read(editorV2NotifierProvider.notifier).setBrushSize(size),
                  onColorChanged: (hex) =>
                      ref.read(editorV2NotifierProvider.notifier).setStrokeColor(hex),
                ),
              ),
            ),
          ] else ...[
            // note 模式——文字格式化工具栏（加粗/斜体/下划线/列表/标题）。
            Padding(
              padding: EdgeInsets.fromLTRB(
                context.responsiveScale(12),
                context.responsiveScale(8),
                context.responsiveScale(12),
                context.responsiveScale(4),
              ),
              child: AppleGlassWidget.toolbar(
                child: const _NoteFormattingToolbar(),
              ),
            ),
          ],
          // ──── 画布 ────
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                context.responsiveScale(12),
                context.responsiveScale(4),
                context.responsiveScale(12),
                context.responsiveScale(12),
              ),
              child: AppleGlassWidget.card(
                child: GestureDetector(
                  onTapUp: state.currentTool == 'text'
                      ? (details) => _showTextInput(details.localPosition)
                      : null,
                  // ── 笔画手势（V2 画板修复——2026-08-25） ──
                  onPanStart: (details) {
                    final notifier = ref.read(editorV2NotifierProvider.notifier);
                    final pos = details.localPosition;
                    switch (state.currentTool) {
                      case 'draw':
                        notifier.startStroke(pos);
                        break;
                      case 'eraser':
                        notifier.eraseAt(pos.dx, pos.dy);
                        break;
                      case 'shape':
                        notifier.startShapeDrag(pos);
                        break;
                    }
                  },
                  onPanUpdate: (details) {
                    final notifier = ref.read(editorV2NotifierProvider.notifier);
                    final pos = details.localPosition;
                    switch (state.currentTool) {
                      case 'draw':
                        notifier.extendStroke(pos);
                        break;
                      case 'eraser':
                        notifier.eraseAt(pos.dx, pos.dy);
                        break;
                      case 'shape':
                        // 形状实时预览（暂不渲染——由 endShapeDrag 提交）。
                        break;
                    }
                  },
                  onPanEnd: (details) {
                    final notifier = ref.read(editorV2NotifierProvider.notifier);
                    final pos = details.localPosition;
                    switch (state.currentTool) {
                      case 'draw':
                        notifier.endStroke();
                        break;
                      case 'shape':
                        notifier.endShapeDrag(pos, state.currentShapeType);
                        break;
                    }
                  },
                  // P2 #30：长按画布 → 放大镜取色。
                  onLongPressStart: (details) {
                    final notifier = ref.read(editorV2NotifierProvider.notifier);
                    if (!state.eyedropperActive) {
                      notifier.activateEyedropper();
                    }
                    notifier.updateEyedropperPosition(details.localPosition);
                  },
                  onLongPressMoveUpdate: (details) async {
                    final notifier = ref.read(editorV2NotifierProvider.notifier);
                    notifier.updateEyedropperPosition(details.localPosition);
                    final color = await _sampleColorAt(details.localPosition);
                    if (color != null && mounted) {
                      notifier.setMagnifierColor(color);
                    }
                  },
                  onLongPressEnd: (details) {
                    final notifier = ref.read(editorV2NotifierProvider.notifier);
                    notifier.applyPickedColor(state.currentColor);
                    // 显示取色结果 SnackBar。
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '已取色: #${state.currentColor.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
                          ),
                          duration: const Duration(seconds: 1),
                          backgroundColor: state.currentColor,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                  child: RepaintBoundary(
                    key: _canvasKey,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      switchInCurve: Curves.easeInOut,
                      child: widget.mode == UnifiedEditorMode.whiteboard
                          ? InfiniteCanvasWidget(
                              key: ValueKey('canvas-${state.document.id}'),
                              child: Stack(
                                children: [
                                  CustomPaint(
                                    painter: CanvasPainterV2(
                                      document: state.document,
                                    ),
                                    size: Size.infinite,
                                  ),
                                // P2 #30：取色放大镜覆盖层。
                                if (state.eyedropperActive)
                                  MagnifierOverlay(
                                    cursorPosition: state.eyedropperPosition,
                                    pickedColor: _getCurrentPickedColor(
                                      state.eyedropperPosition,
                                    ),
                                  ),
                                // 节点连线提示（用户需求 #10）。
                                BindingHintsWidget(
                                  currentTool: state.currentTool,
                                  hasShapes: state.document.layers
                                      .any((l) => l.shapes.isNotEmpty),
                                ),
                              ],
                            ),
                          )
                        : NoteEditorWidget(
                            key: ValueKey('note-${state.document.id}'),
                            document: state.noteDocument ??
                                _initialNoteDocument(state.document.id),
                            onChanged: (doc) {
                              ref.read(editorV2NotifierProvider.notifier)
                                  .updateNoteDocument(doc);
                              _scheduleAutoSave();
                            },
                          ),
                    ),
                  ),
                ),
              ),
            ),
          ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ──────────────────── 笔记模式文字格式化工具栏（#23） ────────────────────

/// note 模式工具栏——加粗/斜体/下划线/删除线/列表/标题。
///
/// 与绘图工具栏互斥——同一时间只显示一个。
class _NoteFormattingToolbar extends ConsumerWidget {
  const _NoteFormattingToolbar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(editorV2NotifierProvider);
    final active = state.activeNoteFormatting;

    return SizedBox(
      height: context.responsiveFont(mobile: 44, desktop: 56),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ToolButton(
            icon: Icons.format_bold,
            tooltip: '加粗 (Ctrl+B)',
            isActive: active.contains('bold'),
            onPressed: () {
              ref.read(editorV2NotifierProvider.notifier)
                  .toggleNoteFormatting('bold');
              _scheduleAutoSave(context, ref);
            },
          ),
          _ToolButton(
            icon: Icons.format_italic,
            tooltip: '斜体 (Ctrl+I)',
            isActive: active.contains('italic'),
            onPressed: () {
              ref.read(editorV2NotifierProvider.notifier)
                  .toggleNoteFormatting('italic');
              _scheduleAutoSave(context, ref);
            },
          ),
          _ToolButton(
            icon: Icons.format_underline,
            tooltip: '下划线 (Ctrl+U)',
            isActive: active.contains('underline'),
            onPressed: () {
              ref.read(editorV2NotifierProvider.notifier)
                  .toggleNoteFormatting('underline');
              _scheduleAutoSave(context, ref);
            },
          ),
          _ToolButton(
            icon: Icons.strikethrough_s,
            tooltip: '删除线',
            isActive: active.contains('strikethrough'),
            onPressed: () {
              ref.read(editorV2NotifierProvider.notifier)
                  .toggleNoteFormatting('strikethrough');
              _scheduleAutoSave(context, ref);
            },
          ),
          const VerticalDivider(indent: 8, endIndent: 8),
          _ToolButton(
            icon: Icons.format_list_bulleted,
            tooltip: '无序列表',
            isActive: active.contains('bullet'),
            onPressed: () {
              ref.read(editorV2NotifierProvider.notifier)
                  .toggleNoteFormatting('bullet');
              _scheduleAutoSave(context, ref);
            },
          ),
          _ToolButton(
            icon: Icons.format_list_numbered,
            tooltip: '有序列表',
            isActive: active.contains('numbered'),
            onPressed: () {
              ref.read(editorV2NotifierProvider.notifier)
                  .toggleNoteFormatting('numbered');
              _scheduleAutoSave(context, ref);
            },
          ),
          const VerticalDivider(indent: 8, endIndent: 8),
          _ToolButton(
            icon: Icons.title,
            tooltip: '标题',
            isActive: active.contains('heading'),
            onPressed: () {
              ref.read(editorV2NotifierProvider.notifier)
                  .toggleNoteFormatting('heading');
              _scheduleAutoSave(context, ref);
            },
          ),
        ],
      ),
    );
  }

  void _scheduleAutoSave(BuildContext context, WidgetRef ref) {
    // 格式切换后延迟保存（800ms 防抖）。
    Future.delayed(const Duration(milliseconds: 800), () {
      if (context.mounted) {
        ref.read(editorV2NotifierProvider.notifier).saveNoteDocument();
      }
    });
  }
}

/// 工具按钮封装——统一风格。
class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.isActive = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, size: context.responsiveFont(mobile: 18, desktop: 22)),
        onPressed: onPressed,
        style: IconButton.styleFrom(
          foregroundColor: isActive
              ? Theme.of(context).colorScheme.primary
              : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }
}
