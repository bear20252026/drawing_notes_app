part of 'editor_page.dart';

/// 编辑器工具栏动作装配。
///
/// 此扩展保留页面侧的真实业务委托；纯工厂只负责把下列具名分组透传为
/// [EditorToolbarActions]。因此 Widget 构建、回调映射与状态变更时序分别可审阅。
extension _EditorPageToolbarActions on _EditorPageState {
  /// 执行一次选中文字变更并统一发出持久化/自动保存通知。
  ///
  /// 工具栏与快捷命令都只提供纯字段变更闭包；选中态、setState 和
  /// [_notifyChanged] 仍由组合根拥有，避免在多个动作装配点复制时序。
  void _mutateSelectedText(void Function(PageTextItem item) mutate) {
    final item = _selectedTextItem;
    if (item == null) return;
    _applyState(() => mutate(item));
    _notifyChanged();
  }

  /// 执行一次选中形状变更并统一发出持久化/自动保存通知。
  void _mutateSelectedShape(void Function(PageShapeItem item) mutate) {
    final item = _selectedShapeItem;
    if (item == null) return;
    _applyState(() => mutate(item));
    _notifyChanged();
  }

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
        toggleBold: () => _mutateSelectedText((item) {
          item.bold = !item.bold;
        }),
        toggleItalic: () => _mutateSelectedText((item) {
          item.italic = !item.italic;
        }),
        toggleUnderline: () => _mutateSelectedText((item) {
          item.underline = !item.underline;
        }),
        toggleStrikethrough: () => _mutateSelectedText((item) {
          item.strikethrough = !item.strikethrough;
        }),
        cycleAlign: () => _mutateSelectedText((item) {
          item.align = TextAlignType
              .values[(item.align.index + 1) % TextAlignType.values.length];
        }),
        editText: _editTextItem,
        deleteSelected: _deleteSelectedItem,
      ),
      shape: EditorToolbarShapeActions(
        onSelectShape: _selectShapeTool,
        setShapeFillEnabled: (enabled) =>
            _applyState(() => _fillShapeEnabled = enabled),
        onDistribute: _distributeItems,
        onShapeStrokeWidth: (value) => _mutateSelectedShape((item) {
          item.strokeWidth = value.clamp(1, 20);
        }),
        onShapeOpacity: (value) => _mutateSelectedShape((item) {
          if (value > 0.5) {
            item.fillColor = item.fillColor ?? 0x66A5D6A7;
          } else {
            item.fillColor = null;
          }
        }),
        onShapeFillColor: () => _mutateSelectedShape((item) {
          item.fillColor = item.fillColor == null ? 0x66A5D6A7 : null;
        }),
        onToggleMarquee: _toggleMarqueeTool,
        onReorder: _reorderSelected,
        onToggleDash: () => _mutateSelectedShape((item) {
          item.dash = !item.dash;
        }),
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
