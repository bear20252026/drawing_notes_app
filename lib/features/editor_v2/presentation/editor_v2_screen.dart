// editor_v2——EditorV2Screen（批次 E——2026-08-21——2026 最佳实践）。
//
// 最小编辑器 UI（Canvas + 工具栏）——CUJ-01/02/04/05。
// 遵循：直接 Canvas 绘画（CustomPainter）+ RepaintBoundary。
// 纯 Flutter UI——业务逻辑在 EditorV2ViewModel。
//
// #13 修复（2026-08-24）：Note 模式接入 NotebookStorage 落盘——
// 之前 onChanged 是 no-op，_initialNoteDocument 每次 build 重建为空。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:editor_core/editor_core.dart';

import '../application/editor_v2_viewmodel.dart';
import '../../notes/domain/notebook.dart';
import '../../notes/infrastructure/notebook_storage.dart';
import '../../../shared/widgets/apple_glass.dart';
import 'canvas_painter.dart';
import 'infinite_canvas_widget.dart';
import 'note_document_bridge.dart';
import 'note_editor_widget.dart';
import 'sidebar_widget.dart';
import 'toolbar_widget.dart';

/// Editor V2 最小 Screen（CUJ-01/02/04/05）。
///
/// 架构（2026 最佳实践）：
/// - ViewModel（Riverpod）——不可变状态 + 命令分发
/// - Canvas（CustomPainter + RepaintBoundary）——直接绘画
/// - Toolbar（工具切换）——最小 UI
///
/// Note 模式：通过 NotebookStorage 落盘——新建→打字→自动保存→重开仍在。
class EditorV2Screen extends ConsumerStatefulWidget {
  const EditorV2Screen({
    super.key,
    required this.documentId,
    this.mode = UnifiedEditorMode.whiteboard,
    this.notebookStorage,
  });

  final String documentId;

  /// 统一编辑器模式（笔记/画板共用——Saber Editor 借鉴——2026-08-22——
  /// 默认 whiteboard（无限画布——向后兼容）——note 模式（分页普通画布）。
  final UnifiedEditorMode mode;

  /// 笔记本存储（note 模式必传——#13 落盘修复——2026-08-24）。
  final NotebookStorage? notebookStorage;

  @override
  ConsumerState<EditorV2Screen> createState() => _EditorV2ScreenState();
}

class _EditorV2ScreenState extends ConsumerState<EditorV2Screen> {
  // ──────────────────────────── Note 模式状态 ────────────────────────────

  /// 当前笔记文档（note 模式——从 NotebookStorage 加载——#13 修复）。
  NoteDocument? _noteDocument;

  /// 是否正在加载（note 模式）。
  bool _noteLoading = true;

  /// 自动保存防抖定时器（#13 修复——打字 1.5 秒后自动落盘）。
  Timer? _autoSaveTimer;

  /// 笔记本存储（快捷引用——可能为 null）。
  NotebookStorage? get _nbStorage => widget.notebookStorage;

  @override
  void initState() {
    super.initState();
    if (widget.mode == UnifiedEditorMode.note) {
      _loadNoteDocument();
    } else {
      // Whiteboard 模式：初始化文档（CUJ-01 创建）。
      Future.microtask(() {
        final notifier = ref.read(editorV2NotifierProvider.notifier);
        notifier.createDocument(widget.documentId);
      });
    }
  }

  /// 从 NotebookStorage 加载笔记文档（#13 核心修复）。
  ///
  /// 流程：NotebookStorage.load → Notebook → NoteDocumentBridge.fromNotebook。
  /// 若笔记本不存在或存储为空，创建默认空文档。
  Future<void> _loadNoteDocument() async {
    final storage = _nbStorage;
    if (storage == null) {
      // 无存储——降级为空文档
      setState(() {
        _noteDocument = NoteDocument(
          id: widget.documentId,
          title: '未命名笔记',
          paragraphs: [const NoteParagraph(id: 'p1', content: '')],
        );
        _noteLoading = false;
      });
      return;
    }

    try {
      final notebook = await storage.load(widget.documentId);
      if (notebook != null) {
        final doc = NoteDocumentBridge.fromNotebook(notebook);
        if (mounted) {
          setState(() {
            _noteDocument = doc;
            _noteLoading = false;
          });
        }
      } else {
        // 笔记本不存在——创建新笔记本并保存
        final newNotebook = Notebook(
          id: widget.documentId,
          title: '未命名笔记',
        );
        await storage.save(newNotebook);
        if (mounted) {
          setState(() {
            _noteDocument = NoteDocument(
              id: widget.documentId,
              title: '未命名笔记',
              paragraphs: [const NoteParagraph(id: 'p1', content: '')],
            );
            _noteLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('加载笔记失败: $e');
      if (mounted) {
        setState(() {
          _noteDocument = NoteDocument(
            id: widget.documentId,
            title: '未命名笔记',
            paragraphs: [const NoteParagraph(id: 'p1', content: '')],
          );
          _noteLoading = false;
        });
      }
    }
  }

  /// 保存笔记文档到 NotebookStorage（#13 核心修复）。
  ///
  /// 流程：NoteDocument → NoteDocumentBridge.applyToNotebook → NotebookStorage.save。
  Future<void> _saveNoteDocument() async {
    final storage = _nbStorage;
    final noteDoc = _noteDocument;
    if (storage == null || noteDoc == null) return;

    try {
      final notebook = await storage.load(widget.documentId);
      if (notebook != null) {
        NoteDocumentBridge.applyToNotebook(noteDoc, notebook);
        await storage.save(notebook);
      }
    } catch (e) {
      debugPrint('保存笔记失败: $e');
    }
  }

  /// Note 模式内容变更回调（#13 修复——防抖自动保存）。
  void _onNoteChanged(NoteDocument updated) {
    setState(() {
      _noteDocument = updated;
    });
    // 防抖 1.5 秒后自动保存
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(milliseconds: 1500), _saveNoteDocument);
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    // 离开时立即保存（#13 保障——不丢最后一个字符）
    if (widget.mode == UnifiedEditorMode.note && _noteDocument != null) {
      _saveNoteDocument();
    }
    super.dispose();
  }

  /// 弹出文本输入框（画布 text 工具——修复打字崩溃——2026-08-22）。
  ///
  /// 使用 Flutter 原生 TextField（不依赖 material_ui——避免中文环境崩溃）。
  Future<void> _showTextInput(Offset position) async {
    final controller = TextEditingController();
    final content = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('输入文字'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: '输入文字内容',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (content != null && content.isNotEmpty) {
      ref.read(editorV2NotifierProvider.notifier)
          .addText(content, position.dx, position.dy);
    }
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isNoteMode = widget.mode == UnifiedEditorMode.note;

    // Note 模式：独立 AppBar（不依赖 EditorV2 ViewModel）。
    if (isNoteMode) {
      return _buildNoteMode(context);
    }

    // Whiteboard 模式：原有 Canvas + 工具栏。
    return _buildWhiteboardMode(context);
  }

  // ──────────────────────────── Note 模式 UI ────────────────────────────

  Widget _buildNoteMode(BuildContext context) {
    final noteDoc = _noteDocument;

    return Scaffold(
      appBar: AppBar(
        title: Text(noteDoc?.title ?? '笔记'),
        actions: [
          // 保存状态指示
          if (_noteLoading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          // 手动保存按钮
          IconButton(
            icon: const Icon(Icons.save_outlined),
            onPressed: _noteLoading ? null : _saveNoteDocument,
            tooltip: '保存',
          ),
        ],
      ),
      body: _noteLoading
          ? const Center(child: CircularProgressIndicator())
          : noteDoc == null
              ? const Center(child: Text('加载失败'))
              : NoteEditorWidget(
                  key: ValueKey('note-${widget.documentId}'),
                  document: noteDoc,
                  onChanged: _onNoteChanged,
                ),
    );
  }

  // ──────────────────────────── Whiteboard 模式 UI ────────────────────────────

  Widget _buildWhiteboardMode(BuildContext context) {
    final state = ref.watch(editorV2NotifierProvider);

    return Scaffold(
      drawer: const EditorV2Sidebar(),
      appBar: AppBar(
        title: Text('Editor V2 - ${widget.documentId}'),
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
      body: Column(
        children: [
          // 工具栏
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
          // 画布
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: AppleGlassWidget.card(
                child: GestureDetector(
                  onTapUp: state.currentTool == 'text'
                      ? (details) => _showTextInput(details.localPosition)
                      : null,
                  child: InfiniteCanvasWidget(
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
