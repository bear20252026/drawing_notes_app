import 'dart:ui' show Rect;

import 'package:drawing_notes_app/core/storage/local_id_generator.dart';
import 'package:drawing_notes_app/features/drawing/domain/document.dart';
import 'package:drawing_notes_app/features/drawing/domain/layer.dart';

/// 图层编辑会话与宿主控制器之间的最小协作边界。
///
/// 图层集合、当前图层索引、缓存和历史命令的实际实现仍属于宿主；会话只
/// 负责编排图层变更及其快照边界，不反向依赖 `DrawingController`。
abstract interface class LayerEditingHost {
  DrawingDocument get document;
  Layer get currentLayer;
  int get currentLayerIndex;
  void setCurrentLayerIndexForLayerEdit(int value);

  void pushLayerSnapshot(List<Layer> before, List<Layer> after);
  void addLayerCache(Layer layer);
  void removeLayerCache(String layerId);
  Future<void> invalidateLayer(String layerId, {Rect? region});
  Future<void> rebuildAll();
  void notifyChanged();
}

/// 图层增删、排序、合并、清空及其快照事务的运行时会话。
///
/// 每个结构性变更在会话内生成深拷贝快照，并委托宿主压入同一条可逆
/// 图层命令。会话不拥有历史游标、渲染资源或 UI 通知机制。
class LayerEditingSession {
  LayerEditingSession(this._host);

  final LayerEditingHost _host;
  DrawingDocument get _document => _host.document;

  List<Layer> _snapshotLayers() => <Layer>[
    for (final layer in _document.layers)
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

  // ---------------- 图层操作 ----------------

  /// 新建图层（放在最上层），并自动选中它。
  void addLayer({String? name}) {
    final before = _snapshotLayers();
    final layer = Layer(
      // Q-4 修复（专家审查 2026-08-15）：统一用 LocalIdGenerator——
      // 微秒时间戳在快速连续操作下可能碰撞（批量加图层）。
      id: LocalIdGenerator.next('layer'),
      name: name ?? '图层 ${_document.layers.length + 1}',
    );
    _document.layers.add(layer);
    _document.touch();
    _host.setCurrentLayerIndexForLayerEdit(_document.layers.length - 1);
    _host.addLayerCache(layer);
    _commitSnapshot(before);
    _host.notifyChanged();
  }

  /// 删除指定索引的图层。
  void removeLayer(int index) {
    if (_document.layers.length <= 1) return; // 至少保留一个图层
    final before = _snapshotLayers();
    final removed = _document.layers.removeAt(index);
    _host.removeLayerCache(removed.id);
    _document.touch();
    if (_host.currentLayerIndex >= _document.layers.length) {
      _host.setCurrentLayerIndexForLayerEdit(_document.layers.length - 1);
    }
    _commitSnapshot(before);
    _host.notifyChanged();
  }

  /// 切换图层显隐。
  void toggleLayerVisibility(int index) {
    final before = _snapshotLayers();
    final layer = _document.layers[index];
    layer.visible = !layer.visible;
    _document.touch();
    _commitSnapshot(before);
    _host.notifyChanged();
  }

  /// 设置图层透明度（0~1）。
  void setLayerOpacity(int index, double value) {
    final layer = _document.layers[index];
    if ((layer.opacity - value).abs() < 0.001) return;
    layer.opacity = value.clamp(0.0, 1.0);
    _document.touch();
    _host.notifyChanged();
  }

  /// 上移图层（向更上层移动一格）。
  void moveLayerUp(int index) {
    if (index >= _document.layers.length - 1) return;
    final before = _snapshotLayers();
    final l = _document.layers.removeAt(index);
    _document.layers.insert(index + 1, l);
    _document.touch();
    _host.setCurrentLayerIndexForLayerEdit(index + 1);
    _commitSnapshot(before);
    _host.notifyChanged();
  }

  /// 下移图层（向更下层移动一格）。
  void moveLayerDown(int index) {
    if (index <= 0) return;
    final before = _snapshotLayers();
    final l = _document.layers.removeAt(index);
    _document.layers.insert(index - 1, l);
    _document.touch();
    _host.setCurrentLayerIndexForLayerEdit(index - 1);
    _commitSnapshot(before);
    _host.notifyChanged();
  }

  /// 向下合并图层：把 [index] 层的内容合并到 index-1 层，并删除 [index] 层。
  void mergeLayerDown(int index) {
    if (index <= 0 || index >= _document.layers.length) return;
    final before = _snapshotLayers();
    final upper = _document.layers[index];
    final lower = _document.layers[index - 1];
    // 笔画顺序：底层原有笔画在前，上层笔画追加在后。
    lower.strokes.addAll(upper.strokes);
    _document.layers.removeAt(index);
    _host.removeLayerCache(upper.id);
    _document.touch();
    _host.setCurrentLayerIndexForLayerEdit(index - 1);
    _commitSnapshot(before);
    _host.rebuildAll();
  }

  // ---------------- 画布操作 ----------------

  /// 清空当前图层所有内容。
  void clearCurrentLayer() {
    final before = _snapshotLayers();
    if (_host.currentLayer.strokes.isEmpty) return;
    _host.currentLayer.strokes.clear();
    _document.touch();
    _commitSnapshot(before);
    _host.invalidateLayer(_host.currentLayer.id);
  }

  /// 清空整个文档（所有图层）。
  void clearAll() {
    final before = _snapshotLayers();
    var changed = false;
    for (final l in _document.layers) {
      if (l.strokes.isNotEmpty) {
        l.strokes.clear();
        changed = true;
      }
    }
    if (!changed) return;
    _document.touch();
    _commitSnapshot(before);
    _host.rebuildAll();
  }
}
