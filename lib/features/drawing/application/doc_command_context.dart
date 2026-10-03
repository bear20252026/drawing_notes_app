import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/layer.dart';
import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';
import 'package:drawing_notes_app/core/canvas_model/stroke.dart';

/// 历史命令执行时需要的最小状态与副作用边界。
///
/// [DocCommand] 依赖此接口而不是 [DrawingController]，因此命令可以在不引入
/// 控制器实现的前提下恢复图层、更新文档脏状态并触发局部缓存刷新。具体的
/// 选择状态、渲染缓存和通知策略仍由控制器实现，避免命令层承担 UI 协调职责。
abstract interface class DocCommandContext {
  DrawingDocument get document;

  void restoreLayersSnapshot(List<Layer> snapshot);

  void touchDocument();

  /// 图层级窄命令（显隐/换位）undo/redo 后的收尾：位图缓存与图层对象
  /// 不变（可见性/顺序是合成期参数），只需钳制当前图层索引并通知。
  void afterLayerUndoRedo();

  Future<void> afterStrokeUndoRedo(int layerIndex);

  void undoRecognizedShape(int layerIndex, Stroke stroke, PageShapeItem shape);

  void redoRecognizedShape(int layerIndex, Stroke stroke, PageShapeItem shape);
}
