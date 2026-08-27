import 'dart:ui' show Offset;

import 'package:drawing_notes_app/features/drawing/application/selection_geometry_service.dart';
import 'package:drawing_notes_app/features/drawing/domain/layer.dart';
import 'package:drawing_notes_app/features/drawing/domain/selection.dart';
import 'package:drawing_notes_app/features/drawing/domain/stroke.dart';

/// 绘图笔画选区的运行时会话状态。
///
/// 该会话只持有短生命周期 UI 状态，不修改文档、不管理历史和渲染缓存；
/// [DrawingController] 仍负责命中测试、几何变换和命令提交。
class DrawingSelectionSession {
  SelectionTool tool = SelectionTool.none;
  Selection selection = const Selection();
  final List<Offset> _draft = <Offset>[];
  Offset? centerCache;
  bool centerDirty = true;
  List<Stroke>? clipboard;
  List<Layer>? transformBefore;

  List<Offset> get draft => _draft;
  bool get hasSelection => selection.polygon.length >= 3;
  bool get hasSelectedStrokes => selection.selectedStrokeIndices.isNotEmpty;

  /// 切换工具时清除正式选区与中心缓存，但保留剪贴板以支持跨选区粘贴。
  void setTool(SelectionTool value) {
    tool = value;
    clearSelection();
  }

  void beginDraft(Offset canvasPoint) {
    _draft
      ..clear()
      ..add(canvasPoint);
  }

  void extendDraft(Offset canvasPoint) {
    if (tool == SelectionTool.rect) {
      if (_draft.isEmpty) _draft.add(canvasPoint);
      _draft
        ..removeRange(1, _draft.length)
        ..add(canvasPoint);
      return;
    }
    _draft.add(canvasPoint);
  }

  /// 用新结果结束草稿选区，并使变换锚点缓存失效。
  void completeDraft(Selection value) {
    selection = value;
    invalidateCenter();
    _draft.clear();
  }

  void clearSelection() {
    selection = const Selection();
    invalidateCenter();
  }

  void invalidateCenter() {
    centerCache = null;
    centerDirty = true;
  }

  Offset cacheCenter(Offset value) {
    centerCache = value;
    centerDirty = false;
    return value;
  }

  void clearTransformBefore() => transformBefore = null;
}

/// 笔画选区交互会话与宿主控制器之间的最小协作边界。
///
/// 会话管理矩形/套索草稿的交互时序和笔画命中；当前图层、选区运行时状态
/// 以及帧级或状态级通知仍由宿主的专门协作者实际持有。
abstract interface class StrokeSelectionInteractionHost {
  Layer get currentLayer;
  DrawingSelectionSession get selectionSession;

  void requestFrame();
  void notifyChanged();
}

/// 矩形与套索笔画选区的草稿、完成和命中编排。
///
/// 高频草稿更新只请求帧级重绘；草稿完成后才发布状态级通知，保持原有画布
/// 跟手性能和工具栏/选区状态刷新时序。
class StrokeSelectionInteractionSession {
  StrokeSelectionInteractionSession(this._host);

  final StrokeSelectionInteractionHost _host;

  DrawingSelectionSession get _selection => _host.selectionSession;

  void beginSelection(Offset canvasPoint) {
    _selection.beginDraft(canvasPoint);
    _host.requestFrame();
  }

  void extendSelection(Offset canvasPoint) {
    _selection.extendDraft(canvasPoint);
    _host.requestFrame();
  }

  void endSelection() {
    final draft = _selection.draft;
    if (draft.isEmpty) {
      _selection.completeDraft(const Selection());
      _host.notifyChanged();
      return;
    }

    final Selection result;
    if (_selection.tool == SelectionTool.rect && draft.length >= 2) {
      final a = draft.first;
      final b = draft.last;
      final polygon = <Offset>[a, Offset(b.dx, a.dy), b, Offset(a.dx, b.dy)];
      result = Selection(
        polygon: polygon,
        selectedStrokeIndices: hitTestStrokes(polygon),
      );
    } else if (_selection.tool == SelectionTool.lasso && draft.length >= 3) {
      final polygon = List<Offset>.of(draft);
      result = Selection(
        polygon: polygon,
        selectedStrokeIndices: hitTestStrokes(polygon),
      );
    } else {
      result = const Selection();
    }

    _selection.completeDraft(result);
    _host.notifyChanged();
  }

  /// 返回当前图层中与 [polygon] 相交或位于其内部的笔画索引。
  ///
  /// 混合对象选择可复用相同判定，确保笔画选择语义在所有入口一致。
  List<int> hitTestStrokes(List<Offset> polygon) {
    final strokes = _host.currentLayer.strokes;
    final result = <int>[];
    for (var index = 0; index < strokes.length; index++) {
      if (SelectionGeometryService.strokeIntersectsPolygon(
        strokes[index].points,
        polygon,
      )) {
        result.add(index);
      }
    }
    return result;
  }
}
