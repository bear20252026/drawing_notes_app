import 'package:flutter/foundation.dart';

import '../models/document_image_item.dart';
import '../models/layer.dart';
import '../models/shape_item.dart';
import '../models/stroke.dart';
import 'drawing_controller.dart';

/// 撤销/重做历史条目（R5：从 drawing_controller 拆出的命令模式文件）。
///
/// 采用"操作前后图层列表快照"方案：
/// - 每次修改文档前记录 [before]（各图层 strokes 的拷贝），
///   修改完成后记录 [after]；
/// - 撤销 = 用 [before] 覆盖当前图层列表；重做 = 用 [after] 覆盖。
///
/// 优点：不依赖具体操作类型，任何操作（加笔画/合并/删除图层/选区变换）
/// 都能统一支持撤销，逻辑简单、不易出错；缺点是内存占用随笔画数增长，
/// 对本地绘图 App 而言完全可接受。
@immutable
class HistoryEntry {
  const HistoryEntry({required this.before, required this.after});

  final List<Layer> before;
  final List<Layer> after;
}

/// 可逆操作命令（命令模式核心，替代整层快照的内存开销）。
///
/// 高频操作（如新增笔画）实现为"逆操作命令"：撤销时执行逆操作
/// （移除该笔画引用），重做时重新执行（重新加入），零拷贝、省内存。
abstract class DocCommand {
  void undo();
  void redo();
}

/// 快照桥接命令：包装 before/after 整层快照，供低频操作使用。
///
/// 行为与原先的 `_restoreLayers` 完全一致，保证既有功能/测试不变，
/// 同时让撤销栈统一为 [DocCommand] 命令。
class SnapshotCommand extends DocCommand {
  SnapshotCommand(this._controller, this._before, this._after);

  final DrawingController _controller;
  final List<Layer> _before;
  final List<Layer> _after;

  @override
  void undo() => _controller.restoreLayersSnapshot(_before);

  @override
  void redo() => _controller.restoreLayersSnapshot(_after);
}

/// 新增笔画命令（最高频操作）：撤销 = 移除该笔画，重做 = 重新加入。
///
/// 相比整层快照，只需保存笔画的图层索引与对象引用，内存开销极小。
class AddStrokeCommand extends DocCommand {
  AddStrokeCommand(this._controller, this._layerIndex, this._stroke);

  final DrawingController _controller;
  final int _layerIndex;
  final Stroke _stroke;

  @override
  void undo() {
    _controller.document.layers[_layerIndex].strokes.remove(_stroke);
    _controller.touchDocument();
    _controller.afterStrokeUndoRedo(_layerIndex);
  }

  @override
  void redo() {
    _controller.document.layers[_layerIndex].strokes.add(_stroke);
    _controller.touchDocument();
    _controller.afterStrokeUndoRedo(_layerIndex);
  }
}

/// 手绘识别形状的原子替换命令。
///
/// 创建时控制器已将笔画替换为 [shape]；撤销恢复原笔画，重做再次显示形状，
/// 保证识别是可逆的编辑增强，而非不可恢复的数据丢失。
class ReplaceStrokeWithShapeCommand extends DocCommand {
  ReplaceStrokeWithShapeCommand(
    this._controller,
    this._layerIndex,
    this._stroke,
    this._shape,
  );

  final DrawingController _controller;
  final int _layerIndex;
  final Stroke _stroke;
  final PageShapeItem _shape;

  @override
  void undo() => _controller.undoRecognizedShape(_layerIndex, _stroke, _shape);

  @override
  void redo() => _controller.redoRecognizedShape(_layerIndex, _stroke, _shape);
}

/// 独立绘图文档图片的一次原子状态变更。
///
/// [before]/[after] 为独立副本；其中一个为 null 表示图片删除或恢复，因而
/// 导入后编辑、删除以及撤销重做都不会依赖可变 UI 引用。
class DocumentImageStateCommand extends DocCommand {
  DocumentImageStateCommand(
    this._controller, {
    required this.imageId,
    required DocumentImageItem? before,
    required DocumentImageItem? after,
  }) : _before = before?.copy(),
       _after = after?.copy();

  final DrawingController _controller;
  final String imageId;
  final DocumentImageItem? _before;
  final DocumentImageItem? _after;

  @override
  void undo() => _controller.restoreDocumentImageState(imageId, _before);

  @override
  void redo() => _controller.restoreDocumentImageState(imageId, _after);
}

/// 独立绘图文档中形状及其关系的一次原子变更。
///
/// 形状变换会同时影响引用它们的绑定箭头；使用完整形状集合快照可把目标、
/// 受影响箭头、锁定状态和关系降级严格纳入同一历史边界，避免撤销后出现
/// “节点回去了但箭头仍在新位置”的不一致状态。
class DocumentShapesSnapshotCommand extends DocCommand {
  DocumentShapesSnapshotCommand(
    this._controller, {
    required List<PageShapeItem> before,
    required List<PageShapeItem> after,
  }) : _before = before.map((shape) => shape.copy()).toList(growable: false),
       _after = after.map((shape) => shape.copy()).toList(growable: false);

  final DrawingController _controller;
  final List<PageShapeItem> _before;
  final List<PageShapeItem> _after;

  @override
  void undo() => _controller.restoreDocumentShapesSnapshot(_before);

  @override
  void redo() => _controller.restoreDocumentShapesSnapshot(_after);
}

/// 独立绘图文档混合对象的一次完整快照。
///
/// 多选变换会同时修改图层笔画、形状关系图和图片几何。把它们放入同一不可变
/// 快照，才能保证撤销或重做不会出现“笔画已经回退、节点尚未回退”的中间态。
@immutable
class DocumentObjectsSnapshot {
  DocumentObjectsSnapshot({
    required List<Layer> layers,
    required List<PageShapeItem> shapes,
    required List<DocumentImageItem> images,
  }) : layers = layers
           .map(
             (layer) => Layer(
               id: layer.id,
               name: layer.name,
               visible: layer.visible,
               opacity: layer.opacity,
               strokes: List.of(layer.strokes),
             ),
           )
           .toList(growable: false),
       shapes = shapes.map((shape) => shape.copy()).toList(growable: false),
       images = images.map((image) => image.copy()).toList(growable: false);

  final List<Layer> layers;
  final List<PageShapeItem> shapes;
  final List<DocumentImageItem> images;
}

/// 混合对象变换命令：笔画、形状（含绑定箭头）与图片在同一历史边界恢复。
class DocumentObjectsSnapshotCommand extends DocCommand {
  DocumentObjectsSnapshotCommand(
    this._controller, {
    required DocumentObjectsSnapshot before,
    required DocumentObjectsSnapshot after,
  }) : _before = DocumentObjectsSnapshot(
         layers: before.layers,
         shapes: before.shapes,
         images: before.images,
       ),
       _after = DocumentObjectsSnapshot(
         layers: after.layers,
         shapes: after.shapes,
         images: after.images,
       );

  final DrawingController _controller;
  final DocumentObjectsSnapshot _before;
  final DocumentObjectsSnapshot _after;

  @override
  void undo() => _controller.restoreDocumentObjectsSnapshot(_before);

  @override
  void redo() => _controller.restoreDocumentObjectsSnapshot(_after);
}
