import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:drawing_notes_app/features/drawing/application/selection_geometry_service.dart';
import 'package:drawing_notes_app/features/drawing/domain/document.dart';
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

/// 笔画选区编辑会话与宿主控制器之间的最小协作边界。
///
/// 会话仅编排已选笔画的变换、剪贴板与图层快照；文档、选区短生命周期
/// 状态、历史命令、缓存和 UI 通知的实际所有权仍保留在各自宿主协作者。
abstract interface class StrokeSelectionEditingHost {
  DrawingDocument get document;
  Layer get currentLayer;
  DrawingSelectionSession get selectionSession;

  void pushLayerSnapshot(List<Layer> before, List<Layer> after);
  Future<void> invalidateLayer(String layerId);
  void notifyChanged();
}

/// 已选笔画的变换、复制、粘贴、删除及其撤销快照编排。
///
/// 连续手势只保存首次变换前的快照；在 [endTransform] 时统一提交一条历史
/// 记录，从而保持拖动和滑块操作的单步撤销语义。
class StrokeSelectionEditingSession {
  StrokeSelectionEditingSession(this._host);

  final StrokeSelectionEditingHost _host;

  DrawingSelectionSession get _selection => _host.selectionSession;

  bool get hasSelectedStrokes => _selection.hasSelectedStrokes;

  List<Layer> _snapshotLayers() => <Layer>[
    for (final layer in _host.document.layers)
      Layer(
        id: layer.id,
        name: layer.name,
        visible: layer.visible,
        opacity: layer.opacity,
        strokes: List.of(layer.strokes),
      ),
  ];

  void _commitSnapshot(List<Layer> before) {
    _host.pushLayerSnapshot(before, _snapshotLayers());
  }

  /// 平移选中的笔画（拖拽移动）。
  void moveSelectedStrokes(Offset delta) {
    if (!hasSelectedStrokes) return;
    _ensureTransformBefore();
    _transformSelected((point) => point + delta);
  }

  /// 缩放选中的笔画（围绕笔画实际外接框中心）。
  void scaleSelectedStrokes(double factor) {
    if (!hasSelectedStrokes) return;
    _ensureTransformBefore();
    final center = _selectedStrokeCenter();
    _transformSelected(
      (point) => SelectionGeometryService.scalePoint(point, center, factor),
    );
  }

  /// 旋转选中的笔画（围绕笔画实际外接框中心，角度为弧度）。
  void rotateSelectedStrokes(double radians) {
    if (!hasSelectedStrokes) return;
    _ensureTransformBefore();
    final center = _selectedStrokeCenter();
    _transformSelected(
      (point) => SelectionGeometryService.rotatePoint(
        point,
        center,
        math.cos(radians),
        math.sin(radians),
      ),
    );
  }

  Offset _selectedStrokeCenter() {
    if (!_selection.centerDirty && _selection.centerCache != null) {
      return _selection.centerCache!;
    }
    final strokes = <Stroke>[
      for (final index in _selection.selection.selectedStrokeIndices)
        _host.currentLayer.strokes[index],
    ];
    final center =
        SelectionGeometryService.centerOfStrokes(strokes) ??
        _selection.selection.center;
    return _selection.cacheCenter(center);
  }

  void _ensureTransformBefore() {
    _selection.transformBefore ??= _snapshotLayers();
  }

  void _transformSelected(Offset Function(Offset) transform) {
    final indices = _selection.selection.selectedStrokeIndices;
    final strokes = _host.currentLayer.strokes;
    for (final index in indices.reversed) {
      final old = strokes[index];
      final points = <StrokePoint>[
        for (final point in old.points)
          () {
            final transformed = transform(point.offset);
            return StrokePoint(transformed.dx, transformed.dy, point.pressure);
          }(),
      ];
      strokes[index] = Stroke(
        points: points,
        color: old.color,
        width: old.width,
        type: old.type,
        opacity: old.opacity,
      );
    }
    _host.document.touch();
    _host.invalidateLayer(_host.currentLayer.id);
    _host.notifyChanged();
  }

  /// 在连续拖动或滑块操作结束时提交一条可逆图层快照。
  void endTransform() {
    final before = _selection.transformBefore;
    if (before == null) return;
    _selection.clearTransformBefore();
    _commitSnapshot(before);
  }

  /// 删除选中的笔画。
  void deleteSelectedStrokes() {
    if (!hasSelectedStrokes) return;
    final before = _snapshotLayers();
    final strokes = _host.currentLayer.strokes;
    for (final index in _selection.selection.selectedStrokeIndices.reversed) {
      strokes.removeAt(index);
    }
    _host.document.touch();
    _selection.clearSelection();
    _commitSnapshot(before);
    _host.invalidateLayer(_host.currentLayer.id);
    _host.notifyChanged();
  }

  /// 复制选中的笔画到会话剪贴板（不修改图层）。
  void copySelectedStrokes() {
    if (!hasSelectedStrokes) return;
    _selection.clipboard = <Stroke>[
      for (final index in _selection.selection.selectedStrokeIndices)
        _copyStroke(_host.currentLayer.strokes[index]),
    ];
  }

  /// 将剪贴板笔画粘贴到当前图层并固定偏移，避免完全覆盖原件。
  void pasteClipboard() {
    final clipboard = _selection.clipboard;
    if (clipboard == null || clipboard.isEmpty) return;
    final before = _snapshotLayers();
    const delta = Offset(20, 20);
    for (final stroke in clipboard) {
      _host.currentLayer.strokes.add(_offsetStroke(stroke, delta));
    }
    _host.document.touch();
    _selection.clearSelection();
    _commitSnapshot(before);
    _host.invalidateLayer(_host.currentLayer.id);
    _host.notifyChanged();
  }

  Stroke _copyStroke(Stroke stroke) => Stroke(
    points: <StrokePoint>[
      for (final point in stroke.points)
        StrokePoint(point.x, point.y, point.pressure),
    ],
    color: stroke.color,
    width: stroke.width,
    type: stroke.type,
    opacity: stroke.opacity,
  );

  Stroke _offsetStroke(Stroke stroke, Offset delta) => Stroke(
    points: <StrokePoint>[
      for (final point in stroke.points)
        StrokePoint(point.x + delta.dx, point.y + delta.dy, point.pressure),
    ],
    color: stroke.color,
    width: stroke.width,
    type: stroke.type,
    opacity: stroke.opacity,
  );
}
