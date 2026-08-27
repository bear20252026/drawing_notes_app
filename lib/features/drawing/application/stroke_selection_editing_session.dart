import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:drawing_notes_app/features/drawing/application/drawing_selection_session.dart';
import 'package:drawing_notes_app/features/drawing/application/selection_geometry_service.dart';
import 'package:drawing_notes_app/features/drawing/domain/document.dart';
import 'package:drawing_notes_app/features/drawing/domain/layer.dart';
import 'package:drawing_notes_app/features/drawing/domain/stroke.dart';

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
