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
          actions: _buildToolbarActions(),
        );
      },
    );
  }

  Set<String> _expandGroup(Set<String> ids) {
    final page = widget.session;
    if (page == null) return Set<String>.unmodifiable(ids);
    return EditorOverlayGroupResolver.expand(
      selectedIds: ids,
      textItems: page.textItems,
      imageItems: page.imageItems,
      shapes: page.shapes,
    );
  }

  // ── 混排拖拽事务便捷入口（拖拽撤销专项 2026-11-17）──────────────
  // overlay 手势链路（移动/旋转/缩放/宽度柄）统一经此三法登记撤销；
  // 独立画布指针链路走 session 事务，不经这里（防双记）。

  /// 手势起点：拍四类集合起始深快照（笔记模式才有混排集合）。
  void _beginMixedDrag() {
    final page = widget.session;
    if (page == null) return;
    MixedObjectDragRecorder.begin(
      interaction: _canvasInteraction,
      textItems: page.textItems,
      imageItems: page.imageItems,
      shapes: page.shapes,
      charts: page.charts,
    );
  }

  /// 手势终点：有变化登记一条撤销，随后走既有保存链通知。
  void _commitMixedDrag() {
    final page = widget.session;
    if (page == null) return;
    MixedObjectDragRecorder.commit(
      interaction: _canvasInteraction,
      textItems: page.textItems,
      imageItems: page.imageItems,
      shapes: page.shapes,
      charts: page.charts,
      host: _controller,
      markDirty: _notifyChanged,
    );
    _notifyChanged();
  }

  /// 手势取消：还原起始快照、不入栈，随后补保存链通知（还原也是改动）。
  void _cancelMixedDrag() {
    final page = widget.session;
    if (page == null) return;
    MixedObjectDragRecorder.cancel(
      interaction: _canvasInteraction,
      textItems: page.textItems,
      imageItems: page.imageItems,
      shapes: page.shapes,
      charts: page.charts,
      host: _controller,
    );
    _notifyChanged();
  }

  void _dragItem(String id, Offset screenDelta) {
    final page = widget.session;
    if (page == null) return;
    // 屏幕位移 -> 画布位移（除以缩放、反向旋转）。
    final canvasDelta = screenDeltaToCanvas(
      screenDelta,
      _controller.viewRotation,
      _controller.viewScale,
    );
    // 动画尾迹（借鉴 Excalidraw animatedTrail）：记录最近拖动点。
    _canvasInteraction.recordTrail(canvasDelta);
    // 多选：拖动任一选中元素时整体移动所有选中元素（借鉴 Excalidraw 多选）。
    final moveIds = _expandGroup(
      _multiSelectedIds.isNotEmpty ? {..._multiSelectedIds, id} : <String>{id},
    );
    // 高频拖动只 tick（审计 #5）：overlay 层（frameTick 驱动）逐帧
    // 重建 items 与对齐参考线 painter，不再全页 setState。
    const grid = 20.0;
    double snap(double v) => _snapToGrid ? (v / grid).round() * grid : v;
    for (final t in page.textItems) {
      if (moveIds.contains(t.id)) {
        t.x = snap(t.x + canvasDelta.dx)
            .clamp(0, _controller.document.width.toDouble());
        t.y = snap(t.y + canvasDelta.dy)
            .clamp(0, _controller.document.height.toDouble());
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
    // 图表元素（拖拽撤销专项 2026-11-17）：overlay 早已挂 _dragItem(chart.id)
    // 回调，但本方法此前没有图表循环——图表拖拽是死手势（回调空转）。
    // 补齐与形状同口径的移动（clamp 到文档边界）。
    for (final c in page.charts) {
      if (moveIds.contains(c.id)) {
        c.x = (c.x + canvasDelta.dx).clamp(
          0,
          _controller.document.width.toDouble(),
        );
        c.y = (c.y + canvasDelta.dy).clamp(
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
    _controller.tickFrame();
  }

  /// 拖动后对齐吸附：把 [id] 元素吸附到其他元素的边/中心对齐线。
  ///
  /// 容差 [snapTol]（画布坐标）；仅当拖动对象与任一参考线足够近时吸附，
  /// 视觉上形成"对齐参考线"的体验（借鉴 Excalidraw）。
  void _snapDragItemToAlign(String id) {
    // 画布模式的对象拖动由 controller 统一管理（不走 _dragItem），
    // 因此对齐吸附仅作用于分页笔记的混排对象；无限画布吸附属于
    // controller 层后续工程（记录于审查报告）。
    final page = widget.session;
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
      _canvasInteraction.replaceSnapGuides(guides);
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
      _canvasInteraction.clearSnapGuides();
    }
  }

  /// 等间距分布：把页面全部混排对象（文字/图片/形状）按水平或垂直
  /// 等间距排列（借鉴 Excalidraw 对齐/分布工具）。
  void _distributeItems(bool horizontal) {
    final page = widget.session;
    if (page == null) return;
    // 收集 (对象, 轴向中心, 回写器)：排序携带对象引用，按排序结果直接
    // 回写对应对象——此前目标槽位按「文字→图片→形状」集合顺序分配，
    // 与位置顺序交叉时元素互相跳位（水平/垂直两分支同病）。
    final items = <({double pos, void Function(double center) place})>[];
    for (final t in page.textItems) {
      items.add((
        pos: t.x + t.fontSize,
        place: (center) => t.x = center - t.fontSize,
      ));
    }
    for (final i in page.imageItems) {
      items.add((
        pos: i.x + i.width / 2,
        place: (center) => i.x = center - i.width / 2,
      ));
    }
    for (final s in page.shapes) {
      items.add((
        pos: s.x + s.width / 2,
        place: (center) => s.x = center - s.width / 2,
      ));
    }
    if (items.length < 3) {
      _showSnack(
        AppLocalizations.of(context)?.distributeNeed3 ?? '至少需要 3 个元素才能分布',
      );
      return;
    }
    // 水平分布：按中心 X 排序，重排到首尾之间等间距。
    if (horizontal) {
      items.sort((a, b) => a.pos.compareTo(b.pos));
      final first = items.first.pos;
      final last = items.last.pos;
      final step = (last - first) / (items.length - 1);
      for (var idx = 0; idx < items.length; idx++) {
        items[idx].place(first + step * idx);
      }
    } else {
      // 垂直分布：按中心 Y 排序。
      final vItems = <({double pos, void Function(double center) place})>[];
      for (final t in page.textItems) {
        vItems.add((
          pos: t.y + t.fontSize / 2,
          place: (center) => t.y = center - t.fontSize / 2,
        ));
      }
      for (final i in page.imageItems) {
        vItems.add((
          pos: i.y + i.height / 2,
          place: (center) => i.y = center - i.height / 2,
        ));
      }
      for (final s in page.shapes) {
        vItems.add((
          pos: s.y + s.height / 2,
          place: (center) => s.y = center - s.height / 2,
        ));
      }
      if (vItems.length < 3) {
        _showSnack(
          AppLocalizations.of(context)?.distributeNeed3 ?? '至少需要 3 个元素才能分布',
        );
        return;
      }
      vItems.sort((a, b) => a.pos.compareTo(b.pos));
      final first = vItems.first.pos;
      final last = vItems.last.pos;
      final step = (last - first) / (vItems.length - 1);
      for (var idx = 0; idx < vItems.length; idx++) {
        vItems[idx].place(first + step * idx);
      }
    }
    _applyState(() {});
    _notifyChanged();
    _showSnack(
      horizontal
          ? _l10nSafe?.distributedH ?? '已水平等间距分布'
          : _l10nSafe?.distributedV ?? '已垂直等间距分布',
    );
  }

  /// 返回 [canvasPoint] 附近（50px 内）吸附命中的混排对象 id。
  ///
  /// 与 [_findSnapTarget] 同逻辑但返回元素 id（供箭头绑定 boundElementId 使用）；
  /// 无命中返回 null。
  String? _findSnapTargetId(Offset canvasPoint) {
    final page = widget.session;
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

  // ---------------- 线性元素端点吸附与编辑（审计二-2/二-3，2026-09-06） ----------------

  /// 线性端点对分页笔记混排对象的磁吸：端点距任一对象外接框 ≤ 8px 时，
  /// 吸附到该框周界并返回目标 id（箭头 boundElementId 用）。
  ///
  /// 替代旧「按中心 50px」判定用于线性元素：大形状边缘绑得上、小形状不会被
  /// 旁边大形状抢绑，且端点直接落在目标边上，不再留视觉缝。
  ({String? targetId, Offset point}) _snapEndpointToPageItems(
    Offset point, {
    String? excludingId,
  }) {
    final page = widget.session;
    if (page == null) return (targetId: null, point: point);
    Rect? bestBounds;
    String? bestId;
    var bestDistance = ShapeBindingGeometry.endpointSnapTolerance;
    void consider(String id, Rect bounds) {
      if (id == excludingId) return;
      final d = ShapeBindingGeometry.distanceToBounds(point, bounds);
      if (d < bestDistance) {
        bestDistance = d;
        bestBounds = bounds;
        bestId = id;
      }
    }

    for (final t in page.textItems) {
      consider(t.id, Rect.fromLTWH(t.x, t.y, t.fontSize * 2, t.fontSize));
    }
    for (final i in page.imageItems) {
      consider(i.id, Rect.fromLTWH(i.x, i.y, i.width, i.height));
    }
    for (final s in page.shapes) {
      consider(s.id, Rect.fromLTWH(s.x, s.y, s.width, s.height));
    }
    if (bestBounds == null) return (targetId: null, point: point);
    return (
      targetId: bestId,
      point: ShapeBindingGeometry.projectPointToBounds(point, bestBounds!),
    );
  }

  /// 拖拽预览的线性端点磁吸：分页笔记 → 混排对象边框；独立画布 → 可绑定形状。
  Offset _snapLinearDraftEndpoint(Offset point) {
    final page = widget.session;
    if (page != null) return _snapEndpointToPageItems(point).point;
    final target = ShapeBindingGeometry.bindableShapeNear(
      point,
      _controller.document.shapes,
    );
    return target == null
        ? point
        : ShapeBindingGeometry.projectPointToBounds(
            point,
            ShapeBindingGeometry.rawBounds(target),
          );
  }

  /// 分页笔记：拖动选中线性元素的一个端点（画布坐标增量累计制）。
  ///
  /// 吸附顺序与创建一致：形状磁吸优先，未命中再做 0°/45°/90° 角度磁吸。
  /// 箭头末端命中目标时同步维护 boundElementId（单目标语义）。
  void _dragNotebookLinearEndpoint(PageShapeItem shape, bool isStart) {
    final base = _linearEndpointDragBase;
    if (base == null) return;
    final rawTarget = (isStart ? base.start : base.end) + _linearEndpointAccum;
    final anchor = isStart ? base.end : base.start;
    final hit = _snapEndpointToPageItems(rawTarget, excludingId: shape.id);
    final snapped = hit.targetId != null
        ? hit.point
        : ShapeCreationGeometry.snapDragAngle(anchor, rawTarget);
    _applyState(() {
      ShapeBindingGeometry.applyLinearEndpoints(
        shape,
        start: isStart ? snapped : anchor,
        end: isStart ? anchor : snapped,
      );
      if (shape.shapeType == ShapeType.arrow && !isStart) {
        shape.boundElementId = hit.targetId;
      }
    });
    _updateLinearReadoutFromShape(shape, isStart);
  }

  /// 选中线性元素的当前全局端点（分页笔记用本地集合；箭头含绑定解析）。
  ({Offset start, Offset end}) _resolvedLinearEndpointsOf(
    PageShapeItem shape,
  ) => shape.shapeType == ShapeType.arrow
      ? ShapeBindingGeometry.resolvedArrowEndpoints(shape, _shapeItems)
      : ShapeBindingGeometry.linearEndpoints(shape);

  /// 由形状当前端点刷新拖拽读数气泡（[atStart] 端为气泡锚点）。
  void _updateLinearReadoutFromShape(PageShapeItem shape, bool atStart) {
    final e = _resolvedLinearEndpointsOf(shape);
    final delta = e.end - e.start;
    _linearReadout.value = LinearDraftReadout(
      viewPos: _controller.canvasToView(atStart ? e.start : e.end),
      length: delta.distance,
      angleDeg: delta.direction * 180 / math.pi,
    );
  }

  /// 形状创建拖拽中的读数气泡（取吸附后的草稿端点）。
  void _updateLinearDraftReadout() {
    final draft = _shapeDraft;
    final tool = _activeShapeTool;
    if (draft == null || !ShapeBindingGeometry.isLinearByType(tool!)) {
      _linearReadout.value = null;
      return;
    }
    final e = ShapeBindingGeometry.linearEndpoints(draft);
    final delta = e.end - e.start;
    _linearReadout.value = LinearDraftReadout(
      viewPos: _controller.canvasToView(e.end),
      length: delta.distance,
      angleDeg: delta.direction * 180 / math.pi,
    );
  }

  // ---------------- 工具条 ----------------

  /// 选区操作条：完成选区后显示（复制/粘贴/删除/清除 + 缩放/旋转滑块）。

  // ── 分组（R1 归并 2026-11-17：自 editing 逐字搬移，与 _expandGroup 同域）──

  /// 分组：给选中的多个元素设置相同 groupId（借鉴 Excalidraw groupIds）。
  void _groupSelected() {
    final page = widget.session;
    if (page == null) return;
    final ids = _multiSelectedIds.isNotEmpty
        ? _multiSelectedIds
        : <String>{?_selectedItemId};
    if (ids.length < 2) {
      _showSnack(
        AppLocalizations.of(context)?.edGroupNeed2 ?? '请先框选/多选至少 2 个元素再分组',
      );
      return;
    }
    final groupId = LocalIdGenerator.next('grp');
    _applyState(() {
      EditorPageObjectMutation.setGroupId(
        ids: ids,
        groupId: groupId,
        textItems: page.textItems,
        imageItems: page.imageItems,
        shapes: page.shapes,
      );
    });
    _notifyChanged();
    _showSnack(_l10nSafe?.edGroupedN(ids.length) ?? '已分组 ${ids.length} 个元素');
  }

  /// 取消分组：清空选中元素的 groupId。
  void _ungroupSelected() {
    final page = widget.session;
    if (page == null) return;
    final ids = _multiSelectedIds.isNotEmpty
        ? _multiSelectedIds
        : <String>{?_selectedItemId};
    _applyState(() {
      EditorPageObjectMutation.setGroupId(
        ids: ids,
        groupId: null,
        textItems: page.textItems,
        imageItems: page.imageItems,
        shapes: page.shapes,
      );
    });
    _notifyChanged();
    _showSnack(_l10nSafe?.edUngrouped ?? '已取消分组');
  }
}
