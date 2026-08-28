part of 'editor_page.dart';

// 编辑器主体布局域（O1 拆分）：从 editor_page.dart 移出为 extension，
// 仅负责组装"左侧工具条 + 画布/选择 + 条件面板"；用 `_applyState` 封装
// 受保护的 setState，行为零变化。

/// 编辑器主体布局（拆分自 editor_page.dart）。
extension _EditorPageBody on _EditorPageState {
  /// 主体：非全屏 = 左工具条 + (上下文条 + 选择/画布) + 条件面板。
  Widget _buildBody() {
    return _fullscreen
        // 全屏模式：只保留画布区域。
        ? _buildCanvasArea()
        : Row(
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
                onEyedropper: () => _applyState(() {
                  _toolMode.clearPointerModes();
                  _controller.selectionTool = SelectionTool.none;
                  _viewModel.setEyedropperActive(true);
                  _viewModel.setTextToolActive(false);
                }),
                onRectSelect: () => _applyState(() {
                  _toolMode.clearPointerModes();
                  _viewModel.setEyedropperActive(false);
                  _viewModel.setTextToolActive(false);
                  _viewModel.setSelectionDone(false);
                  _controller.selectionTool = SelectionTool.rect;
                }),
                onMarquee: _toggleMarqueeTool,
                onText: () => _applyState(() {
                  _toolMode.clearPointerModes();
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
                    SelectionBar(
                      controller: _controller,
                      isNotebookMode: _isNotebookMode,
                      scaleValue: _scaleValue,
                      rotateDegrees: _rotateDegrees,
                      onScaleChanged: (v) {
                        _applyState(() {
                          final factor = _selectionTransform.updateScale(v);
                          final c = _controller;
                          if (_isNotebookMode &&
                              c.hasMixedDocumentObjectSelection) {
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
                          final delta =
                              _selectionTransform.updateRotationDegrees(v);
                          _controller.rotateSelectedStrokes(delta);
                        });
                      },
                      onClearSelection: () => _applyState(() {
                        _viewModel.setSelectionDone(false);
                        _controller.clearDocumentObjectSelection();
                      }),
                      onTransformEnd: () {
                        final c = _controller;
                        if (_isNotebookMode &&
                            c.hasMixedDocumentObjectSelection) {
                          c.endDocumentObjectsTransform();
                        } else if (c.hasSelectedDocumentShape) {
                          c.endDocumentShapeTransform();
                        } else if (c.hasSelectedDocumentImage) {
                          c.endDocumentImageTransform();
                        }
                        _notifyChanged();
                      },
                    ),
                    Expanded(child: _buildCanvasArea()),
                  ],
                ),
              ),
              // 图层与详细属性仅在用户需要时展开，画布默认保持居中和宽阔。
              if (_layersVisible) LayerPanel(controller: _controller),
              if (_inspectorVisible)
                PropertiesPanel(
                  controller: _controller,
                  selectedShape: _selectedShapeItem,
                  selectedText: _selectedTextItem,
                  selectedImage: _selectedImageItem,
                  onPickColor: _showColorPicker,
                  onBrushSizeChanged: (v) =>
                      _updateCurrentBrushPreset(size: v),
                  onShapeStrokeWidth: (v) {
                    final s = _selectedShapeItem;
                    if (s == null) return;
                    _applyState(() => s.strokeWidth = v.clamp(1, 20));
                    _notifyChanged();
                  },
                  onShapeOpacity: (v) {
                    final s = _selectedShapeItem;
                    if (s == null) return;
                    _applyState(() {
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
                    _applyState(() {
                      s.fillColor =
                          s.fillColor == null ? 0x66A5D6A7 : null;
                    });
                    _notifyChanged();
                  },
                  onShapeDash: () {
                    final s = _selectedShapeItem;
                    if (s == null) return;
                    _applyState(() => s.dash = !s.dash);
                    _notifyChanged();
                  },
                  onShapeRough: () {
                    final s = _selectedShapeItem;
                    if (s == null) return;
                    _applyState(() => s.rough = !s.rough);
                    _notifyChanged();
                  },
                  onTextColor: _changeSelectedTextColor,
                  onTextFontSize: _setSelectedTextFontSize,
                  onCropImage: () {
                    // 已在裁剪模式：确认裁剪；否则进入裁剪模式。
                    if (_cropItem != null) {
                      _confirmCrop();
                      return;
                    }
                    final img = _selectedImageItem;
                    if (img == null) return;
                    _applyState(() => _canvasInteraction.beginCrop(img));
                    _showSnack('拖动图片四角调整裁剪区域，再点裁剪按钮确认');
                  },
                  onCycleFont: () {
                    final t = _selectedTextItem;
                    if (t == null) return;
                    _applyState(() {
                      t.fontFamily = switch (t.fontFamily) {
                        null => 'serif',
                        'serif' => 'monospace',
                        'monospace' => 'handwriting',
                        _ => null,
                      };
                    });
                    _notifyChanged();
                  },
                ),
            ],
          );
  }
}
