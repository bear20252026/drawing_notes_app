part of 'editor_page.dart';

// 编辑器输入处理域（O1 拆分）：指针/捏合/缩放/取色方法从
// editor_page.dart 移出为 extension。这些方法只处理输入事件并
// 委托控制器，不直接修改文档；行为零变化。

/// 编辑器输入处理域（拆分自 editor_page.dart）。
extension _EditorPageInput on _EditorPageState {
  void _onPointerDown(PointerDownEvent event, Offset local) {
    final disposition = _inputArbiter.onDown(event, policy: _inputPolicy);
    if (disposition == EditorPointerDisposition.ignore) return;
    _activePointers[event.pointer] = local;

    // 第二个非手掌指针意味着用户明确开始视图手势；取消尚未提交的第一笔，
    // 防止缩放后在笔记中留下短促的误触笔画。
    if (disposition == EditorPointerDisposition.cancelInkForViewportGesture) {
      _controller.cancelActiveStroke();
    }
    if (_inPinch ||
        disposition == EditorPointerDisposition.beginViewportGesture ||
        disposition == EditorPointerDisposition.cancelInkForViewportGesture) {
      _initPinch();
      return;
    }

    final canvasPoint = _controller.viewToCanvas(local);

    // 吸管模式：点击取色，取色后切回画笔。
    if (_eyedropperActive) {
      _pickColor(canvasPoint);
      return;
    }

    // 文字工具模式：点击放置文字。
    if (_textToolActive) {
      _addTextItem(canvasPoint);
      return;
    }

    // 选区模式：独立绘图先命中最上层图片；未命中时保持既有笔画矩形/套索逻辑。
    if (_controller.selectionTool != SelectionTool.none) {
      if (!_isNotebookMode) {
        final shape = _controller.selectDocumentShapeAt(canvasPoint);
        if (shape != null) {
          _viewModel.setSelectionDone(true);
          _lastDragCanvas = canvasPoint;
          return;
        }
        final image = _controller.selectDocumentImageAt(canvasPoint);
        if (image != null) {
          _viewModel.setSelectionDone(true);
          _lastDragCanvas = canvasPoint;
          return;
        }
      }
      if (_selectionDone && _controller.hasSelectedStrokes) {
        _lastDragCanvas = canvasPoint;
      } else {
        _viewModel.setSelectionDone(false);
        _controller.beginSelection(canvasPoint);
      }
      return;
    }

    // 手型工具：记录拖动起点（平移画布）。
    if (_handToolActive) {
      _handDragLast = local;
      return;
    }

    // 形状工具：按下创建草稿，移动决定尺寸；不进入手写笔画。
    if (_activeShapeTool != null) {
      _applyState(() {
        _shapeDraftStart = canvasPoint;
        _shapeDraftCurrent = canvasPoint;
      });
      return;
    }

    // 框选工具：记录框选起点（不进入绘制，借鉴 Excalidraw 多选）。
    if (_marqueeActive) {
      _applyState(() {
        _marqueeStart = canvasPoint;
        _marqueeRect = Rect.fromPoints(canvasPoint, canvasPoint);
        _multiSelectedIds.clear();
      });
      return;
    }

    // 对象橡皮擦不创建伪笔画：命中哪一条就从对象模型中删除哪一条。
    if (_isObjectEraser) {
      _controller.beginObjectErase();
      _controller.eraseStrokesAt(canvasPoint);
      return;
    }

    // 起笔也采集压力；此前固定为 1.0 会让每一笔的笔尖突变为最粗。
    _stylusInput.resetStroke();
    final sample = _stylusInput.process(event);
    _inkPressureSample.value = sample;
    _lastPenPos = canvasPoint;
    _lastPenTime = DateTime.now();
    _controller.startStroke(
      canvasPoint,
      pressure: _controller.tool == BrushType.eraser ? 1.0 : sample.value,
    );
  }

  void _onPointerMove(PointerMoveEvent event, Offset local) {
    // 更新状态栏坐标（所有模式都记录，供状态栏显示）。
    _hoverPos.value = _controller.viewToCanvas(local);
    final disposition = _inputArbiter.onMove(event);
    if (disposition == EditorPointerDisposition.ignore) return;
    final wasPinch = _inPinch;
    _activePointers[event.pointer] = local;

    // 多指手势：缩放/旋转画布。
    if (_inPinch ||
        disposition == EditorPointerDisposition.updateViewportGesture) {
      _updatePinch();
      return;
    }
    // 从多指手势退出到单指：丢弃当前笔画（避免画布旋转后误画一笔）。
    if (wasPinch) return;

    if (_eyedropperActive || _textToolActive) return;
    final canvasPoint = _controller.viewToCanvas(local);

    // 选区模式
    if (_controller.selectionTool != SelectionTool.none) {
      if (!_isNotebookMode &&
          _selectionDone &&
          _controller.selectedDocumentObjectCount > 1) {
        final last = _lastDragCanvas;
        if (last != null) {
          final delta = canvasPoint - last;
          if (delta.distance > 0.001) {
            _controller.moveSelectedDocumentObjects(delta);
            _lastDragCanvas = canvasPoint;
          }
        }
      } else if (_selectionDone && _controller.hasSelectedDocumentShape) {
        final last = _lastDragCanvas;
        if (last != null) {
          final delta = canvasPoint - last;
          if (delta.distance > 0.001) {
            _controller.moveSelectedDocumentImage(delta);
            _lastDragCanvas = canvasPoint;
          }
        }
      } else if (_selectionDone && _controller.hasSelectedStrokes) {
        final last = _lastDragCanvas;
        if (last != null) {
          final delta = canvasPoint - last;
          if (delta.distance > 0.001) {
            _controller.moveSelectedStrokes(delta);
            _lastDragCanvas = canvasPoint;
          }
        }
      } else {
        _controller.extendSelection(canvasPoint);
      }
      return;
    }

    // 手型工具：拖动平移视口（对齐 Excalidraw hand）。
    if (_handToolActive) {
      final last = _handDragLast;
      if (last != null) {
        _controller.viewOffset += local - last;
        _handDragLast = local;
        _controller.tickFrame();
      }
      return;
    }

    // 形状工具：实时更新草稿外接框，提供拖拽创建的即时视觉反馈。
    if (_activeShapeTool != null && _shapeDraftStart != null) {
      _applyState(() => _shapeDraftCurrent = canvasPoint);
      return;
    }

    // 框选工具：更新框选矩形（借鉴 Excalidraw 多选）。
    if (_marqueeActive && _marqueeStart != null) {
      _applyState(() {
        _marqueeRect = Rect.fromPoints(_marqueeStart!, canvasPoint);
      });
      return;
    }

    if (_isObjectEraser) {
      _controller.eraseStrokesAt(canvasPoint);
      return;
    }

    // 无真实压感的鼠标才使用受限速度回退；触控笔范围由处理器正规化。
    double? fallbackPressure;
    final last = _lastPenPos;
    final lastTime = _lastPenTime;
    if (_controller.tool == BrushType.eraser) {
      fallbackPressure = 1.0;
    } else if (last != null && lastTime != null) {
      final dt = DateTime.now().difference(lastTime).inMilliseconds;
      final distance = (canvasPoint - last).distance;
      final speed = dt > 0 ? distance / dt : 0;
      fallbackPressure = (1.0 - speed / 10.0).clamp(0.6, 1.0);
    }
    final sample = _stylusInput.process(
      event,
      fallbackPressure: fallbackPressure,
    );
    _inkPressureSample.value = sample;
    _lastPenPos = canvasPoint;
    _lastPenTime = DateTime.now();
    _controller.extendStroke(
      canvasPoint,
      pressure: _controller.tool == BrushType.eraser ? 1.0 : sample.value,
    );
  }
}
