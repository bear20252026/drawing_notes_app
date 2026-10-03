import 'package:flutter/foundation.dart';

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/document_image_item.dart';
import 'package:drawing_notes_app/core/canvas_model/layer.dart';
import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';
import 'package:drawing_notes_app/core/canvas_model/stroke.dart';
import 'package:drawing_notes_app/features/drawing/application/doc_command_context.dart';

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
  SnapshotCommand(this._context, this._before, this._after);

  final DocCommandContext _context;
  final List<Layer> _before;
  final List<Layer> _after;

  @override
  void undo() => _context.restoreLayersSnapshot(_before);

  @override
  void redo() => _context.restoreLayersSnapshot(_after);
}

/// 新增笔画命令（最高频操作）：撤销 = 移除该笔画，重做 = 重新加入。
///
/// 相比整层快照，只需保存笔画的图层索引与对象引用，内存开销极小。
class AddStrokeCommand extends DocCommand {
  AddStrokeCommand(this._context, this._layerIndex, this._stroke);

  final DocCommandContext _context;
  final int _layerIndex;
  final Stroke _stroke;

  @override
  void undo() {
    _context.document.layers[_layerIndex].strokes.remove(_stroke);
    _context.touchDocument();
    _context.afterStrokeUndoRedo(_layerIndex);
  }

  @override
  void redo() {
    _context.document.layers[_layerIndex].strokes.add(_stroke);
    _context.touchDocument();
    _context.afterStrokeUndoRedo(_layerIndex);
  }
}

/// 对象橡皮擦的增量命令（对齐 excalidraw StoreDelta 只存变更的设计）。
///
/// 一次擦除手势可能删除多条笔画和/或标准形状；相比原先的整层快照
/// [SnapshotCommand]（深拷贝全部图层），这里只保存被删笔画的
/// 图层索引、原位置与对象引用，撤销/重做零整层拷贝、内存开销极小。
/// 形状擦除（问题3：标准直线/图案可被橡皮擦除）同样按引用记录。
class EraseStrokesCommand extends DocCommand {
  EraseStrokesCommand(
    this._context,
    this._removed, {
    this.removedShapeEntries = const [],
  });

  final DocCommandContext _context;

  /// 被删笔画按删除顺序记录：(图层索引, 手势起始原始序号, 笔画对象)。
  final List<({int layerIndex, int index, Stroke stroke})> _removed;

  /// 本次手势一并删除的标准形状：(手势起始原始序号, 原实例)（引用快照）。
  ///
  /// 2026-10-03 复核：原先只记实例、撤销时 `copy()` 追加到末尾——undo 放回的是
  /// 新副本，redo 按 identity `remove` 移不掉 ⇒ 重做无效；再次 undo 又追加
  /// 一个**同 id** 形状（破坏箭头 `firstOrNull` 绑定与按 id 选择，并原样存盘），
  /// 且末尾追加丢失原 z 序。现按原实例 + 原序号精确插回，redo 按 identity 移除。
  final List<({int index, PageShapeItem shape})> removedShapeEntries;

  /// 被删形状实例（既有只读视图，与 [removedShapeEntries] 同序）。
  List<PageShapeItem> get removedShapes =>
      removedShapeEntries.map((entry) => entry.shape).toList(growable: false);

  @override
  void undo() {
    // 按 (图层, 原始序号) 升序插回原处：存活笔画相对序不变、序号更小的已先
    // 插回，故逐次 insert(entry.index) 恰好还原手势起始次序。
    final byLayer = <int, List<({int index, Stroke stroke})>>{};
    for (final entry in _removed) {
      byLayer.putIfAbsent(entry.layerIndex, () => []).add((
        index: entry.index,
        stroke: entry.stroke,
      ));
    }
    for (final layerIndex in byLayer.keys) {
      final entries = byLayer[layerIndex]!
        ..sort((a, b) => a.index.compareTo(b.index));
      final strokes = _context.document.layers[layerIndex].strokes;
      for (final entry in entries) {
        strokes.insert(entry.index, entry.stroke);
      }
      _context.afterStrokeUndoRedo(layerIndex);
    }
    // 恢复被擦除的标准形状：按原始序号插回原实例（同笔画，形状也保持原 z 序）。
    if (removedShapeEntries.isNotEmpty) {
      final shapes = _context.document.shapes;
      final entries = <({int index, PageShapeItem shape})>[
        ...removedShapeEntries,
      ]..sort((a, b) => a.index.compareTo(b.index));
      for (final entry in entries) {
        shapes.insert(entry.index.clamp(0, shapes.length), entry.shape);
      }
    }
    _context.touchDocument();
  }

  @override
  void redo() {
    // 按引用移除即可，无需关心原位置（与擦除时行为一致）。
    final layers = _context.document.layers;
    final changedLayers = <int>{};
    for (final entry in _removed) {
      layers[entry.layerIndex].strokes.remove(entry.stroke);
      changedLayers.add(entry.layerIndex);
    }
    for (final layerIndex in changedLayers) {
      _context.afterStrokeUndoRedo(layerIndex);
    }
    // 再次移除被擦除的标准形状：undo 放回的就是这些实例，identity 移除成立。
    for (final entry in removedShapeEntries) {
      _context.document.shapes.remove(entry.shape);
    }
    _context.touchDocument();
  }
}

/// 选区变换的窄命令（P-05，审计 2026-09-27）。
///
/// 一次变换手势（拖拽平移/缩放/旋转）只把选中笔画的点列替换为新
/// [Stroke] 对象，图层笔画数不变。此前经 [SnapshotCommand] 提交
/// 全图层 before/after 双份快照——开销 O(全部图层全部笔画) 引用拷贝，
/// 且撤销栈（容量 60）里每条变换都常驻两份。这里只记录受影响笔画的
/// (位置, 变换前, 变换后) 三元组，内存 O(选中笔画数)。
///
/// 按索引直接覆写的 LIFO 正确性：命令栈按序回放，执行到本命令时
/// 文档必处于本命令提交时的状态（栈中上方命令已全部忠实还原），
/// 三元组索引即可精确定位——与 [EraseStrokesCommand] 记录原位置插回
/// 是同一假设，中删/层操作等快照命令还原的是完整图层列表，同样成立。
class TransformStrokesCommand extends DocCommand {
  TransformStrokesCommand(this._context, this._layerIndex, this._pairs);

  final DocCommandContext _context;
  final int _layerIndex;

  /// (图层内位置, 变换前对象, 变换后对象)，按位置升序、位置互异。
  final List<({int index, Stroke before, Stroke after})> _pairs;

  @override
  void undo() {
    final strokes = _context.document.layers[_layerIndex].strokes;
    for (final pair in _pairs) {
      strokes[pair.index] = pair.before;
    }
    _context.afterStrokeUndoRedo(_layerIndex);
    _context.touchDocument();
  }

  @override
  void redo() {
    final strokes = _context.document.layers[_layerIndex].strokes;
    for (final pair in _pairs) {
      strokes[pair.index] = pair.after;
    }
    _context.afterStrokeUndoRedo(_layerIndex);
    _context.touchDocument();
  }
}

/// 图层显隐切换的窄命令（P-05 同款拆分，2026-10-03）。
///
/// 此前显隐切换经 [SnapshotCommand] 提交全图层列表双份快照；显隐只是
/// 图层对象上的一个布尔翻转（合成期参数，位图缓存不变），窄命令只记
/// (索引, 前, 后) 三个值。
class LayerVisibilityCommand extends DocCommand {
  LayerVisibilityCommand(this._context, this._layerIndex, this._before, this._after);

  final DocCommandContext _context;
  final int _layerIndex;
  final bool _before;
  final bool _after;

  @override
  void undo() {
    _context.document.layers[_layerIndex].visible = _before;
    _context.touchDocument();
    _context.afterLayerUndoRedo();
  }

  @override
  void redo() {
    _context.document.layers[_layerIndex].visible = _after;
    _context.touchDocument();
    _context.afterLayerUndoRedo();
  }
}

/// 图层相邻换位的窄命令（图层面板的上移/下移）。
///
/// 换位不改图层集合成员（列表长度不变、图层对象引用不变），只记
/// (from, to) 两个索引；undo/redo 互为反向 removeAt+insert。
class LayerReorderCommand extends DocCommand {
  LayerReorderCommand(this._context, this._from, this._to)
    : assert(_from != _to);

  final DocCommandContext _context;
  final int _from;
  final int _to;

  @override
  void undo() {
    final l = _context.document.layers.removeAt(_to);
    _context.document.layers.insert(_from, l);
    _context.touchDocument();
    _context.afterLayerUndoRedo();
  }

  @override
  void redo() {
    final l = _context.document.layers.removeAt(_from);
    _context.document.layers.insert(_to, l);
    _context.touchDocument();
    _context.afterLayerUndoRedo();
  }
}

/// 手绘识别形状的原子替换命令。
///
/// 创建时控制器已将笔画替换为 [shape]；撤销恢复原笔画，重做再次显示形状，
/// 保证识别是可逆的编辑增强，而非不可恢复的数据丢失。
class ReplaceStrokeWithShapeCommand extends DocCommand {
  ReplaceStrokeWithShapeCommand(
    this._context,
    this._layerIndex,
    this._stroke,
    this._shape,
  );

  final DocCommandContext _context;
  final int _layerIndex;
  final Stroke _stroke;
  final PageShapeItem _shape;

  @override
  void undo() => _context.undoRecognizedShape(_layerIndex, _stroke, _shape);

  @override
  void redo() => _context.redoRecognizedShape(_layerIndex, _stroke, _shape);
}

/// 独立绘图文档图片的一次原子状态变更。
///
/// [before]/[after] 为独立副本；其中一个为 null 表示图片删除或恢复，因而
/// 导入后编辑、删除以及撤销重做都不会依赖可变 UI 引用。
class DocumentImageStateCommand extends DocCommand {
  DocumentImageStateCommand({
    required this.restoreImageState,

    required this.imageId,
    required DocumentImageItem? before,
    required DocumentImageItem? after,
  }) : _before = before?.copy(),
       _after = after?.copy();

  final void Function(String imageId, DocumentImageItem? snapshot)
  restoreImageState;

  final String imageId;
  final DocumentImageItem? _before;
  final DocumentImageItem? _after;

  @override
  void undo() => restoreImageState(imageId, _before);

  @override
  void redo() => restoreImageState(imageId, _after);
}

/// 独立绘图文档中形状及其关系的一次原子变更。
///
/// 形状变换会同时影响引用它们的绑定箭头；使用完整形状集合快照可把目标、
/// 受影响箭头、锁定状态和关系降级严格纳入同一历史边界，避免撤销后出现
/// “节点回去了但箭头仍在新位置”的不一致状态。
class DocumentShapesSnapshotCommand extends DocCommand {
  DocumentShapesSnapshotCommand({
    required this.restoreShapesSnapshot,
    required List<PageShapeItem> before,
    required List<PageShapeItem> after,
  }) : _before = before.map((shape) => shape.copy()).toList(growable: false),
       _after = after.map((shape) => shape.copy()).toList(growable: false);

  final void Function(List<PageShapeItem> snapshot) restoreShapesSnapshot;
  final List<PageShapeItem> _before;
  final List<PageShapeItem> _after;

  @override
  void undo() => restoreShapesSnapshot(_before);

  @override
  void redo() => restoreShapesSnapshot(_after);
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

/// 混合对象快照的无状态构造、恢复和比较服务。
///
/// 该服务只处理领域对象集合，不持有编辑会话、选择、命令栈、缓存或 UI。
/// `DocumentObjectEditingSession` 继续在恢复后修正选择、触碰文档及协调渲染副作用。
class DocumentObjectSnapshotService {
  const DocumentObjectSnapshotService._();

  /// 以当前文档对象建立独立快照，后续原对象变化不会污染返回值。
  static DocumentObjectsSnapshot capture(DrawingDocument document) =>
      DocumentObjectsSnapshot(
        layers: document.layers,
        shapes: document.shapes,
        images: document.imageItems,
      );

  /// 将 [snapshot] 的图层、形状与图片以深拷贝方式完整写回 [document]。
  static void restore(
    DrawingDocument document,
    DocumentObjectsSnapshot snapshot,
  ) {
    document.layers
      ..clear()
      ..addAll(
        snapshot.layers.map(
          (layer) => Layer(
            id: layer.id,
            name: layer.name,
            visible: layer.visible,
            opacity: layer.opacity,
            strokes: List<Stroke>.of(layer.strokes),
          ),
        ),
      );
    document.shapes
      ..clear()
      ..addAll(snapshot.shapes.map((shape) => shape.copy()));
    document.imageItems
      ..clear()
      ..addAll(snapshot.images.map((image) => image.copy()));
  }

  /// 当恢复后的图层数缩短时，返回应收敛到的当前图层索引；无需修正则返回 null。
  static int? correctedCurrentLayerIndex({
    required int currentLayerIndex,
    required int restoredLayerCount,
  }) => currentLayerIndex >= restoredLayerCount ? restoredLayerCount - 1 : null;

  /// 判断两个混合对象快照的持久化内容是否完全一致。
  static bool isSame(DocumentObjectsSnapshot a, DocumentObjectsSnapshot b) {
    if (a.layers.length != b.layers.length ||
        a.shapes.length != b.shapes.length ||
        a.images.length != b.images.length) {
      return false;
    }
    for (var index = 0; index < a.layers.length; index++) {
      if (a.layers[index].toJson().toString() !=
          b.layers[index].toJson().toString()) {
        return false;
      }
    }
    for (var index = 0; index < a.shapes.length; index++) {
      if (a.shapes[index].toJson().toString() !=
          b.shapes[index].toJson().toString()) {
        return false;
      }
    }
    for (var index = 0; index < a.images.length; index++) {
      if (a.images[index].toJson().toString() !=
          b.images[index].toJson().toString()) {
        return false;
      }
    }
    return true;
  }
}

/// 混合对象变换命令：笔画、形状（含绑定箭头）与图片在同一历史边界恢复。
class DocumentObjectsSnapshotCommand extends DocCommand {
  DocumentObjectsSnapshotCommand({
    required this.restoreObjectsSnapshot,

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

  final void Function(DocumentObjectsSnapshot snapshot) restoreObjectsSnapshot;
  final DocumentObjectsSnapshot _before;
  final DocumentObjectsSnapshot _after;

  @override
  void undo() => restoreObjectsSnapshot(_before);

  @override
  void redo() => restoreObjectsSnapshot(_after);
}
