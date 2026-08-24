// editor_v2——EditorV2Screen（批次 E——2026-08-21——2026 最佳实践）。
//
// 最小编辑器 UI（Canvas + 工具栏）——CUJ-01/02/04/05。
// 遵循：直接 Canvas 绘画（CustomPainter）+ RepaintBoundary。
// 纯 Flutter UI——业务逻辑在 EditorV2ViewModel。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:editor_core/editor_core.dart';

import '../application/editor_v2_viewmodel.dart';
import '../../../shared/widgets/apple_glass.dart';
import 'canvas_painter.dart';
import 'infinite_canvas_widget.dart';
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

class _EditorV2ScreenState extends ConsumerState<EditorV2Screen> {
  @override
  void initState() {
    super.initState();
    // 初始化文档（CUJ-01 创建）。
    Future.microtask(() {
      final notifier = ref.read(editorV2NotifierProvider.notifier);
    notifier.createDocument(widget.documentId);
    });
  }

  @override
  void dispose() {
    _removeTextOverlay();
    _textController.dispose();
    _textFocus.dispose();
    super.dispose();
  }

  /// 初始笔记文档（note 模式——Word 文档式——2026-08-22——
  /// 标题 + 一个空段落（直接打字——Word 式））。
  NoteDocument _initialNoteDocument(String documentId) {
    return NoteDocument(
      id: documentId,
      title: '未命名笔记',
      paragraphs: [
        NoteParagraph(id: 'p1', content: ''),
      ],
    );
  }

  /// 就地文本输入（画布 text 工具——修复打字崩溃——2026-08-24）。
  ///
  /// 使用 Overlay 就地编辑，不使用 showDialog（避免模态对话框中断画布手势）。
  /// 借鉴 editor_page.dart 的就地编辑实现。
  OverlayEntry? _textOverlayEntry;
  final TextEditingController _textController = TextEditingController();
  final FocusNode _textFocus = FocusNode();
  Offset _textInputPosition = Offset.zero;

  void _showTextInput(Offset position) {
    // 先清理之前的 overlay（如果有）。
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
            constraints: const BoxConstraints(maxWidth: 300),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 8,
                  offset: const Offset(0, 2),
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

    // 延迟聚焦，确保 overlay 已渲染。
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(editorV2NotifierProvider);

    return Scaffold(
      // 侧边栏页面导航（AFFiNE 页面设计借鉴——不大幅变动——
      // 现有工具栏/画布保留——批次 F 页面管理）。
      drawer: const EditorV2Sidebar(),
      appBar: AppBar(
        title: Text('Editor V2 - ${widget.documentId}'),
        actions: [
          // 撤销/重做按钮
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
      body: Column(
        children: [
          // 工具栏（苹果设计语言——Liquid Glass 毛玻璃——2026-08-22——
          // 借鉴 AFFiNE/Saber 清爽 UI——大圆角 + 半透明）。
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: AppleGlassWidget.toolbar(
              child: EditorV2Toolbar(
                currentTool: state.currentTool,
                currentShapeType: state.currentShapeType,
                onToolChanged: (tool) =>
                    ref.read(editorV2NotifierProvider.notifier).setTool(tool),
                onShapeTypeChanged: (type) =>
                    ref.read(editorV2NotifierProvider.notifier).setShapeType(type),
              ),
            ),
          ),
          // 画布（苹果设计语言——Liquid Glass 毛玻璃卡片——2026-08-22——
          // 借鉴 Excalidraw/Saber 清爽画布——半透明 + 圆角 + 页面转换动画）。
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: AppleGlassWidget.card(
                // text 工具时点击画布 → 弹出文本输入框（修复打字崩溃——
                // Flutter 原生 TextField——不依赖 material_ui——不崩溃——2026-08-22）。
                child: GestureDetector(
                  onTapUp: state.currentTool == 'text'
                      ? (details) => _showTextInput(details.localPosition)
                      : null,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    switchInCurve: Curves.easeInOut,
                    // 统一架构（笔记/画板共用——2026-08-22）：
                    // - whiteboard 模式：无限画布（InfiniteCanvas——缩放平移）
                    // - note 模式：Word 文档式编辑器（NoteEditorWidget——
                    //   直接打字——AFFiNE Page 借鉴——2026-08-22）
                    child: widget.mode == UnifiedEditorMode.whiteboard
                        ? InfiniteCanvasWidget(
                            key: ValueKey('canvas-${state.document.id}'),
                            child: RepaintBoundary(
                              child: CustomPaint(
                                painter: CanvasPainterV2(
                                  document: state.document,
                                  fillMode: FillMode.stroke,
                                ),
                                size: Size.infinite,
                              ),
                            ),
                          )
                        : NoteEditorWidget(
                            key: ValueKey('note-${state.document.id}'),
                            document: _initialNoteDocument(state.document.id),
                            onChanged: (_) {},
                          ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
