part of 'editor_page.dart';

// 编辑器交互/手柄/选区域（O1 拆分）：上下文栏、分组/拖拽/对齐/
// 分布、缩放手柄、选区栏方法从 editor_page_overlays.dart 移出为
// 独立 extension（同库 extension 可经 this. 访问私有成员）；行为零变化。

/// 编辑器交互/手柄/选区域（拆分自 editor_page_overlays.dart）。
extension _EditorPageDragOps on _EditorPageState {
  Widget _buildContextBar() {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        return EditorContextBar(
          state: mapEditorToolbarState(
            _controller,
            ToolbarUiFlags(
              isNotebookMode: _isNotebookMode,
              eyedropperActive: _eyedropperActive,
              textToolActive: _textToolActive,
              linkMode: _linkMode,
              selectedItemId: _selectedItemId,
              selectedTextItem: _selectedTextItem,
              activeShape: _activeShapeTool,
              selectedShape: _selectedShapeItem,
              shapeFillEnabled: _fillShapeEnabled,
              marqueeActive: _marqueeActive,
              gridVisible: _gridVisible,
              snapToGrid: _snapToGrid,
            ),
          ),
          actions: EditorToolbarActions(
            onToggleGrid: () => _applyState(() => _gridVisible = !_gridVisible),
            onToggleSnap: () => _applyState(() => _snapToGrid = !_snapToGrid),
            onFitToScreen: _fitToScreen,
            onZoomIn: _zoomIn,
            onZoomOut: _zoomOut,
            onZoomReset: _zoomReset,
            onToggleDash: () {
              final s = _selectedShapeItem;
              if (s == null) return;
              _applyState(() => s.dash = !s.dash);
              _notifyChanged();
            },
            onToggleMarquee: _toggleMarqueeTool,
            onReorder: _reorderSelected,
            onSelectShape: _selectShapeTool,
            setShapeFillEnabled: (enabled) =>
                _applyState(() => _fillShapeEnabled = enabled),
            onDistribute: _distributeItems,
            onShapeStrokeWidth: (v) {
              final s = _selectedShapeItem;
              if (s == null) return;
              _applyState(() => s.strokeWidth = v.clamp(1, 20));
              _notifyChanged();
            },
            onShapeOpacity: (v) {
              final s = _selectedShapeItem;
              if (s == null) return;
              // 透明度滑块：>0 时启用填充色，=0 时清除填充。
              _applyState(() {
                if (v > 0.5) {
                  s.fillColor = s.fillColor ?? 0x66A5D6A7;
                } else {
                  s.fillColor = null;
                }
              });
              _notifyChanged();
            },
            onShapeFillColor: () {
              final s = _selectedShapeItem;
              if (s == null) return;
              _applyState(() {
                s.fillColor = s.fillColor == null ? 0x66A5D6A7 : null;
              });
              _notifyChanged();
            },
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
            showColorPicker: _showColorPicker,
            onSizeChanged: (v) => _updateCurrentBrushPreset(size: v),
            onSelectedFontSize: _setSelectedTextFontSize,
            changeTextColor: _changeSelectedTextColor,
            toggleBold: () => _applyState(() {
              final s = _selectedTextItem;
              if (s == null) return;
              s.bold = !s.bold;
              _notifyChanged();
            }),
            toggleItalic: () => _applyState(() {
              final s = _selectedTextItem;
              if (s == null) return;
              s.italic = !s.italic;
              _notifyChanged();
            }),
            toggleUnderline: () => _applyState(() {
              final s = _selectedTextItem;
              if (s == null) return;
              s.underline = !s.underline;
              _notifyChanged();
            }),
            toggleStrikethrough: () => _applyState(() {
              final s = _selectedTextItem;
              if (s == null) return;
              s.strikethrough = !s.strikethrough;
              _notifyChanged();
            }),
            cycleAlign: () => _applyState(() {
              final s = _selectedTextItem;
              if (s == null) return;
              final next =
                  TextAlignType.values[(s.align.index + 1) %
                      TextAlignType.values.length];
              s.align = next;
              _notifyChanged();
            }),
            editText: _editTextItem,
            deleteSelected: _deleteSelectedItem,
            onBrushSelected: (id) {
              if (id == 'pen') _selectWritingTool(BrushType.pen);
            },
          ),
        );
      },
    );
  }
  Set<String> _expandGroup(Set<String> ids) {
    final page = widget.page;
    if (page == null || ids.isEmpty) return ids;
    // 收集 ids 涉及的所有 groupId。
    final groups = <String>{};
    for (final t in page.textItems) {
      if (ids.contains(t.id) && t.groupId != null) groups.add(t.groupId!);
    }
    for (final i in page.imageItems) {
      if (ids.contains(i.id) && i.groupId != null) groups.add(i.groupId!);
    }
    for (final sh in page.shapes) {
      if (ids.contains(sh.id) && sh.groupId != null) groups.add(sh.groupId!);
    }
    if (groups.isEmpty) return ids;
    // 展开：把同组元素全部加入。
    final result = {...ids};
    for (final t in page.textItems) {
      if (t.groupId != null && groups.contains(t.groupId)) result.add(t.id);
    }
    for (final i in page.imageItems) {
      if (i.groupId != null && groups.contains(i.groupId)) result.add(i.id);
    }
    for (final sh in page.shapes) {
      if (sh.groupId != null && groups.contains(sh.groupId)) result.add(sh.id);
    }
    return result;
  }

  void _dragItem(String id, Offset screenDelta) {
    final page = widget.page;
    if (page == null) return;
    // 屏幕位移 -> 画布位移（除以缩放、反向旋转）。
    final canvasDelta = screenDeltaToCanvas(screenDelta, _controller.viewRotation, _controller.viewScale);
    // 动画尾迹（借鉴 Excalidraw animatedTrail）：记录最近拖动点。
    _trailPoints.add(canvasDelta);
    if (_trailPoints.length > 8) {
      _trailPoints.removeAt(0);
    }
    // 多选：拖动任一选中元素时整体移动所有选中元素（借鉴 Excalidraw 多选）。
    final moveIds = _expandGroup(
      _multiSelectedIds.isNotEmpty ? {..._multiSelectedIds, id} : <String>{id},
    );
    _applyState(() {
      const grid = 20.0;
      double snap(double v) => _snapToGrid ? (v / grid).round() * grid : v;
      for (final t in page.textItems) {
        if (moveIds.contains(t.id)) {
          t.x = snap(
            t.x + canvasDelta.dx,
          ).clamp(0, _controller.document.width.toDouble());
          t.y = snap(
            t.y + canvasDelta.dy,
          ).clamp(0, _controller.document.height.toDouble());
        }
      }
      for (final i in page.imageItems) {
        if (moveIds.contains(i.id)) {
          i.x = (i.x + canvasDelta.dx).clamp(
            0,
            _controller.document.width.toDouble(),
          );
          i.y = (i.y + canvasDelta.dy).clamp(
            0,
            _controller.document.height.toDouble(),
          );
        }
      }
      // 形状元素（借鉴 Excalidraw 图形工具）：拖动移动位置。
      for (final s in page.shapes) {
        if (moveIds.contains(s.id)) {
          s.x = (s.x + canvasDelta.dx).clamp(
            0,
            _controller.document.width.toDouble(),
          );
          s.y = (s.y + canvasDelta.dy).clamp(
            0,
            _controller.document.height.toDouble(),
          );
        }
      }
      // 箭头绑定（借鉴 Excalidraw boundElements）：目标元素移动时，
      // 绑定到该元素的箭头同步跟随（引用关联而非坐标快照）。
      for (final targetId in moveIds) {
        for (final s in page.shapes) {
          if (s.boundElementId == targetId) {
            s.x = (s.x + canvasDelta.dx).clamp(
              0,
              _controller.document.width.toDouble(),
            );
            s.y = (s.y + canvasDelta.dy).clamp(
              0,
              _controller.document.height.toDouble(),
            );
          }
        }
      }
      // 对齐吸附（借鉴 Excalidraw 对齐参考线）：拖动结束后吸附到
      // 其他混排对象的左/中/右 或 上/中/下 边（容差 10px）。
      _snapDragItemToAlign(id);
    });
  }

  /// 拖动后对齐吸附：把 [id] 元素吸附到其他元素的边/中心对齐线。
  ///
  /// 容差 [snapTol]（画布坐标）；仅当拖动对象与任一参考线足够近时吸附，
  /// 视觉上形成"对齐参考线"的体验（借鉴 Excalidraw）。
  void _snapDragItemToAlign(String id) {
    // 画布模式的对象拖动由 controller 统一管理（不走 _dragItem），
    // 因此对齐吸附仅作用于分页笔记的混排对象；无限画布吸附属于
    // controller 层后续工程（记录于审查报告）。
    final page = widget.page;
    if (page == null) return;
    const snapTol = 10.0;
    final textItems = page.textItems;
    final imageItems = page.imageItems;
    final shapes = page.shapes;

    // 收集所有混排对象的边界（左/右/上/下/水平中心/垂直中心）。
    final refs =
        <({double l, double r, double t, double b, double cx, double cy})>[];
    for (final t in textItems) {
      if (t.id == id) continue;
      final w = t.fontSize * 2.0;
      refs.add((
        l: t.x,
        r: t.x + w,
        t: t.y,
        b: t.y + t.fontSize,
        cx: t.x + w / 2,
        cy: t.y + t.fontSize / 2,
      ));
    }
    for (final i in imageItems) {
      if (i.id == id) continue;
      refs.add((
        l: i.x,
        r: i.x + i.width,
        t: i.y,
        b: i.y + i.height,
        cx: i.x + i.width / 2,
        cy: i.y + i.height / 2,
      ));
    }
    for (final s in shapes) {
      if (s.id == id) continue;
      refs.add((
        l: s.x,
        r: s.x + s.width,
        t: s.y,
        b: s.y + s.height,
        cx: s.x + s.width / 2,
        cy: s.y + s.height / 2,
      ));
    }
    if (refs.isEmpty) return;

    // 当前拖动元素边界。
    double l = 0, r = 0, top = 0, bottom = 0;
    for (final t in textItems) {
      if (t.id == id) {
        l = t.x;
        r = t.x + t.fontSize * 2;
        top = t.y;
        bottom = t.y + t.fontSize;
      }
    }
    for (final i in imageItems) {
      if (i.id == id) {
        l = i.x;
        r = i.x + i.width;
        top = i.y;
        bottom = i.y + i.height;
      }
    }
    for (final s in shapes) {
      if (s.id == id) {
        l = s.x;
        r = s.x + s.width;
        top = s.y;
        bottom = s.y + s.height;
      }
    }
    final cx = (l + r) / 2;
    final cy = (top + bottom) / 2;

    // 水平对齐（X 轴）：左/中/右。
    var dx = 0.0;
    var bestDx = snapTol;
    void snapX(double target) {
      final d = target - l;
      if (d.abs() < bestDx) {
        bestDx = d.abs();
        dx = d;
      }
    }

    void snapCx(double target) {
      final d = target - cx;
      if (d.abs() < bestDx) {
        bestDx = d.abs();
        dx = d;
      }
    }

    for (final ref in refs) {
      snapX(ref.l);
      snapX(ref.r);
      snapCx(ref.cx);
    }
    // 垂直对齐（Y 轴）：上/中/下。
    var dy = 0.0;
    var bestDy = snapTol;
    void snapY(double target) {
      final d = target - top;
      if (d.abs() < bestDy) {
        bestDy = d.abs();
        dy = d;
      }
    }

    void snapCy(double target) {
      final d = target - cy;
      if (d.abs() < bestDy) {
        bestDy = d.abs();
        dy = d;
      }
    }

    for (final ref in refs) {
      snapY(ref.t);
      snapY(ref.b);
      snapCy(ref.cy);
    }

    if (dx != 0 || dy != 0) {
      // 记录对齐参考线（实时显示，借鉴 Excalidraw 对齐可视化）。
      final guides = <({bool vertical, double pos})>[];
      if (dx != 0) guides.add((vertical: true, pos: l + dx));
      if (dy != 0) guides.add((vertical: false, pos: top + dy));
      _snapGuides = guides;
      for (final t in textItems) {
        if (t.id == id) {
          t.x += dx;
          t.y += dy;
        }
      }
      for (final i in imageItems) {
        if (i.id == id) {
          i.x += dx;
          i.y += dy;
        }
      }
      for (final s in shapes) {
        if (s.id == id) {
          s.x += dx;
          s.y += dy;
        }
      }
    } else {
      _snapGuides = const [];
    }
  }

  /// 等间距分布：把页面全部混排对象（文字/图片/形状）按水平或垂直
  /// 等间距排列（借鉴 Excalidraw 对齐/分布工具）。
  void _distributeItems(bool horizontal) {
    final page = widget.page;
    if (page == null) return;
    final items = <({double pos, double size})>[];
    // 收集所有对象的中心位置与尺寸。
    for (final t in page.textItems) {
      items.add((pos: t.x + t.fontSize, size: t.fontSize * 2));
    }
    for (final i in page.imageItems) {
      items.add((pos: i.x + i.width / 2, size: i.width));
    }
    for (final s in page.shapes) {
      items.add((pos: s.x + s.width / 2, size: s.width));
    }
    if (items.length < 3) {
      _showSnack('至少需要 3 个元素才能分布');
      return;
    }
    // 水平分布：按中心 X 排序，重排到首尾之间等间距。
    if (horizontal) {
      items.sort((a, b) => a.pos.compareTo(b.pos));
      final first = items.first.pos;
      final last = items.last.pos;
      final step = (last - first) / (items.length - 1);
      var idx = 0;
      for (final t in page.textItems) {
        final target = first + step * (idx++);
        t.x = target - t.fontSize;
      }
      for (final i in page.imageItems) {
        final target = first + step * (idx++);
        i.x = target - i.width / 2;
      }
      for (final s in page.shapes) {
        final target = first + step * (idx++);
        s.x = target - s.width / 2;
      }
    } else {
      // 垂直分布：按中心 Y 排序。
      final vItems = <({double pos, double size})>[];
      for (final t in page.textItems) {
        vItems.add((pos: t.y + t.fontSize / 2, size: t.fontSize));
      }
      for (final i in page.imageItems) {
        vItems.add((pos: i.y + i.height / 2, size: i.height));
      }
      for (final s in page.shapes) {
        vItems.add((pos: s.y + s.height / 2, size: s.height));
      }
      vItems.sort((a, b) => a.pos.compareTo(b.pos));
      final first = vItems.first.pos;
      final last = vItems.last.pos;
      final step = (last - first) / (vItems.length - 1);
      var idx = 0;
      for (final t in page.textItems) {
        final target = first + step * (idx++);
        t.y = target - t.fontSize / 2;
      }
      for (final i in page.imageItems) {
        final target = first + step * (idx++);
        i.y = target - i.height / 2;
      }
      for (final s in page.shapes) {
        final target = first + step * (idx++);
        s.y = target - s.height / 2;
      }
    }
    _applyState(() {});
    _notifyChanged();
    _showSnack(horizontal ? '已水平等间距分布' : '已垂直等间距分布');
  }

  /// 图片裁剪 4 角手柄（拖拽调整 _cropRect，画布坐标）。
  List<Widget> _buildCropHandles(PageImageItem _) {
    final rect = _cropRect!;
    final corners = [
      rect.topLeft,
      rect.topRight,
      rect.bottomLeft,
      rect.bottomRight,
    ];
    return [
      for (final c in corners)
        Positioned(
          left: _controller.canvasToView(c).dx - 5,
          top: _controller.canvasToView(c).dy - 5,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (d) {
              final delta = screenDeltaToCanvas(d.delta, _controller.viewRotation, _controller.viewScale);
              _applyState(() {
                // 按角位置调整 _cropRect 的对应边（限制在图片区域内）。
                final img = _cropItem!;
                if (c == rect.topLeft) {
                  _cropRect = Rect.fromLTRB(
                    (rect.left + delta.dx).clamp(img.x, rect.right - 10),
                    (rect.top + delta.dy).clamp(img.y, rect.bottom - 10),
                    rect.right,
                    rect.bottom,
                  );
                } else if (c == rect.topRight) {
                  _cropRect = Rect.fromLTRB(
                    rect.left,
                    (rect.top + delta.dy).clamp(img.y, rect.bottom - 10),
                    (rect.right + delta.dx).clamp(
                      rect.left + 10,
                      img.x + img.width,
                    ),
                    rect.bottom,
                  );
                } else if (c == rect.bottomLeft) {
                  _cropRect = Rect.fromLTRB(
                    (rect.left + delta.dx).clamp(img.x, rect.right - 10),
                    rect.top,
                    rect.right,
                    (rect.bottom + delta.dy).clamp(
                      rect.top + 10,
                      img.y + img.height,
                    ),
                  );
                } else {
                  _cropRect = Rect.fromLTRB(
                    rect.left,
                    rect.top,
                    (rect.right + delta.dx).clamp(
                      rect.left + 10,
                      img.x + img.width,
                    ),
                    (rect.bottom + delta.dy).clamp(
                      rect.top + 10,
                      img.y + img.height,
                    ),
                  );
                }
              });
            },
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: const Color(0xFF42A5F5),
                borderRadius: BorderRadius.circular(2),
                border: Border.all(color: Colors.white, width: 1),
              ),
            ),
          ),
        ),
    ];
  }

  /// 返回 [canvasPoint] 附近（50px 内）吸附命中的混排对象 id。
  ///
  /// 与 [_findSnapTarget] 同逻辑但返回元素 id（供箭头绑定 boundElementId 使用）；
  /// 无命中返回 null。
  String? _findSnapTargetId(Offset canvasPoint) {
    final page = widget.page;
    if (page == null) return null;
    const snapDist = 50.0;
    String? best;
    var bestDist = snapDist;
    void consider(String id, Offset center) {
      final d = (center - canvasPoint).distance;
      if (d < bestDist) {
        bestDist = d;
        best = id;
      }
    }

    for (final t in page.textItems) {
      consider(t.id, t.position + Offset(t.fontSize * 2, t.fontSize / 2));
    }
    for (final i in page.imageItems) {
      consider(i.id, i.position + Offset(i.width / 2, i.height / 2));
    }
    for (final s in page.shapes) {
      consider(s.id, s.position + Offset(s.width / 2, s.height / 2));
    }
    return best;
  }

  // ---------------- 工具条 ----------------

  /// 选区操作条：完成选区后显示（复制/粘贴/删除/清除 + 缩放/旋转滑块）。
}


