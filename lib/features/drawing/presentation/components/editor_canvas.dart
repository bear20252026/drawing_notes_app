/// 编辑器画布组件 — 独立 Widget（画布+手势）。
///
/// 从 editor_page.dart 拆分出的核心画布组件。
/// 负责：
/// - 画布渲染（CustomPaint + CanvasPainter）
/// - 手势采集（PointerDown/Move/Up）
/// - 视口初始化与变换
/// - 阅读模式滤镜
///
/// 通过 [EditorState] 读取状态，通过回调向上传递手势事件。
library;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import '../../application/drawing_controller.dart';
import '../canvas_painter.dart';
import '../controllers/editor_state.dart';
import '../editor_components.dart';

/// 编辑器画布组件。
class EditorCanvas extends StatefulWidget {
  const EditorCanvas({
    super.key,
    required this.controller,
    required this.editorState,
    required this.isNotebookMode,
    required this.onPointerDown,
    required this.onPointerMove,
    required this.onPointerUp,
    required this.onPointerCancel,
    required this.onPointerSignal,
    required this.onViewportInit,
    this.gridVisible = false,
    this.shapeDraft,
  });

  /// 绘图控制器。
  final DrawingController controller;

  /// 编辑器状态。
  final EditorState editorState;

  /// 是否为笔记本模式。
  final bool isNotebookMode;

  /// 指针按下回调。
  final void Function(PointerDownEvent event, Offset localPos) onPointerDown;

  /// 指针移动回调。
  final void Function(PointerMoveEvent event, Offset localPos) onPointerMove;

  /// 指针抬起回调。
  final void Function(PointerUpEvent event) onPointerUp;

  /// 指针取消回调。
  final void Function(PointerCancelEvent event) onPointerCancel;

  /// 指针信号回调（滚轮缩放）。
  final void Function(PointerSignalEvent event) onPointerSignal;

  /// 视口初始化回调。
  final void Function(Size size) onViewportInit;

  /// 是否显示网格。
  final bool gridVisible;

  /// 当前形状草稿（可选）。
  final dynamic shapeDraft;

  @override
  State<EditorCanvas> createState() => _EditorCanvasState();
}

class _EditorCanvasState extends State<EditorCanvas> {
  bool _viewportInitialized = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _initViewport(constraints.biggest);
        return Stack(
          children: [
            // 画布层
            Positioned.fill(
              child: Semantics(
                label: '绘图画布',
                hint: '使用工具栏文字工具插入文字；其他工具绘制',
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (e) => widget.onPointerDown(e, e.localPosition),
                  onPointerMove: (e) => widget.onPointerMove(e, e.localPosition),
                  onPointerUp: widget.onPointerUp,
                  onPointerCancel: widget.onPointerCancel,
                  onPointerSignal: widget.onPointerSignal,
                  child: Builder(
                    builder: (context) {
                      final bgColor =
                          Theme.of(context).brightness == Brightness.dark
                              ? Theme.of(context).colorScheme.surface
                              : const Color(0xFFFFFFFF);
                      return _applyReadingFilter(
                        RepaintBoundary(
                          child: CustomPaint(
                            painter: CanvasPainter(
                              controller: widget.controller,
                              backgroundColor: bgColor,
                            ),
                            size: Size.infinite,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            // 网格层
            if (widget.gridVisible)
              Positioned.fill(
                child: IgnorePointer(
                  child: _applyReadingFilter(
                    CustomPaint(
                      painter: GridPainter(controller: widget.controller),
                    ),
                  ),
                ),
              ),
            // 形状草稿层
            if (widget.shapeDraft != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: _applyReadingFilter(
                    CustomPaint(
                      painter: ShapePainter(
                        shape: widget.shapeDraft,
                        viewScale: widget.controller.viewScale,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  void _initViewport(Size viewportSize) {
    if (_viewportInitialized) return;
    _viewportInitialized = true;
    widget.onViewportInit(viewportSize);
  }

  Widget _applyReadingFilter(Widget child) {
    if (!widget.editorState.readingInverted) return child;
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix(<double>[
        -1, 0, 0, 0, 255,
        0, -1, 0, 0, 255,
        0, 0, -1, 0, 255,
        0, 0, 0, 1, 0,
      ]),
      child: child,
    );
  }
}
