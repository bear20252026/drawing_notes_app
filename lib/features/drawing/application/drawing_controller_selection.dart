part of 'drawing_controller.dart';

/// 笔画选区工具与编辑 API 的兼容委托层。
///
/// 矩形和套索草稿、命中检测仍需与当前图层和高频画布刷新协作；已选笔画
/// 的变换、剪贴板、删除及图层快照由 [StrokeSelectionEditingSession] 持有。
extension DrawingControllerSelectionOps on DrawingController {
  void beginSelection(Offset canvasPoint) {
    _selectionSession.beginDraft(canvasPoint);
    tickFrame();
  }

  /// 延伸选区（拖动过程中调用）。
  void extendSelection(Offset canvasPoint) {
    _selectionSession.extendDraft(canvasPoint);
    tickFrame();
  }

  /// 结束选区：由草稿生成正式选区，并做笔画命中检测。
  void endSelection() {
    final draft = _selectionSession.draft;
    if (draft.isEmpty) {
      _selectionSession.completeDraft(const Selection());
      _applyNotify();
      return;
    }

    final Selection result;
    if (_selectionSession.tool == SelectionTool.rect && draft.length >= 2) {
      final a = draft.first;
      final b = draft.last;
      final polygon = <Offset>[a, Offset(b.dx, a.dy), b, Offset(a.dx, b.dy)];
      result = Selection(
        polygon: polygon,
        selectedStrokeIndices: _hitTestStrokes(polygon),
      );
    } else if (_selectionSession.tool == SelectionTool.lasso &&
        draft.length >= 3) {
      final polygon = List<Offset>.of(draft);
      result = Selection(
        polygon: polygon,
        selectedStrokeIndices: _hitTestStrokes(polygon),
      );
    } else {
      result = const Selection();
    }
    _selectionSession.completeDraft(result);
    _applyNotify();
  }

  /// 返回被选区多边形命中的当前图层笔画索引。
  ///
  /// 除了采样点落在内部，也检测笔画线段与套索边界的交叉，确保端点位于
  /// 外部的长笔画在穿过选区时仍可被选中。
  List<int> _hitTestStrokes(List<Offset> polygon) {
    final strokes = currentLayer.strokes;
    final result = <int>[];
    for (var index = 0; index < strokes.length; index++) {
      final points = strokes[index].points;
      if (points.any((point) => _pointInPolygon(point.offset, polygon)) ||
          DrawingController._strokeIntersectsPolygon(points, polygon)) {
        result.add(index);
      }
    }
    return result;
  }

  bool _pointInPolygon(Offset point, List<Offset> polygon) {
    var inside = false;
    for (
      var index = 0, previous = polygon.length - 1;
      index < polygon.length;
      previous = index++
    ) {
      final a = polygon[index];
      final b = polygon[previous];
      final intersects =
          (a.dy > point.dy) != (b.dy > point.dy) &&
          point.dx < (b.dx - a.dx) * (point.dy - a.dy) / (b.dy - a.dy) + a.dx;
      if (intersects) inside = !inside;
    }
    return inside;
  }

  /// 清除笔画、形状和图片的统一选择状态。
  void clearSelection() => clearDocumentObjectSelection();

  void moveSelectedStrokes(Offset delta) =>
      _strokeSelectionEditingSession.moveSelectedStrokes(delta);
  void scaleSelectedStrokes(double factor) =>
      _strokeSelectionEditingSession.scaleSelectedStrokes(factor);
  void rotateSelectedStrokes(double radians) =>
      _strokeSelectionEditingSession.rotateSelectedStrokes(radians);
  void endTransform() => _strokeSelectionEditingSession.endTransform();
  void deleteSelectedStrokes() =>
      _strokeSelectionEditingSession.deleteSelectedStrokes();
  void copySelectedStrokes() =>
      _strokeSelectionEditingSession.copySelectedStrokes();
  void pasteClipboard() => _strokeSelectionEditingSession.pasteClipboard();
}
