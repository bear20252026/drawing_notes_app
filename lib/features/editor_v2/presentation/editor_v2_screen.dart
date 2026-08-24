// editor_v2——EditorV2Screen（批次 E——2026-08-21——2026 最佳实践）。
//
// 最小编辑器 UI（Canvas + 工具栏）——CUJ-01/02/04/05。
// 遵循：直接 Canvas 绘画（CustomPainter）+ RepaintBoundary。
// 纯 Flutter UI——业务逻辑在 EditorV2ViewModel。
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:editor_core/editor_core.dart';

import '../application/editor_v2_viewmodel.dart';
import '../application/pdf_import_service.dart';
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
  /// 画布 RepaintBoundary Key——用于截图取色（P2 #30）。
  final GlobalKey _canvasKey = GlobalKey();

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
      ref
          .read(editorV2NotifierProvider.notifier)
          .addText(content, position.dx, position.dy);
    }
    controller.dispose();
  }

  // ──────────────────── P2 #30 放大镜取色器 ────────────────────

  /// 从画布截图中采样像素颜色（真实取色——非占位）。
  ///
  /// 将 RepaintBoundary 渲染为 RGBA 图片，在指针坐标处取像素。
  Future<Color?> _sampleColorAt(Offset position) async {
    try {
      final boundary = _canvasKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return null;

      final image = await boundary.toImage(
        pixelRatio: MediaQuery.devicePixelRatioOf(context),
      );
      final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
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

  /// 从画布取色并应用到当前画笔（用户需求 #7——放大镜取色）。
  Future<void> _pickColorFromCanvas(Offset position) async {
    final color = await _sampleColorAt(position);
    if (color == null) return;
    // 将采样颜色写入状态——同时更新画笔颜色和放大镜显示。
    ref.read(editorV2NotifierProvider.notifier).setMagnifierColor(color);
  }

  /// 导入 PDF（多页 → 多页画布背景——Saber 借鉴）。
  Future<void> _importPdf() async {
    try {
      final pages = await PdfImportService.importPdf('');
      if (pages.isNotEmpty && mounted) {
        // TODO: 将导入的页面添加到编辑器
        // 实际实现需要通过 ViewModel 添加多页支持
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF 导入失败: $e')),
        );
      }
    }
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
      body: Row(
        children: [
          // 工具栏——根据模式互斥显示（2026-08-24 修复 #23）。
          // note 模式：文字格式化工具栏（加粗/斜体/列表/标题等）。
          // drawing 模式：绘图工具栏（画笔/形状/颜色等 + eyedropper 取色）。
          if (widget.mode == UnifiedEditorMode.whiteboard) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: AppleGlassWidget.toolbar(
                child: EditorV2Toolbar(
                  currentTool: state.currentTool,
                  currentShapeType: state.currentShapeType,
                  onToolChanged: (tool) {
                    final notifier =
                        ref.read(editorV2NotifierProvider.notifier);
                    if (tool == 'eyedropper') {
                      notifier.activateEyedropper();
                    } else {
                      if (state.eyedropperActive) {
                        notifier.deactivateEyedropper();
                      }
                      notifier.setTool(tool);
                    }
                  },
                  onShapeTypeChanged: (type) => ref
                      .read(editorV2NotifierProvider.notifier)
                      .setShapeType(type),
                  onImportPdf: _importPdf,
                ),
              ),
            ),
          ] else ...[
            // 笔记模式——文字格式化工具栏（加粗/斜体/下划线/删除线/列表/标题）。
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: AppleGlassWidget.toolbar(
                child: const _NoteFormattingToolbar(),
              ),
            ),
          ],
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
                      ? (details) => ref
                          .read(editorV2NotifierProvider.notifier)
                          .updateEyedropperPosition(details.localPosition)
                      : null,
                  onPanUpdate: state.eyedropperActive
                      ? (details) async {
                          ref
                              .read(editorV2NotifierProvider.notifier)
                              .updateEyedropperPosition(details.localPosition);
                          // 实时采样颜色。
                          final color =
                              await _sampleColorAt(details.localPosition);
                          if (color != null && mounted) {
                            ref
                                .read(editorV2NotifierProvider.notifier)
                                .setMagnifierColor(color);
                          }
                        }
                      : null,
                  onPanEnd: state.eyedropperActive
                      ? (details) =>
                          _pickColorFromCanvas(state.eyedropperPosition)
                      : null,
                  // P2 #30：长按画布也触发取色（移动端交互——无需先选 eyedropper 工具）。
                  onLongPressStart: (details) {
                    final notifier =
                        ref.read(editorV2NotifierProvider.notifier);
                    if (!state.eyedropperActive) {
                      notifier.activateEyedropper();
                    }
                    notifier.updateEyedropperPosition(details.localPosition);
                  },
                  onLongPressMoveUpdate: (details) async {
                    ref
                        .read(editorV2NotifierProvider.notifier)
                        .updateEyedropperPosition(details.localPosition);
                    final color =
                        await _sampleColorAt(details.localPosition);
                    if (color != null && mounted) {
                      ref
                          .read(editorV2NotifierProvider.notifier)
                          .setMagnifierColor(color);
                    }
                  },
                  onLongPressEnd: (details) {
                    final notifier =
                        ref.read(editorV2NotifierProvider.notifier);
                    _pickColorFromCanvas(state.eyedropperPosition);
                    notifier.deactivateEyedropper();
                  },
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
                              key: _canvasKey,
                              child: Stack(
                                children: [
                                  CustomPaint(
                                    painter: CanvasPainterV2(
                                      document: state.document,
                                      fillMode: state.currentTool == 'eraser'
                                          ? FillMode.erase
                                          : FillMode.stroke,
                                    ),
                                    size: Size.infinite,
                                  ),
                                  // 取色放大镜覆盖层（P2 #30——用户需求 #7）。
                                  if (state.eyedropperActive)
                                    MagnifierOverlay(
                                      cursorPosition:
                                          state.eyedropperPosition,
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
                            document:
                                _initialNoteDocument(state.document.id),
                            onChanged: (_) {},
                          ),
                  ),
                ),
              ),
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

  /// 获取当前位置的取色结果（用于放大镜显示）。
  ///
  /// 优先使用实时采样的颜色（通过 MagnifierOverlay 传入），
  // 如果没有则返回占位灰色。
  Color _getCurrentPickedColor(Offset position) {
    // 取色器已通过 setMagnifierColor 实时更新状态，
    // 此处直接返回状态中的颜色即可。
    final state = ref.read(editorV2NotifierProvider);
    return state.currentColor;
  }
}

/// 笔记模式——文字格式化工具栏（#23 修复——2026-08-24）。
///
/// note 模式显示：加粗/斜体/下划线/删除线/无序列表/有序列表/标题。
/// 与绘图工具栏互斥——同一时间只显示一个。
class _NoteFormattingToolbar extends StatelessWidget {
  const _NoteFormattingToolbar();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ToolButton(
            icon: Icons.format_bold,
            tooltip: '加粗 (Ctrl+B)',
            onPressed: () {
              // TODO: 接入富文本编辑器加粗逻辑
            },
          ),
          _ToolButton(
            icon: Icons.format_italic,
            tooltip: '斜体 (Ctrl+I)',
            onPressed: () {
              // TODO: 接入富文本编辑器斜体逻辑
            },
          ),
          _ToolButton(
            icon: Icons.format_underline,
            tooltip: '下划线 (Ctrl+U)',
            onPressed: () {
              // TODO: 接入富文本编辑器下划线逻辑
            },
          ),
          _ToolButton(
            icon: Icons.strikethrough_s,
            tooltip: '删除线',
            onPressed: () {
              // TODO: 接入富文本编辑器删除线逻辑
            },
          ),
          const VerticalDivider(indent: 8, endIndent: 8),
          _ToolButton(
            icon: Icons.format_list_bulleted,
            tooltip: '无序列表',
            onPressed: () {
              // TODO: 接入列表逻辑
            },
          ),
          _ToolButton(
            icon: Icons.format_list_numbered,
            tooltip: '有序列表',
            onPressed: () {
              // TODO: 接入列表逻辑
            },
          ),
          const VerticalDivider(indent: 8, endIndent: 8),
          _ToolButton(
            icon: Icons.title,
            tooltip: '标题',
            onPressed: () {
              // TODO: 接入标题逻辑
            },
          ),
        ],
      ),
    );
  }
}

/// 工具按钮封装——统一风格。
class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, size: 20),
        onPressed: onPressed,
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }
}
