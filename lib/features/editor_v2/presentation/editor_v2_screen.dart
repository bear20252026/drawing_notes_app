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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(editorV2NotifierProvider);

    return Scaffold(
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
          // 工具栏
          EditorV2Toolbar(
            currentTool: state.currentTool,
            currentShapeType: state.currentShapeType,
            onToolChanged: (tool) =>
                ref.read(editorV2NotifierProvider.notifier).setTool(tool),
            onShapeTypeChanged: (type) =>
                ref.read(editorV2NotifierProvider.notifier).setShapeType(type),
          ),
          // 画布（CustomPainter + RepaintBoundary——直接绘画）
          Expanded(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: CanvasPainterV2(document: state.document),
                size: Size.infinite,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
