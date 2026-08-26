// editor_v2——DrawingAdapter（批次 E——2026-08-21）。
//
// V1 → V2 桥接适配器（迁移期——旧编辑器功能桥接到 V2 ViewModel）。
// 临时：待 Editor V2 完整实现后删除。
library;

import 'package:editor_core/editor_core.dart';

/// 旧 V1 DrawingController → V2 EditorV2ViewModel 桥接（迁移期）。
///
/// 用途：在 Editor V2 完整实现前，将旧编辑器的绘制操作桥接到 V2 命令模式。
/// 迁移完成后删除。
class DrawingAdapter {
  DrawingAdapter(this._reducer);

  final DocumentReducer _reducer;

  /// 旧绘制操作 → V2 AddStrokeCommand（V1/V2 迁移阶段1——2026-08-24）。
  ///
  /// [color] 格式：#RRGGBB；[strokeWidth] 默认 2.0。
  void bridgeAddStroke(
    String layerId,
    List<Point> points, {
    String color = '#000000',
    double strokeWidth = 2.0,
  }) {
    final stroke = LineItem(
      id: 'bridge-${DateTime.now().millisecondsSinceEpoch}',
      points: points,
      strokeWidth: strokeWidth,
      color: color,
    );
    _reducer.execute(AddStrokeCommand(layerId: layerId, stroke: stroke));
  }

  /// 旧形状操作 → V2 CreateShapeCommand。
  void bridgeCreateShape(
    String layerId,
    String type,
    double x,
    double y,
    double w,
    double h, {
    String strokeColor = '#000000',
    String fillColor = '#CCCCCC',
  }) {
    final shape = ShapeItem(
      id: 'bridge-${DateTime.now().millisecondsSinceEpoch}',
      type: type,
      x: x,
      y: y,
      width: w,
      height: h,
      strokeColor: strokeColor,
      fillColor: fillColor,
    );
    _reducer.execute(CreateShapeCommand(layerId: layerId, shape: shape));
  }

  /// 获取当前文档状态（V2 不可变快照）。
  DocumentV2 get currentDocument => _reducer.current;
}
