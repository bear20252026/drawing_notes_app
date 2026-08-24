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
import '../application/stroke_style_notifier.dart';
import '../../../shared/widgets/apple_glass.dart';
import 'binding_hints_widget.dart';
import 'canvas_painter.dart';
import 'infinite_canvas_widget.dart';
import 'magnifier_overlay.dart';
import 'note_editor_widget.dart';
import 'property_panel.dart';
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

  /// 从画布取色并应用到当前画笔（用户需求 #7——放大镜取色）。
  void _pickColorFromCanvas(Offset position) {
    // 根据位置附近的颜色生成取色结果。
    // 实际应用中应从 RenderRepaintBoundary 获取像素数据。
    // 此处使用画布背景色作为简化实现。
    final pickedColor = PickedColor(
      r: 255, g: 255, b: 255, // 默认白色（画布背景）。
      positionX: position.dx,
      positionY: position.dy,
    );
    ref.read(strokeStyleProvider.notifier).updateColor(pickedColor.hex);
    ref.read(editorV2NotifierProvider.notifier).applyPickedColor(pickedColor.hex);
  }

  /// 获取当前位置的取色结果（用于放大镜显示）。
  PickedColor _getCurrentPickedColor(Offset position) {
    // 简化实现：根据位置附近的形状颜色返回。
    // 实际应用中应从 RenderRepaintBoundary 获取像素数据。
    return PickedColor(
      r: 128, g: 128, b: 128, // 默认灰色。
      positionX: position.dx,
      positionY: position.dy,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(editorV2NotifierProvider);
    final strokeStyle = ref.watch(strokeStyleProvider);

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
      body: Row(
        children: [
          // 左侧：工具栏 + 画布
          Expanded(
            child: Column(
              children: [
                // 工具栏（苹果设计语言——Liquid Glass 毛玻璃——2026-08-22——
                // 借鉴 AFFiNE/Saber 清爽 UI——大圆角 + 半透明）。
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: AppleGlassWidget.toolbar(
                    child: EditorV2Toolbar(
                      currentTool: state.currentTool,
                      currentShapeType: state.currentShapeType,
                      onToolChanged: (tool) {
                        final notifier = ref.read(editorV2NotifierProvider.notifier);
                        if (tool == 'eyedropper') {
                          notifier.activateEyedropper();
                        } else {
                          if (state.eyedropperActive) {
                            notifier.deactivateEyedropper();
                          }
                          notifier.setTool(tool);
                        }
                      },
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
                      // eyedropper 工具时 → 显示放大取色镜。
                      child: GestureDetector(
                        onTapUp: state.currentTool == 'text'
                            ? (details) => _showTextInput(details.localPosition)
                            : null,
                        onPanStart: state.eyedropperActive
                            ? (details) => ref.read(editorV2NotifierProvider.notifier)
                                .updateEyedropperPosition(details.localPosition)
                            : null,
                        onPanUpdate: state.eyedropperActive
                            ? (details) => ref.read(editorV2NotifierProvider.notifier)
                                .updateEyedropperPosition(details.localPosition)
                            : null,
                        onPanEnd: state.eyedropperActive
                            ? (details) => _pickColorFromCanvas(state.eyedropperPosition)
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
                                    child: Stack(
                                      children: [
                                        CustomPaint(
                                          painter: CanvasPainterV2(
                                            document: state.document,
                                            fillMode: strokeStyle.fillMode,
                                          ),
                                          size: Size.infinite,
                                        ),
                                        // 取色放大镜覆盖层（用户需求 #7）。
                                        if (state.eyedropperActive)
                                          MagnifierOverlay(
                                            cursorPosition: state.eyedropperPosition,
                                            pickedColor: _getCurrentPickedColor(
                                                state.eyedropperPosition),
                                          ),
                                        // 节点连线提示（用户需求 #10——交互提示/空态引导）。
                                        BindingHintsWidget(
                                          currentTool: state.currentTool,
                                          hasShapes: state.document.layers
                                              .any((l) => l.shapes.isNotEmpty),
                                        ),
                                      ],
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
          ),
          // 右侧：属性面板（AFFiNE 借鉴——颜色/填充模式/线宽/透明度）。
          const Padding(
            padding: EdgeInsets.fromLTRB(0, 8, 8, 8),
            child: PropertyPanel(),
          ),
        ],
      ),
    );
  }
}
