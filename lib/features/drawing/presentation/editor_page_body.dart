part of 'editor_page.dart';

/// 画布主体区域构建域（拆分自 editor_page.dart build 方法）。
extension _EditorPageBody on _EditorPageState {
  /// 非全屏模式主体：左侧工具栏 + 中央画布 + 右侧属性面板。
  ///
  /// 横竖屏适配：竖屏时左侧工具栏移至顶部水平排列，节省纵向空间。
  Widget _buildBody(BuildContext context) {
    return OrientationBuilder(
      builder: (context, orientation) {
        if (orientation == Orientation.portrait) {
          return _buildPortraitBody(context);
        }
        return _buildLandscapeBody(context);
      },
    );
  }

  /// 竖屏布局：顶部工具栏 + 中央画布。
  Widget _buildPortraitBody(BuildContext context) {
    return Column(
      children: [
        _buildContextBar(),
        _buildSelectionBar(),
        Expanded(child: _buildCanvasArea()),
      ],
    );
  }

  /// 横屏布局：左侧工具栏 + 中央画布 + 右侧属性面板。
  Widget _buildLandscapeBody(BuildContext context) {
    return Row(
      children: [
        // 左侧垂直工具条（对齐 Excalidraw LayerUI 布局）。
        EditorLeftToolbar(
          controller: _controller,
          eyedropperActive: _eyedropperActive,
          textToolActive: _textToolActive,
          marqueeActive: _marqueeActive,
          linkMode: _linkMode,
          handActive: _handToolActive,
          onHand: _toggleHandTool,
          activeShape: _activeShapeTool,
          onBrush: () => _selectWritingTool(BrushType.pen),
          onPencil: () => _selectWritingTool(BrushType.pencil),
          onHighlighter: () => _selectWritingTool(BrushType.marker),
          onLaser: () => _selectWritingTool(BrushType.laser),
          onEraser: () => _selectWritingTool(BrushType.eraser),
          onEyedropper: () => setState(() {
            _handToolActive = false;
            _activeShapeTool = null;
            _marqueeActive = false;
            _controller.selectionTool = SelectionTool.none;
            _viewModel.setEyedropperActive(true);
            _viewModel.setTextToolActive(false);
          }),
          onRectSelect: () => setState(() {
            _handToolActive = false;
            _activeShapeTool = null;
            _marqueeActive = false;
            _viewModel.setEyedropperActive(false);
            _viewModel.setTextToolActive(false);
            _viewModel.setSelectionDone(false);
            _controller.selectionTool = SelectionTool.rect;
          }),
          onMarquee: _toggleMarqueeTool,
          onText: () => setState(() {
            _handToolActive = false;
            _activeShapeTool = null;
            _marqueeActive = false;
            _controller.selectionTool = SelectionTool.none;
            _viewModel.setEyedropperActive(false);
            _viewModel.setTextToolActive(true);
          }),
          onShape: _selectShapeTool,
          onLink: _toggleLinkMode,
        ),
        Expanded(
          child: Column(
            children: [
              _buildContextBar(),
              _buildSelectionBar(),
              Expanded(child: _buildCanvasArea()),
            ],
          ),
        ),
        // 图层与详细属性仅在用户需要时展开。
        if (_layersVisible) LayerPanel(controller: _controller),
        if (_inspectorVisible) _buildPropertiesPanel(),
      ],
    );
  }

  /// 选区操作栏。
  Widget _buildSelectionBar() {
    return SelectionBar(
      controller: _controller,
      isNotebookMode: _isNotebookMode,
      scaleValue: _scaleValue,
      rotateDegrees: _rotateDegrees,
      onScaleChanged: (v) {
        _applyState(() {
          final factor = v / _scaleValue;
          _scaleValue = v;
          final c = _controller;
          if (_isNotebookMode && c.hasMixedDocumentObjectSelection) {
            c.scaleSelectedDocumentObjects(factor);
          } else if (c.hasSelectedDocumentShape) {
            c.scaleSelectedDocumentShape(factor);
          } else if (c.hasSelectedDocumentImage) {
            c.scaleSelectedDocumentImage(factor);
          } else {
            c.scaleSelectedStrokes(factor);
          }
        });
      },
      onRotateChanged: (v) {
        _applyState(() {
          final delta = (v - _rotateDegrees) * 3.14159265 / 180;
          _rotateDegrees = v;
          _controller.rotateSelectedStrokes(delta);
        });
      },
      onClearSelection: () => _applyState(() {
        _viewModel.setSelectionDone(false);
        _controller.clearDocumentObjectSelection();
      }),
      onTransformEnd: () {
        final c = _controller;
        if (_isNotebookMode && c.hasMixedDocumentObjectSelection) {
          c.endDocumentObjectsTransform();
        } else if (c.hasSelectedDocumentShape) {
          c.endDocumentShapeTransform();
        } else if (c.hasSelectedDocumentImage) {
          c.endDocumentImageTransform();
        }
        _notifyChanged();
      },
    );
  }

  /// 属性面板。
  Widget _buildPropertiesPanel() {
    return PropertiesPanel(
      controller: _controller,
      selectedShape: _selectedShapeItem,
      selectedText: _selectedTextItem,
      selectedImage: _selectedImageItem,
      onPickColor: _showColorPicker,
      onBrushSizeChanged: (v) => _updateCurrentBrushPreset(size: v),
      onShapeStrokeWidth: (v) {
        final s = _selectedShapeItem;
        if (s == null) return;
        setState(() => s.strokeWidth = v.clamp(1, 20));
        _notifyChanged();
      },
      onShapeOpacity: (v) {
        final s = _selectedShapeItem;
        if (s == null) return;
        setState(() {
          if (v > 0.5) {
            s.fillColor = s.fillColor ?? 0x66A5D6A7;
          } else {
            s.fillColor = null;
          }
        });
        _notifyChanged();
      },
      onShapeFill: () {
        final s = _selectedShapeItem;
        if (s == null) return;
        setState(() {
          s.fillColor = s.fillColor == null ? 0x66A5D6A7 : null;
        });
        _notifyChanged();
      },
      onShapeDash: () {
        final s = _selectedShapeItem;
        if (s == null) return;
        setState(() => s.dash = !s.dash);
        _notifyChanged();
      },
      onShapeRough: () {
        final s = _selectedShapeItem;
        if (s == null) return;
        setState(() => s.rough = !s.rough);
        _notifyChanged();
      },
      onTextColor: _changeSelectedTextColor,
      onTextFontSize: _setSelectedTextFontSize,
      onCropImage: () {
        if (_cropItem != null) {
          _confirmCrop();
          return;
        }
        final img = _selectedImageItem;
        if (img == null) return;
        setState(() {
          _cropItem = img;
          _cropRect = Rect.fromLTWH(img.x, img.y, img.width, img.height);
        });
        _showSnack('拖动图片四角调整裁剪区域，再点裁剪按钮确认');
      },
      onCycleFont: () {
        final t = _selectedTextItem;
        if (t == null) return;
        setState(() {
          t.fontFamily = switch (t.fontFamily) {
            null => 'serif',
            'serif' => 'monospace',
            'monospace' => 'handwriting',
            _ => null,
          };
        });
        _notifyChanged();
      },
    );
  }
}
