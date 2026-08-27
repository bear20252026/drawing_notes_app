part of 'editor_page.dart';

/// 编辑器工具栏动作装配。
///
/// 此扩展保留页面侧的真实业务委托；纯工厂只负责把下列具名分组透传为
/// [EditorToolbarActions]。因此 Widget 构建、回调映射与状态变更时序分别可审阅。
extension _EditorPageToolbarActions on _EditorPageState {
  EditorToolbarActions _buildToolbarActions() {
    return EditorToolbarActionFactory.build(
      brush: EditorToolbarBrushActions(
        selectBrush: () => _selectWritingTool(BrushType.pen),
        selectEraser: () => _selectWritingTool(BrushType.eraser),
        setPixelEraserMode: (pixel) {
          final mode = pixel ? EraserMode.pixel : EraserMode.stroke;
          _applyState(() => _controller.eraserMode = mode);
          unawaited(_eraserModeStore.save(mode));
        },
        setEraserCanEraseShapesStroke: (value) =>
            _applyState(() => _controller.eraserCanEraseShapesStroke = value),
        setEraserCanEraseShapesPixel: (value) =>
            _applyState(() => _controller.eraserCanEraseShapesPixel = value),
        setTemporaryMarkerEnabled: (enabled) =>
            _applyState(() => _controller.temporaryMarkerEnabled = enabled),
        showColorPicker: _showColorPicker,
        onSizeChanged: (value) => _updateCurrentBrushPreset(size: value),
        onBrushSelected: (id) {
          if (id == 'pen') _selectWritingTool(BrushType.pen);
        },
      ),
      object: EditorToolbarObjectActions(
        selectEyedropper: () => _applyState(() {
          _viewModel.setEyedropperActive(true);
          _viewModel.setTextToolActive(false);
        }),
        selectRect: () => _applyState(() {
          _viewModel.setEyedropperActive(false);
          _viewModel.setTextToolActive(false);
          _viewModel.setSelectionDone(false);
          _controller.selectionTool = SelectionTool.rect;
        }),
        selectLasso: () => _applyState(() {
          _viewModel.setEyedropperActive(false);
          _viewModel.setTextToolActive(false);
          _viewModel.setSelectionDone(false);
          _controller.selectionTool = SelectionTool.lasso;
        }),
        selectText: () => _applyState(() {
          _viewModel.setTextToolActive(true);
          _viewModel.setEyedropperActive(false);
          _controller.selectionTool = SelectionTool.none;
        }),
        recolorAllText: _macroRecolorAllText,
        toggleLink: _toggleLinkMode,
        showPagination: _showPaginationPreview,
        addStickyNote: _addStickyNote,
        cyclePaper: () => _applyState(() {
          final next =
              PaperType.values[(_controller.document.paperType.index + 1) %
                  PaperType.values.length];
          _controller.document.paperType = next;
          _controller.tickFrame();
          _notifyChanged();
        }),
        insertImage: _insertImage,
        onSelectedFontSize: _setSelectedTextFontSize,
        changeTextColor: _changeSelectedTextColor,
        toggleBold: () => _applyState(() {
          final selected = _selectedTextItem;
          if (selected == null) return;
          selected.bold = !selected.bold;
          _notifyChanged();
        }),
        toggleItalic: () => _applyState(() {
          final selected = _selectedTextItem;
          if (selected == null) return;
          selected.italic = !selected.italic;
          _notifyChanged();
        }),
        toggleUnderline: () => _applyState(() {
          final selected = _selectedTextItem;
          if (selected == null) return;
          selected.underline = !selected.underline;
          _notifyChanged();
        }),
        toggleStrikethrough: () => _applyState(() {
          final selected = _selectedTextItem;
          if (selected == null) return;
          selected.strikethrough = !selected.strikethrough;
          _notifyChanged();
        }),
        cycleAlign: () => _applyState(() {
          final selected = _selectedTextItem;
          if (selected == null) return;
          final next = TextAlignType
              .values[(selected.align.index + 1) % TextAlignType.values.length];
          selected.align = next;
          _notifyChanged();
        }),
        editText: _editTextItem,
        deleteSelected: _deleteSelectedItem,
      ),
      shape: EditorToolbarShapeActions(
        onSelectShape: _selectShapeTool,
        setShapeFillEnabled: (enabled) =>
            _applyState(() => _fillShapeEnabled = enabled),
        onDistribute: _distributeItems,
        onShapeStrokeWidth: (value) {
          final selected = _selectedShapeItem;
          if (selected == null) return;
          _applyState(() => selected.strokeWidth = value.clamp(1, 20));
          _notifyChanged();
        },
        onShapeOpacity: (value) {
          final selected = _selectedShapeItem;
          if (selected == null) return;
          _applyState(() {
            if (value > 0.5) {
              selected.fillColor = selected.fillColor ?? 0x66A5D6A7;
            } else {
              selected.fillColor = null;
            }
          });
          _notifyChanged();
        },
        onShapeFillColor: () {
          final selected = _selectedShapeItem;
          if (selected == null) return;
          _applyState(() {
            selected.fillColor = selected.fillColor == null ? 0x66A5D6A7 : null;
          });
          _notifyChanged();
        },
        onToggleMarquee: _toggleMarqueeTool,
        onReorder: _reorderSelected,
        onToggleDash: () {
          final selected = _selectedShapeItem;
          if (selected == null) return;
          _applyState(() => selected.dash = !selected.dash);
          _notifyChanged();
        },
      ),
      viewport: EditorToolbarViewportActions(
        onToggleGrid: () => _applyState(() => _gridVisible = !_gridVisible),
        onToggleSnap: () => _applyState(() => _snapToGrid = !_snapToGrid),
        onFitToScreen: _fitToScreen,
        onZoomIn: _zoomIn,
        onZoomOut: _zoomOut,
        onZoomReset: _zoomReset,
      ),
    );
  }
}
