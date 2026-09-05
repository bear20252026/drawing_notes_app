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
      _applyState(() => _canvasInteraction.beginMarquee(canvasPoint));
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
      // 线性元素拖拽读数（长度/角度小气泡，审计二-6）。
      _updateLinearDraftReadout();
      return;
    }

    // 框选工具：更新框选矩形（借鉴 Excalidraw 多选）。
    if (_marqueeActive && _marqueeStart != null) {
      _applyState(() => _canvasInteraction.updateMarquee(canvasPoint));
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

  /// 初始化捏合参数：以当前两指距离/角度为基准。
  void _initPinch() {
    final pts = _activePointers.values.toList();
    if (pts.length < 2) return;
    final d = (pts[0] - pts[1]).distance;
    final a = (pts[1] - pts[0]).direction;
    _pinchDistance = d;
    _pinchAngle = a;
  }

  /// 更新捏合：根据两指距离/角度变化调整画布缩放与旋转。
  void _updatePinch() {
    final pts = _activePointers.values.toList();
    if (pts.length < 2 || _pinchDistance == null || _pinchAngle == null) return;
    final d = (pts[0] - pts[1]).distance;
    final a = (pts[1] - pts[0]).direction;
    if (d < 1e-3) return;

    // 缩放：距离比（限制在合理范围，防止画布被缩放得不可用）。
    final scaleFactor = d / _pinchDistance!;
    _controller.viewScale = (_controller.viewScale * scaleFactor).clamp(
      0.05,
      20.0,
    );

    // 旋转：角度差（弧度），归一化到 [-π, π] 避免跨越边界时翻转。
    var angleDelta = a - _pinchAngle!;
    const pi = 3.141592653589793;
    while (angleDelta > pi) {
      angleDelta -= 2 * pi;
    }
    while (angleDelta < -pi) {
      angleDelta += 2 * pi;
    }
    _controller.viewRotation += angleDelta;

    _pinchDistance = d;
    _pinchAngle = a;
    _controller.tickFrame(); // 视口变换高频更新：只重绘画布。
  }

  void _onPointerUp(PointerUpEvent event) {
    final wasTracked = _activePointers.containsKey(event.pointer);
    final disposition = _inputArbiter.onUp(event);
    if (!wasTracked) return;
    // 按 pointerId 精确移除，避免多指手势中抬起一指误清全部状态。
    _activePointers.remove(event.pointer);
    if (_activePointers.length >= 2) {
      // 仍处于多指：以剩余手指重新校准捏合基准。
      _initPinch();
    } else {
      _pinchDistance = null;
      _pinchAngle = null;
    }

    // 只有实际完成首个单指操作时，才允许后续工具结算。多指视图手势中
    // 的抬起仅清理状态，不能提交笔画、放置形状或结束选区。
    if (disposition != EditorPointerDisposition.finishInk) return;
    if (_eyedropperActive || _textToolActive) return;

    // 框选工具：结算框选，把矩形内的混排对象加入多选（借鉴 Excalidraw）。
    if (_marqueeActive && _marqueeRect != null) {
      final page = widget.session;
      final rect = _marqueeRect!;
      if (page != null) {
        final selectedIds = <String>[
          for (final text in page.textItems)
            if (rect.overlaps(
              Rect.fromLTWH(text.x, text.y, text.fontSize * 2, text.fontSize),
            ))
              text.id,
          for (final image in page.imageItems)
            if (rect.overlaps(
              Rect.fromLTWH(image.x, image.y, image.width, image.height),
            ))
              image.id,
          for (final shape in page.shapes)
            if (rect.overlaps(
              Rect.fromLTWH(shape.x, shape.y, shape.width, shape.height),
            ))
              shape.id,
        ];
        _applyState(() => _canvasInteraction.completeMarquee(selectedIds));
        _notifyChanged();
      } else {
        // 画布模式（问题10）：把虚线框转为多边形，交由控制器做
        // 笔画/形状/图片的统一混合对象选择（选中后可移动/缩放）。
        _controller.selectDocumentObjectsInPolygon([
          rect.topLeft,
          rect.topRight,
          rect.bottomRight,
          rect.bottomLeft,
        ]);
        _applyState(_canvasInteraction.clearMarquee);
        _notifyChanged();
      }
      return;
    }

    // 形状工具：按实际拖拽范围提交到笔记页或独立绘图文档。
    if (_activeShapeTool != null) {
      final tool = _activeShapeTool!;
      final start = _shapeDraftStart;
      final end =
          _shapeDraftCurrent ?? _controller.viewToCanvas(event.localPosition);
      _linearReadout.value = null;
      if (start != null) {
        // 拖拽吸附（审计二-1/二-3）：与 _shapeDraft 预览同一换算——
        // 网格档（20px）优先；否则线性元素做 0°/45°/90° 角度磁吸
        // （Shift 强制）+ 端点对既有形状的 8px 边框磁吸并重投影到边框。
        final linear = ShapeBindingGeometry.isLinearByType(tool);
        final snapped = ShapeCreationGeometry.snappedDragPoints(
          start,
          end,
          linear: linear,
          gridSnapEnabled: _snapToGrid,
          forceAngle: HardwareKeyboard.instance.isShiftPressed,
        );
        var geoStart = snapped.start;
        var geoEnd = snapped.end;
        final page = widget.session;
        String? snapId;
        if (linear && !_snapToGrid) {
          if (page != null) {
            // 分页笔记：端点磁吸到混排对象边框；箭头末端命中即绑定。
            final startHit = _snapEndpointToPageItems(geoStart);
            final endHit = _snapEndpointToPageItems(geoEnd);
            geoStart = startHit.point;
            geoEnd = endHit.point;
            if (tool == ShapeType.arrow) snapId = endHit.targetId;
          } else if (tool == ShapeType.line) {
            // 独立画布直线：无绑定关系，只做边框磁吸对齐（箭头在下方
            // bindArrowAtEndpoints 统一做近旁吸附 + 边框投影）。
            geoStart = _snapLinearDraftEndpoint(geoStart);
            geoEnd = _snapLinearDraftEndpoint(geoEnd);
          }
        } else if (page != null) {
          // 非线性/网格档：保留既有「中心 50px」轻量组合语义（拖动跟随）。
          snapId = _findSnapTargetId(end);
        }
        final geometry = ShapeCreationGeometry.fromDrag(geoStart, geoEnd);
        final shape = geometry.createShape(
          id: LocalIdGenerator.next('shp'),
          shapeType: tool,
          color: _controller.color.toARGB32(),
          strokeWidth: _controller.brushSize,
          boundElementId: snapId,
          // 填充模式开启时新建形状带填充色（问题4）。
          fillColor: _fillShapeEnabled ? _shapeFillColor : null,
        );
        // 独立画布的箭头在起终点落入既有形状邻域时自动建立双端关系，
        // 并把端点重投影到目标边框（消掉视觉缝）。
        // 分页笔记保持原有轻量 `boundElementId` 行为，避免改变其旧格式语义。
        if (page == null && shape.shapeType == ShapeType.arrow) {
          ShapeBindingGeometry.bindArrowAtEndpoints(
            shape,
            _controller.document.shapes,
            start: geoStart,
            end: geoEnd,
          );
        }
        _applyState(() {
          _shapeItems.add(shape);
          _selectedItemId = shape.id;
          _shapeDraftStart = null;
          _shapeDraftCurrent = null;
        });
        _controller.document.touch();
        _notifyChanged();
      }
      return;
    }

    // 选区模式
    if (_controller.selectionTool != SelectionTool.none) {
      if (!_isNotebookMode &&
          _selectionDone &&
          _controller.selectedDocumentObjectCount > 1) {
        _lastDragCanvas = null;
        _controller.endDocumentObjectsTransform();
        _notifyChanged();
      } else if (_selectionDone && _controller.hasSelectedDocumentShape) {
        _lastDragCanvas = null;
        _controller.endDocumentShapeTransform();
        _notifyChanged();
      } else if (_selectionDone && _controller.hasSelectedStrokes) {
        _lastDragCanvas = null;
        _controller.endTransform();
        _notifyChanged();
      } else {
        _controller.endSelection();
        final polygon = _controller.selection.polygon;
        if (!_isNotebookMode && polygon.length >= 3) {
          _controller.selectDocumentObjectsInPolygon(polygon);
        }
        if (_controller.hasSelection ||
            (!_isNotebookMode && _controller.hasMixedDocumentObjectSelection)) {
          _viewModel.setSelectionDone(true);
        }
        // 分页笔记保留既有的混排对象套索；独立绘图文档由控制器统一维护
        // 笔画、形状和图片选择，避免 UI 侧临时 ID 与历史事务脱节。
        if (_isNotebookMode && polygon.length >= 3) {
          final path = Path()..addPolygon(polygon, true);
          final page = widget.session;
          if (page != null) {
            final selectedIds = <String>[
              for (final text in page.textItems)
                if (path.contains(
                  text.position + Offset(text.fontSize, text.fontSize / 2),
                ))
                  text.id,
              for (final image in page.imageItems)
                if (path.contains(
                  image.position + Offset(image.width / 2, image.height / 2),
                ))
                  image.id,
              for (final shape in page.shapes)
                if (path.contains(
                  shape.position + Offset(shape.width / 2, shape.height / 2),
                ))
                  shape.id,
            ];
            _applyState(
              () => _canvasInteraction.addToMultiSelection(selectedIds),
            );
          }
        }
      }
      return;
    }
    if (_isObjectEraser) {
      _controller.endObjectErase();
      _notifyChanged();
      return;
    }
    _controller.endStroke();
    _notifyChanged();
  }

  void _onPointerCancel(PointerCancelEvent event) {
    final wasTracked = _activePointers.containsKey(event.pointer);
    _inputArbiter.onCancel(event);
    if (!wasTracked) return;
    _activePointers.remove(event.pointer);
    _pinchDistance = null;
    _pinchAngle = null;
    if (_activeShapeTool != null) {
      _applyState(() {
        _shapeDraftStart = null;
        _shapeDraftCurrent = null;
      });
      _linearReadout.value = null;
      return;
    }
    if (_eyedropperActive || _textToolActive) return;
    if (_controller.selectionTool != SelectionTool.none) {
      _lastDragCanvas = null;
      if (!_isNotebookMode && _controller.selectedDocumentObjectCount > 1) {
        _controller.cancelDocumentObjectsTransform();
      } else {
        _controller.cancelDocumentShapeTransform();
        _controller.cancelDocumentImageTransform();
      }
      return;
    }
    if (_isObjectEraser) {
      _controller.cancelObjectErase();
      return;
    }
    _controller.cancelActiveStroke();
  }

  /// 滚轮缩放画布：以鼠标当前位置为锚点（桌面端标准交互）。
  ///
  /// 滚轮向上（dy < 0）放大，向下（dy > 0）缩小；
  /// 缩放后鼠标指向的画布位置保持不变（锚点不漂移）。
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    // 每格滚轮缩放 10%（factor>1 放大，<1 缩小）。
    final factor = event.scrollDelta.dy < 0 ? 1.1 : 1 / 1.1;
    _zoomAt(event.localPosition, factor);
  }

  /// 以视口坐标 [viewPoint] 为锚点缩放画布 [factor] 倍。
  void _zoomAt(Offset viewPoint, double factor) {
    final oldScale = _controller.viewScale;
    final newScale = (oldScale * factor).clamp(0.05, 20.0);
    if ((newScale - oldScale).abs() < 1e-9) return;

    // 保持锚点不动：缩放前后锚点对应的画布坐标必须一致。
    // 由变换模型 view = R·(scale·(p - center)) + center + offset 推导：
    //   offset' = view - R·(newScale·(p - center)) - center
    // 其中 p = viewToCanvas(viewPoint)（缩放前）。
    final c = _controller.document.size.center(Offset.zero);
    final canvasPoint = _controller.viewToCanvas(viewPoint);
    final rotated = rotatePoint2(
      (canvasPoint - c) * newScale,
      _controller.viewRotation,
    );
    _controller.viewOffset = viewPoint - rotated - c;
    _controller.viewScale = newScale;
    _controller.tickFrame(); // 高频重绘：仅画布。
  }

  /// 状态栏缩放菜单（审计三-2）：缩放到指定倍率，保持视口中心不漂移。
  void _setScaleFromMenu(double scale) {
    final viewport = _viewportSize;
    final current = _controller.viewScale;
    if (viewport == null || current <= 0) return;
    _zoomAt(
      Offset(viewport.width / 2, viewport.height / 2),
      scale / current,
    );
  }

  /// 状态栏「适应画布」（审计三-2）：按视口适配整页并居中（与
  /// _initViewport 首次进入同一套几何）。
  void _fitCanvasToViewport() {
    final viewport = _viewportSize;
    if (viewport == null) return;
    final doc = _controller.document;
    final scaleW = viewport.width / doc.width;
    final scaleH = viewport.height / doc.height;
    _controller.viewScale = (scaleW < scaleH ? scaleW : scaleH).clamp(
      0.05,
      8.0,
    );
    _controller.viewOffset = Offset(
      viewport.width / 2 - doc.width / 2,
      viewport.height / 2 - doc.height / 2,
    );
    _controller.tickFrame();
  }

  /// 在画布坐标处取色并更新当前画笔颜色（P-2 修复 2026-08-15：200ms
  /// 冷却节流——pickColorAt 每次完整重绘文档到图片，极重操作）。
  Future<void> _pickColor(Offset canvasPoint) async {
    final now = DateTime.now();
    if (_lastPickColorAt != null &&
        now.difference(_lastPickColorAt!) < const Duration(milliseconds: 200)) {
      return; // 节流：200ms 冷却期内忽略重复取色
    }
    _lastPickColorAt = now;
    final color = await _controller.pickColorAt(canvasPoint);
    if (color == null) return;
    _updateCurrentBrushPreset(color: color);
    _applyState(() => _viewModel.setEyedropperActive(false));
  }

  /// 打开颜色选择对话框，应用用户选择的颜色。
  Future<void> _showColorPicker() async {
    final color = await GlassDialog.show<Color>(
      context: context,
      builder: (_) => ColorPickerDialog(initialColor: _controller.color),
    );
    if (color != null) {
      _updateCurrentBrushPreset(color: color);
    }
  }
}
