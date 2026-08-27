import 'dart:ui' show Offset;

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
