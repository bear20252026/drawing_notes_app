// editor_v2——EditorV2Screen（批?E—?026-08-21—?026 最佳实践）?//
// 最小编辑器 UI（Canvas + 工具栏）——CUJ-01/02/04/05?// 遵循：直?Canvas 绘画（CustomPainter? RepaintBoundary?// ?Flutter UI——业务逻辑?EditorV2ViewModel?library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:editor_core/editor_core.dart';

import '../domain/editor_repository.dart';
import '../../../core/ui/widgets/app_snackbar.dart';

import '../../../../core/theme/responsive.dart';
import '../../../../core/theme/app_design.dart';
import '../application/editor_v2_viewmodel.dart';
import '../../../shared/widgets/apple_glass.dart';
import 'binding_hints_widget.dart';
import 'canvas_painter.dart';
import 'infinite_canvas_widget.dart';
import 'magnifier_overlay.dart';
import 'note_editor_widget.dart';
import 'sidebar_widget.dart';
import 'toolbar_widget.dart';

/// Editor V2 最?Screen（CUJ-01/02/04/05）?///
/// 架构?026 最佳实践）?/// - ViewModel（Riverpod）——不可变状?+ 命令分发
/// - Canvas（CustomPainter + RepaintBoundary）——直接绘?/// - Toolbar（工具切换）——最?UI
class EditorV2Screen extends ConsumerStatefulWidget {
  const EditorV2Screen({
    super.key,
    required this.documentId,
    this.mode = UnifiedEditorMode.whiteboard,
  });

  final String documentId;

  /// 统一编辑器模式（笔记/画板共用——Saber Editor 借鉴—?026-08-22—?  /// 默认 whiteboard（无限画布——向后兼容）——note 模式（分页普通画布）?  final UnifiedEditorMode mode;

  @override
  ConsumerState<EditorV2Screen> createState() => _EditorV2ScreenState();
}

class _EditorV2ScreenState extends ConsumerState<EditorV2Screen>
    with WidgetsBindingObserver {
  /// 画布 RepaintBoundary Key——用于截图取色（P2 #30）?  final GlobalKey _canvasKey = GlobalKey();

  /// 自动保存防抖计时器（V1/V2 迁移阶段2—?026-08-24）?  Timer? _autoSaveTimer;
  static const _autoSaveDuration = Duration(milliseconds: 800);

  /// 右侧图层/属性面板可见性（白板模式——V1 风格布局）?  bool _layersVisible = false;
  bool _propertiesVisible = false;

  /// Notifier 引用（dispose ?ref 不可用，提前捕获）?  late final EditorV2Notifier _notifier;

  /// Apple 风格：文档标题（?StorageService 加载，非硬编?documentId）?  String _documentTitle = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _notifier = ref.read(editorV2NotifierProvider.notifier);
    // 初始化文档（CUJ-01 创建）?    Future.microtask(() async {
      _notifier.createDocument(widget.documentId);
      // note 模式：加?初始化笔记文档（固定 ID——防止重建丢失内容）?      if (widget.mode == UnifiedEditorMode.note) {
        _notifier.loadNoteDocument(widget.documentId);
      }
      // 加载文档标题（Apple 风格：显示可读标题而非原始 ID）?      await _loadDocumentTitle();
    });
  }

  /// ?StorageService 加载文档标题?  Future<void> _loadDocumentTitle() async {
    try {
      final docs = await ref.read(editorRepositoryProvider).listDocumentMeta();
      final meta = docs.where((d) => d.id == widget.documentId).firstOrNull;
      if (mounted && meta != null) {
        setState(() {
          _documentTitle = meta.title;
        });
      }
    } catch (_) {
      // 加载失败时静默——使用默认标题?    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 切到后台时立即保存?    if (state == AppLifecycleState.paused) {
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

  /// 安排一次防抖自动保存?  void _scheduleAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(_autoSaveDuration, _saveNow);
  }

  /// 立即执行保存（供切后台、销毁时调用）?  void _saveNow() {
    // 使用 _notifier 而非 ref.read()——dispose ?ref 不可用?    // 保存绘图文档（白板模式）?    if (widget.mode != UnifiedEditorMode.note) {
      final json = _notifier.toJson();
      ref.read(editorRepositoryProvider).saveDocument(widget.documentId, json).catchError((e, _) {
        debugPrint('EditorV2: _saveNow draw error: $e');
        return '';
      });
    }
    // 保存笔记文档（note 模式）?    if (widget.mode == UnifiedEditorMode.note) {
      _notifier.saveNoteDocument();
    }
  }

  /// 初始笔记文档（note 模式——Word 文档式—?026-08-22—?  /// 标题 + 一个空段落（直接打字——Word 式））?  NoteDocument _initialNoteDocument(String documentId) {
    return NoteDocument(
      id: documentId,
      paragraphs: [
        const NoteParagraph(id: 'p1', content: ''),
      ],
    );
  }

  // ──────────────────── 文本输入 Overlay ────────────────────

  /// 就地文本输入（画?text 工具——修复打字崩溃—?026-08-24）?  ///
  /// 使用 Overlay 就地编辑，不使用 showDialog（避免模态对话框中断画布手势）?  OverlayEntry? _textOverlayEntry;
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

  // ──────────────────── P2 #30 取色放大?────────────────────

  /// 从画布截图中采样像素颜色?  Future<Color?> _sampleColorAt(Offset position) async {
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

  /// 从当前位置取色并更新放大镜?  Future<void> _pickColorFromCanvas(Offset position) async {
    final color = await _sampleColorAt(position);
    if (color != null && mounted) {
      ref.read(editorV2NotifierProvider.notifier).setMagnifierColor(color);
    }
  }

  /// Apple 风格：处理导出操作（PDF/PNG/PPT）?  Future<void> _handleExport(String format) async {
    // TODO: 导出功能需要适配 V2 数据模型（NoteDocument/LineItem?    if (mounted) {
      AppSnackbar.showInfo(context, '导出功能即将推出');
    }
  }

  /// 获取当前位置的取色结果（用于放大镜显示）?  PickedColor _getCurrentPickedColor(Offset position) {
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
        // Apple 风格：用户可读标?        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          _documentTitle.isNotEmpty ? _documentTitle : '无标?,
          style: AppDesign.bodyStrong,
        ),
        actions: context.isMobile
            ? [
                // 移动端：收进单个 PopupMenuButton，避?AppBar 溢出
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_horiz),
                  tooltip: '更多',
                  onSelected: (value) {
                    switch (value) {
                      case 'undo':
                        if (state.canUndo) ref.read(editorV2NotifierProvider.notifier).undo();
                        break;
                      case 'redo':
                        if (state.canRedo) ref.read(editorV2NotifierProvider.notifier).redo();
                        break;
                      case 'layers':
                        setState(() => _layersVisible = !_layersVisible);
                        break;
                      case 'properties':
                        setState(() => _propertiesVisible = !_propertiesVisible);
                        break;
                      case 'export_pdf':
                      case 'export_png':
                      case 'export_ppt':
                        _handleExport(value);
                        break;
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'undo', child: Text('撤销')),
                    const PopupMenuItem(value: 'redo', child: Text('重做')),
                    if (widget.mode == UnifiedEditorMode.whiteboard) ...[
                      const PopupMenuItem(value: 'layers', child: Text('图层')),
                      const PopupMenuItem(value: 'properties', child: Text('属?)),
                    ],
                    const PopupMenuDivider(),
                    const PopupMenuItem(value: 'export_pdf', child: Text('导出 PDF')),
                    const PopupMenuItem(value: 'export_png', child: Text('导出 PNG')),
                    const PopupMenuItem(value: 'export_ppt', child: Text('导出 PPT')),
                  ],
                ),
              ]
            : [
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
          // 右侧面板切换（白板模式——仿 V1 布局）?          if (widget.mode == UnifiedEditorMode.whiteboard) ...[
            IconButton(
              icon: Icon(_layersVisible ? Icons.layers : Icons.layers_outlined),
              onPressed: () => setState(() => _layersVisible = !_layersVisible),
              tooltip: '图层',
            ),
            IconButton(
              icon: Icon(_propertiesVisible
                  ? Icons.tune
                  : Icons.tune_outlined),
              onPressed: () =>
                  setState(() => _propertiesVisible = !_propertiesVisible),
              tooltip: '属?,
            ),
          ],
          // Apple 风格：导出菜单（PDF/PNG/PPT?          PopupMenuButton<String>(
            icon: const Icon(Icons.ios_share_rounded),
            tooltip: '导出',
            onSelected: (value) => _handleExport(value),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'export_pdf',
                child: Row(
                  children: [
                    Icon(Icons.picture_as_pdf, color: AppDesign.primary, size: 20),
                    const SizedBox(width: 12),
                    Text('导出 PDF', style: AppDesign.body),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'export_png',
                child: Row(
                  children: [
                    Icon(Icons.image, color: AppDesign.primary, size: 20),
                    const SizedBox(width: 12),
                    Text('导出 PNG', style: AppDesign.body),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'export_ppt',
                child: Row(
                  children: [
                    Icon(Icons.slideshow, color: AppDesign.primary, size: 20),
                    const SizedBox(width: 12),
                    Text('导出 PPT', style: AppDesign.body),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: widget.mode == UnifiedEditorMode.whiteboard
          // ──── 白板模式：V1 风格布局（左侧工?+ 中央画布 + 右侧属性面板） ────
          ? _buildWhiteboardLayout(context, state)
          // ──── 笔记模式：保?V2 风格 ────
          : _buildNoteLayout(context, state),
    );
  }

  /// 白板模式布局——仿 V1 编辑器：左侧窄工具条 + 中央画布 + 右侧属性面板?  Widget _buildWhiteboardLayout(BuildContext context, EditorV2State state) {
    return Row(
      children: [
        // ── 左侧工具条（窄面板，V1 风格?──
        _V2LeftToolbar(
          currentTool: state.currentTool,
          currentShapeType: state.currentShapeType,
          onToolChanged: (tool) =>
              ref.read(editorV2NotifierProvider.notifier).setTool(tool),
          onShapeTypeChanged: (type) =>
              ref.read(editorV2NotifierProvider.notifier).setShapeType(type),
        ),
        // ── 中央画布区域（含顶部工具?+ 画布?──
        Expanded(
          child: Column(
            children: [
              // 顶部绘图工具栏（笔刷/颜色/尺寸）?              Padding(
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
                    onShapeTypeChanged: (type) => ref
                        .read(editorV2NotifierProvider.notifier)
                        .setShapeType(type),
                    onBrushTypeChanged: (type) => ref
                        .read(editorV2NotifierProvider.notifier)
                        .setBrushType(type),
                    onBrushSizeChanged: (size) => ref
                        .read(editorV2NotifierProvider.notifier)
                        .setBrushSize(size),
                    onColorChanged: (hex) => ref
                        .read(editorV2NotifierProvider.notifier)
                        .setStrokeColor(hex),
                  ),
                ),
              ),
              // 画布（支持笔画手?+ 取色?+ 形状拖拽）?              Expanded(
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
                          ? (details) =>
                              _showTextInput(details.localPosition)
                          : null,
                      onPanStart: (details) {
                        final notifier =
                            ref.read(editorV2NotifierProvider.notifier);
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
                        final notifier =
                            ref.read(editorV2NotifierProvider.notifier);
                        final pos = details.localPosition;
                        switch (state.currentTool) {
                          case 'draw':
                            notifier.extendStroke(pos);
                            break;
                          case 'eraser':
                            notifier.eraseAt(pos.dx, pos.dy);
                            break;
                          case 'shape':
                            break;
                        }
                      },
                      onPanEnd: (details) {
                        final notifier =
                            ref.read(editorV2NotifierProvider.notifier);
                        final pos = details.localPosition;
                        switch (state.currentTool) {
                          case 'draw':
                            notifier.endStroke();
                            break;
                          case 'shape':
                            notifier.endShapeDrag(
                                pos, state.currentShapeType);
                            break;
                        }
                      },
                      onLongPressStart: (details) {
                        final notifier =
                            ref.read(editorV2NotifierProvider.notifier);
                        if (!state.eyedropperActive) {
                          notifier.activateEyedropper();
                        }
                      },
                      onLongPressMoveUpdate: (details) {
                        ref
                            .read(editorV2NotifierProvider.notifier)
                            .updateEyedropperPosition(
                                details.localPosition);
                        _pickColorFromCanvas(details.localPosition);
                      },
                      onLongPressEnd: (details) {
                        final notifier =
                            ref.read(editorV2NotifierProvider.notifier);
                        final c = state.currentColor;
                        notifier.deactivateEyedropper();
                        if (mounted) {
                          AppSnackbar.showInfo(
                            context,
                            '已取? #${c.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
                            duration: const Duration(seconds: 1),
                          );
                        }
                      },
                      child: RepaintBoundary(
                        key: _canvasKey,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          switchInCurve: Curves.easeInOut,
                          child: InfiniteCanvasWidget(
                            key: ValueKey('canvas-${state.document.id}'),
                            child: Stack(
                              children: [
                                CustomPaint(
                                  painter: CanvasPainterV2(
                                    document: state.document,
                                  ),
                                  size: Size.infinite,
                                ),
                                if (state.eyedropperActive)
                                  MagnifierOverlay(
                                    cursorPosition:
                                        state.eyedropperPosition,
                                    pickedColor: _getCurrentPickedColor(
                                        state.eyedropperPosition),
                                  ),
                                BindingHintsWidget(
                                  currentTool: state.currentTool,
                                  hasShapes: state.document.layers.any(
                                      (l) => l.shapes.isNotEmpty),
                                ),
                              ],
                            ),
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
        // ── 右侧图层/属性面板（可收起，V1 风格?──
        if (_layersVisible || _propertiesVisible)
          _V2RightPanel(
            layersVisible: _layersVisible,
            propertiesVisible: _propertiesVisible,
            state: state,
            onToggleLayers: () =>
                setState(() => _layersVisible = !_layersVisible),
            onToggleProperties: () =>
                setState(() => _propertiesVisible = !_propertiesVisible),
          ),
      ],
    );
  }

  /// 笔记模式布局——保?V2 风格（侧边栏 + 顶部工具?+ 笔记编辑器）?  Widget _buildNoteLayout(BuildContext context, EditorV2State state) {
    return Row(
      children: [
        if (!context.isMobile)
          const SizedBox(
            width: 240,
            child: EditorV2Sidebar(),
          ),
        Expanded(
          child: Column(
            children: [
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
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    context.responsiveScale(12),
                    context.responsiveScale(4),
                    context.responsiveScale(12),
                    context.responsiveScale(12),
                  ),
                  child: AppleGlassWidget.card(
                    child: NoteEditorWidget(
                      key: ValueKey('note-${state.document.id}'),
                      document: state.noteDocument ??
                          _initialNoteDocument(state.document.id),
                      onChanged: (doc) {
                        ref
                            .read(editorV2NotifierProvider.notifier)
                            .updateNoteDocument(doc);
                        _scheduleAutoSave();
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ──────────────────── 笔记模式文字格式化工具栏?23?────────────────────

/// note 模式工具栏——加?斜体/下划?删除?列表/标题?///
/// 与绘图工具栏互斥——同一时间只显示一个?class _NoteFormattingToolbar extends ConsumerWidget {
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
            tooltip: '下划?(Ctrl+U)',
            isActive: active.contains('underline'),
            onPressed: () {
              ref.read(editorV2NotifierProvider.notifier)
                  .toggleNoteFormatting('underline');
              _scheduleAutoSave(context, ref);
            },
          ),
          _ToolButton(
            icon: Icons.strikethrough_s,
            tooltip: '删除?,
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
    // 格式切换后延迟保存（800ms 防抖）?    Future.delayed(const Duration(milliseconds: 800), () {
      if (context.mounted) {
        ref.read(editorV2NotifierProvider.notifier).saveNoteDocument();
      }
    });
  }
}

/// 工具按钮封装——统一风格?class _ToolButton extends StatelessWidget {
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

/// V2 左侧窄工具条（白板模式——仿 V1 布局）?class _V2LeftToolbar extends StatelessWidget {
  const _V2LeftToolbar({
    required this.currentTool,
    required this.currentShapeType,
    required this.onToolChanged,
    required this.onShapeTypeChanged,
  });

  final String currentTool;
  final String currentShapeType;
  final ValueChanged<String> onToolChanged;
  final ValueChanged<String> onShapeTypeChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          right: BorderSide(
            color: Theme.of(context).dividerTheme.color?.withValues(alpha: 0.12) ?? Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.12),
          ),
        ),
      ),
      child: SingleChildScrollView(
        child: Column(
        children: [
          const SizedBox(height: 8),
          _LeftToolBtn(
            icon: Icons.draw,
            tooltip: '画笔',
            isActive: currentTool == 'draw',
            onTap: () => onToolChanged('draw'),
          ),
          _LeftToolBtn(
            icon: Icons.auto_fix_high,
            tooltip: '橡皮?,
            isActive: currentTool == 'eraser',
            onTap: () => onToolChanged('eraser'),
          ),
          _LeftToolBtn(
            icon: Icons.text_fields,
            tooltip: '文字',
            isActive: currentTool == 'text',
            onTap: () => onToolChanged('text'),
          ),
          _LeftToolBtn(
            icon: Icons.rectangle_outlined,
            tooltip: '形状',
            isActive: currentTool == 'shape',
            onTap: () => onToolChanged('shape'),
          ),
          const Divider(height: 16),
          _LeftToolBtn(
            icon: Icons.pan_tool,
            tooltip: '选择',
            isActive: currentTool == 'select',
            onTap: () => onToolChanged('select'),
          ),
          _LeftToolBtn(
            icon: Icons.zoom_in,
            tooltip: '缩放',
            isActive: currentTool == 'zoom',
            onTap: () => onToolChanged('zoom'),
          ),
        ],
      ),
      ),
    );
  }
}

/// 左侧工具条中的单个按钮?class _LeftToolBtn extends StatelessWidget {
  const _LeftToolBtn({
    required this.icon,
    required this.tooltip,
    required this.isActive,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: SizedBox(
        width: 40,
        height: 40,
        child: Tooltip(
          message: tooltip,
          child: Material(
            color: isActive
                ? colorScheme.primaryContainer.withValues(alpha: 0.4)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onTap,
              child: Icon(
                icon,
                size: 20,
                color: isActive
                    ? colorScheme.primary
                    : colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// V2 右侧面板（图层列?+ 属性面板）?class _V2RightPanel extends ConsumerWidget {
  const _V2RightPanel({
    required this.layersVisible,
    required this.propertiesVisible,
    required this.state,
    required this.onToggleLayers,
    required this.onToggleProperties,
  });

  final bool layersVisible;
  final bool propertiesVisible;
  final EditorV2State state;
  final VoidCallback onToggleLayers;
  final VoidCallback onToggleProperties;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final children = <Widget>[];

    if (layersVisible) {
      children.add(
        SizedBox(
          width: 200,
          child: Container(
            decoration: BoxDecoration(
              color: colorScheme.surface,
              border: Border(
                left: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.12),
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.layers, size: 16, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('图层',
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: onToggleLayers,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    itemCount: state.document.layers.length,
                    itemBuilder: (context, index) {
                      final layer = state.document.layers[index];
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: Color(0xFFE0E0E0), width: 0.5),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              layer.visible
                                  ? Icons.visibility_rounded
                                  : Icons.visibility_off_rounded,
                              size: 18,
                              color: const Color(0xFF0066CC),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    layer.name,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                      color: Color(0xFF1D1D1F),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${layer.shapes.length} 个形?,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFF8E8E93),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (propertiesVisible) {
      children.add(
        SizedBox(
          width: 220,
          child: Container(
            decoration: BoxDecoration(
              color: colorScheme.surface,
              border: Border(
                left: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.12),
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.tune, size: 16, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('属?,
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: onToggleProperties,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      Text('笔刷大小',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: colorScheme.onSurface.withValues(alpha: 0.7))),
                      Slider(
                        value: state.brushSize,
                        min: 1,
                        max: 50,
                        onChanged: (v) => ref
                            .read(editorV2NotifierProvider.notifier)
                            .setBrushSize(v),
                      ),
                      const SizedBox(height: 16),
                      Text('画笔类型',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: colorScheme.onSurface.withValues(alpha: 0.7))),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: BrushType.values.map((bt) {
                          final isActive = state.brushType == bt.name;
                          return ChoiceChip(
                            label: Text(bt.name,
                                style: const TextStyle(fontSize: 11)),
                            selected: isActive,
                            onSelected: (_) => ref
                                .read(editorV2NotifierProvider.notifier)
                                .setBrushType(bt.name),
                            visualDensity: VisualDensity.compact,
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      Text('形状类型',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: colorScheme.onSurface.withValues(alpha: 0.7))),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: ['rectangle', 'circle', 'line', 'arrow'].map((t) {
                          final isActive = state.currentShapeType == t;
                          return ChoiceChip(
                            label: Text(t,
                                style: const TextStyle(fontSize: 11)),
                            selected: isActive,
                            onSelected: (_) => ref
                                .read(editorV2NotifierProvider.notifier)
                                .setShapeType(t),
                            visualDensity: VisualDensity.compact,
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(children: children);
  }
}
