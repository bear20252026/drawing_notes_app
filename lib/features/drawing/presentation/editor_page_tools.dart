part of 'editor_page.dart';

// 编辑器工具选择与笔刷域（O1 拆分）：形状工具/手型/框选/笔刷
// 预设方法从 editor_page.dart 移出为 extension；行为零变化。

/// 编辑器工具选择与笔刷域（拆分自 editor_page.dart）。
extension _EditorPageTools on _EditorPageState {
  void _selectShapeTool(ShapeType type) {
    _applyState(() {
      _handToolActive = false;
      _marqueeActive = false;
      _activeShapeTool = type;
      _viewModel.setLinkMode(false);
      _viewModel.setLinkSourceId(null);
      _viewModel.setEyedropperActive(false);
      _viewModel.setTextToolActive(false);
      _controller.selectionTool = SelectionTool.none;
    });
  }

  /// 适应画布（Fit to Screen）：缩放视图显示整个画布（借鉴 Excalidraw 导航）。
  void _fitToScreen() {
    final vp = _viewportSize ?? const Size(800, 600);
    final doc = _controller.document;
    final scale = (vp.width / doc.width).clamp(0.05, 1.0).toDouble();
    _controller.viewScale = scale;
    final center = doc.size.center(Offset.zero);
    final vc = Offset(vp.width / 2, vp.height / 2);
    // 中心对齐：offset = viewCenter - R(scale·(center-center)) - center = viewCenter - center
    _controller.viewOffset = vc - center;
    _controller.tickFrame();
  }

  /// 手型工具切换：激活后画布拖动 = 平移视口（对齐 Excalidraw hand）。
  void _toggleHandTool() {
    _applyState(() {
      _handToolActive = !_handToolActive;
      _marqueeActive = false;
      _activeShapeTool = null;
      _viewModel.setLinkMode(false);
      _viewModel.setLinkSourceId(null);
      _viewModel.setEyedropperActive(false);
      _viewModel.setTextToolActive(false);
      _controller.selectionTool = SelectionTool.none;
      if (!_handToolActive) {
        _handDragLast = null;
      }
    });
  }


  /// 框选工具开关：激活后画布上拖动矩形框选多个混排对象
  /// （借鉴 Excalidraw 多选）。
  void _toggleMarqueeTool() {
    _applyState(() {
      _marqueeActive = !_marqueeActive;
      _handToolActive = false;
      _activeShapeTool = null;
      _viewModel.setLinkMode(false);
      _viewModel.setLinkSourceId(null);
      _viewModel.setEyedropperActive(false);
      _viewModel.setTextToolActive(false);
      _controller.selectionTool = SelectionTool.none;
      if (!_marqueeActive) {
        _marqueeRect = null;
        _marqueeStart = null;
        _multiSelectedIds.clear();
      }
    });
  }

  /// 连线模式的第一个端点元素 id。
  Future<void> _loadBrushPresets() async {
    try {
      final restored = await _brushPresetStore.load();
      if (!mounted) return;
      _applyState(() {
        _brushPresets = restored;
        _applyBrushPreset(_controller.tool);
      });
    } catch (_) {
      // 偏好存储不可用时继续使用内置安全默认值，不阻塞编辑器。
    }
  }

  Future<void> _loadEraserMode() async {
    try {
      final mode = await _eraserModeStore.load();
      if (!mounted) return;
      _applyState(() {
        _controller.eraserMode = mode;
        _lastEraserMode = mode;
      });
    } catch (_) {
      // 偏好不可用时保留安全默认的整笔删除模式。
    }
  }

  void _applyBrushPreset(BrushType tool) {
    final preset = _brushPresets.forTool(tool);
    _controller.tool = tool;
    if (tool == BrushType.eraser) {
      _controller.eraserSize = preset.size;
      // 恢复用户上次选择的橡皮擦模式（整笔/透明），解决"切走再切回模式丢失"。
      _controller.eraserMode = _lastEraserMode;
    } else {
      _controller.color = preset.color;
      _controller.brushSize = preset.size;
    }
  }

  void _selectWritingTool(BrushType tool) {
    _applyState(() {
      _handToolActive = false;
      _activeShapeTool = null;
      _marqueeActive = false;
      _viewModel.setEyedropperActive(false);
      _viewModel.setTextToolActive(false);
      _controller.selectionTool = SelectionTool.none;
      _applyBrushPreset(tool);
    });
  }

  void _updateCurrentBrushPreset({Color? color, double? size}) {
    final tool = _controller.tool;
    final updated = _brushPresets
        .forTool(tool)
        .copyWith(color: color, size: size);
    _applyState(() {
      _brushPresets = _brushPresets.update(updated);
      if (tool == BrushType.eraser) {
        _controller.eraserSize = updated.size;
      } else {
        _controller.color = updated.color;
        _controller.brushSize = updated.size;
      }
    });
    unawaited(_brushPresetStore.save(_brushPresets));
  }
}
