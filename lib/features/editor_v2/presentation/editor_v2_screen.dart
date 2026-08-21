// editor_v2——EditorV2Screen（批次 E——2026-08-21——2026 最佳实践）。
//
// 最小编辑器 UI（Canvas + 工具栏）——CUJ-01/02/04/05。
// 遵循：直接 Canvas 绘画（CustomPainter）+ RepaintBoundary。
// 纯 Flutter UI——业务逻辑在 EditorV2ViewModel。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/editor_v2_viewmodel.dart';
import 'canvas_painter.dart';
import 'infinite_canvas_widget.dart';
import 'sidebar_widget.dart';
import 'toolbar_widget.dart';

/// Editor V2 最小 Screen（CUJ-01/02/04/05）。
///
/// 架构（2026 最佳实践）：
/// - ViewModel（Riverpod）——不可变状态 + 命令分发
/// - Canvas（CustomPainter + RepaintBoundary）——直接绘画
/// - Toolbar（工具切换）——最小 UI
class EditorV2Screen extends ConsumerStatefulWidget {
  const EditorV2Screen({super.key, required this.documentId});

  final String documentId;

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
          // 工具栏（AFFiNE 质感升级——Card 容器——圆角/阴影/边框——精致感）。
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade300),
              ),
              clipBehavior: Clip.antiAlias,
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
          // 画布（AFFiNE 质感升级——Card 容器 + AnimatedSwitcher 页面转换动画——
          // 圆角/阴影/边框——精致感——不大幅变动——现有 InfiniteCanvasWidget 保留）。
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade300),
                ),
                clipBehavior: Clip.antiAlias,
                // text 工具时点击画布 → 弹出文本输入框（修复打字崩溃——
                // Flutter 原生 TextField——不依赖 material_ui——不崩溃——2026-08-22）。
                child: GestureDetector(
                  onTapUp: state.currentTool == 'text'
                      ? (details) => _showTextInput(details.localPosition)
                      : null,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    switchInCurve: Curves.easeInOut,
                    child: InfiniteCanvasWidget(
                      key: ValueKey(state.document.id),
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: CanvasPainterV2(document: state.document),
                          size: Size.infinite,
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
    );
  }
}
