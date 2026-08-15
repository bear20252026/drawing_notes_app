part of 'drawing_controller.dart';

// 笔画选区/变换域（O1 拆分）：矩形/套索选区命中、移动/缩放/旋转、
// 剪贴板复制粘贴方法从 drawing_controller.dart 移出为 extension；
// 行为零变化。

/// 笔画选区/变换域（拆分自 drawing_controller.dart）。
extension DrawingControllerSelectionOps on DrawingController {
  void beginSelection(Offset canvasPoint) {
    _selectionDraft
      ..clear()
      ..add(canvasPoint);
    tickFrame();
  }

  /// 延伸选区（拖动过程中调用）。
  void extendSelection(Offset canvasPoint) {
    if (_selectionTool == SelectionTool.rect) {
      // 矩形选区：只需记录起点与当前点，由绘制层实时画出矩形。
      if (_selectionDraft.isEmpty) _selectionDraft.add(canvasPoint);
      // 保持起点不变，追加当前点（用于渲染）。
      _selectionDraft
        ..removeRange(1, _selectionDraft.length)
        ..add(canvasPoint);
    } else {
      // 套索选区：逐点追加，形成自由多边形。
      _selectionDraft.add(canvasPoint);
    }
    tickFrame(); // 拖动中高频更新：只重绘画布上的选区轮廓。
  }

  /// 结束选区：由草稿生成正式选区，并做笔画命中检测。
  void endSelection() {
    if (_selectionDraft.isEmpty) {
      _selection = const Selection();
    _selectionCenterDirty = true;
      _applyNotify();
      return;
    }

    // 矩形选区：草稿为"起点+当前点"两个点，展开为 4 顶点多边形。
    // 套索选区：草稿为自由点列，至少 3 点才能构成区域。
    if (_selectionTool == SelectionTool.rect && _selectionDraft.length >= 2) {
      final a = _selectionDraft.first;
      final b = _selectionDraft.last;
      final polygon = [a, Offset(b.dx, a.dy), b, Offset(a.dx, b.dy)];
      _selection = Selection(
        polygon: polygon,
        selectedStrokeIndices: _hitTestStrokes(polygon),
      );
    } else if (_selectionTool == SelectionTool.lasso &&
        _selectionDraft.length >= 3) {
      final polygon = List.of(_selectionDraft);
      _selection = Selection(
        polygon: polygon,
        selectedStrokeIndices: _hitTestStrokes(polygon),
      );
    } else {
      // 草稿不构成有效选区（矩形只有单点 / 套索少于 3 点）。
      _selection = const Selection();
    _selectionCenterDirty = true;
    }
    _selectionCenterDirty = true;
    _selectionDraft.clear();
    _applyNotify();
  }

  /// 命中检测：返回选区多边形命中的当前图层笔画索引。
  ///
  /// 除了采样点落在内部，也检测笔画线段与套索边界的交叉，避免一条只含两个
  /// 端点的长线“穿过选区却选不中”。
  List<int> _hitTestStrokes(List<Offset> polygon) {
    final strokes = currentLayer.strokes;
    final result = <int>[];
    for (var i = 0; i < strokes.length; i++) {
      final points = strokes[i].points;
      if (points.any((point) => _pointInPolygon(point.offset, polygon)) ||
          DrawingController._strokeIntersectsPolygon(points, polygon)) {
        result.add(i);
      }
    }
    return result;
  }


  /// 射线法判断点是否在多边形内。
  bool _pointInPolygon(Offset point, List<Offset> polygon) {
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final a = polygon[i], b = polygon[j];
      final intersects =
          (a.dy > point.dy) != (b.dy > point.dy) &&
          point.dx < (b.dx - a.dx) * (point.dy - a.dy) / (b.dy - a.dy) + a.dx;
      if (intersects) inside = !inside;
    }
    return inside;
  }

  /// 清除选区。
  void clearSelection() {
    if (_selection.polygon.isEmpty && _selectedDocumentImageId == null) return;
    _selection = const Selection();
    _selectionCenterDirty = true;
    _selectedDocumentImageId = null;
    _applyNotify();
  }

  /// 平移选中的笔画（拖拽移动）。
  void moveSelectedStrokes(Offset delta) {
    if (!hasSelectedStrokes) return;
    _ensureTransformBefore();
    _transformSelected((p) => p + delta);
  }

  /// 缩放选中的笔画（围绕选区中心）。
  void scaleSelectedStrokes(double factor) {
    if (!hasSelectedStrokes) return;
    _ensureTransformBefore();
    final c = _selectedStrokeCenter();
    _transformSelected((p) => c + (p - c) * factor);
  }

  /// 旋转选中的笔画（围绕选区中心，角度为弧度）。
  void rotateSelectedStrokes(double radians) {
    if (!hasSelectedStrokes) return;
    _ensureTransformBefore();
    final c = _selectedStrokeCenter();
    final cosA = math.cos(radians);
    final sinA = math.sin(radians);
    _transformSelected((p) {
      final dx = p.dx - c.dx, dy = p.dy - c.dy;
      return Offset(c.dx + dx * cosA - dy * sinA, c.dy + dx * sinA + dy * cosA);
    });
  }

  /// 已选笔画的实际外接框中心。手势套索可画得很大，因此不能把套索包围盒
  /// 中心误用为变换锚点，否则用户会感到缩放、旋转“漂移”。
  Offset _selectedStrokeCenter() {
    // P-1 修复（专家审查 2026-08-15）：缓存选区中心——scale/rotate 围绕
    // 中心变换（中心不变），滑块连续拖动不再每次 O(N×M) 重算；选区
    // 变化时经 _selectionCenterDirty 失效。
    if (!_selectionCenterDirty && _selectionCenterCache != null) {
      return _selectionCenterCache!;
    }
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;
    for (final index in _selection.selectedStrokeIndices) {
      final stroke = currentLayer.strokes[index];
      for (final point in stroke.points) {
        minX = math.min(minX, point.x);
        minY = math.min(minY, point.y);
        maxX = math.max(maxX, point.x);
        maxY = math.max(maxY, point.y);
      }
    }
    final center = !minX.isFinite
        ? _selection.center
        : Offset((minX + maxX) / 2, (minY + maxY) / 2);
    _selectionCenterCache = center;
    _selectionCenterDirty = false;
    return center;
  }

  /// 记录变换前的图层快照（首次变换时调用一次）。
  void _ensureTransformBefore() {
    _transformBefore ??= _snapshotLayers();
  }

  /// 对选中的笔画统一应用坐标变换（保持宽度/颜色不变）。
  ///
  /// 注意：变换不产生新的历史条目（供拖拽过程中反复调用），
  /// 需要撤销时由调用方在拖拽结束后 push 一次历史（见 endTransform）。
  void _transformSelected(Offset Function(Offset) transform) {
    final indices = _selection.selectedStrokeIndices;
    final strokes = currentLayer.strokes;
    for (final i in indices.reversed) {
      final old = strokes[i];
      final newPoints = old.points.map((p) {
        final t = transform(p.offset);
        return StrokePoint(t.dx, t.dy, p.pressure);
      }).toList();
      strokes[i] = Stroke(
        points: newPoints,
        color: old.color,
        width: old.width,
        type: old.type,
        opacity: old.opacity,
      );
    }
    _document.touch();
    _invalidateLayer(currentLayer.id);
    _applyNotify();
  }

  /// 变换结束：把"变换前快照 → 当前状态"记入历史（拖拽/滑块松手后调用一次）。
  void endTransform() {
    final before = _transformBefore;
    if (before == null) return;
    _transformBefore = null;
    _pushHistory(HistoryEntry(before: before, after: _snapshotLayers()));
  }

  /// 删除选中的笔画。
  void deleteSelectedStrokes() {
    if (!hasSelectedStrokes) return;
    final before = _snapshotLayers();
    final indices = _selection.selectedStrokeIndices;
    for (final i in indices.reversed) {
      currentLayer.strokes.removeAt(i);
    }
    _document.touch();
    _selection = const Selection();
    _selectionCenterDirty = true;
    _pushHistory(HistoryEntry(before: before, after: _snapshotLayers()));
    _invalidateLayer(currentLayer.id);
    _applyNotify();
  }

  /// 复制选中的笔画到剪贴板（内部副本，不修改图层）。
  void copySelectedStrokes() {
    if (!hasSelectedStrokes) return;
    _clipboard = [
      for (final i in _selection.selectedStrokeIndices)
        _copyStroke(currentLayer.strokes[i]),
    ];
  }

  /// 粘贴剪贴板中的笔画到当前图层（在原位置基础上整体偏移，避免覆盖原件）。
  void pasteClipboard() {
    final clip = _clipboard;
    if (clip == null || clip.isEmpty) return;
    final before = _snapshotLayers();
    // 固定偏移量：粘贴内容出现在原内容的右下方向，肉眼可见且不遮挡。
    const delta = Offset(20, 20);
    for (final stroke in clip) {
      currentLayer.strokes.add(_offsetStroke(stroke, delta));
    }
    _document.touch();
    _selection = const Selection();
    _selectionCenterDirty = true;
    _pushHistory(HistoryEntry(before: before, after: _snapshotLayers()));
    _invalidateLayer(currentLayer.id);
    _applyNotify();
  }

  Stroke _copyStroke(Stroke s) => Stroke(
    points: [for (final p in s.points) StrokePoint(p.x, p.y, p.pressure)],
    color: s.color,
    width: s.width,
    type: s.type,
    opacity: s.opacity,
  );

  /// 把笔画整体平移指定偏移（保留原形状，用于粘贴）。
  Stroke _offsetStroke(Stroke s, Offset delta) {
    return Stroke(
      points: [
        for (final p in s.points)
          StrokePoint(p.x + delta.dx, p.y + delta.dy, p.pressure),
      ],
      color: s.color,
      width: s.width,
      type: s.type,
      opacity: s.opacity,
    );
  }
}
