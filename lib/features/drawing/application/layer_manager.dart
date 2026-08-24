// layer_manager.dart — 图层操作管理器（从 DrawingController 提取）。
//
// 职责：管理图层的增删改查、可见性、透明度、排序。
// 设计：纯状态容器 + onChange 回调，不依赖 ChangeNotifier。

import 'package:drawing_notes_app/features/drawing/domain/document.dart';
import 'package:drawing_notes_app/features/drawing/domain/layer.dart';

/// 图层操作管理器。
///
/// 从 DrawingController 的图层管理逻辑提取：
/// - currentLayerIndex / currentLayer
/// - 图层增删/排序/可见性/透明度操作
///
/// 使用方式：
/// ```dart
/// final layerManager = LayerManager(
///   document: doc,
///   onChange: () => notifyListeners(),
/// );
/// layerManager.addLayer(name: '新图层');
/// ```
class LayerManager {
  LayerManager({
    required this.document,
    this.onChange,
  });

  /// 文档引用（包含图层列表）。
  final DrawingDocument document;

  /// 状态变更回调（由 DrawingController 注入 notifyListeners）。
  final void Function()? onChange;

  // ─── 状态字段 ───

  int _currentLayerIndex = 0;

  // ─── 只读访问器 ───

  int get currentLayerIndex => _currentLayerIndex;
  Layer get currentLayer => document.layers[_currentLayerIndex];
  List<Layer> get layers => document.layers;
  int get layerCount => document.layers.length;

  // ─── 写入方法 ───

  set currentLayerIndex(int value) {
    if (value >= 0 && value < document.layers.length) {
      _currentLayerIndex = value;
      onChange?.call();
    }
  }

  // ─── 图层操作 ───

  /// 添加新图层。
  Layer addLayer({String? name}) {
    final layer = Layer(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name ?? '图层 ${document.layers.length + 1}',
    );
    document.layers.add(layer);
    _currentLayerIndex = document.layers.length - 1;
    document.touch();
    onChange?.call();
    return layer;
  }

  /// 删除指定索引的图层（至少保留一个图层）。
  bool removeLayer(int index) {
    if (document.layers.length <= 1) return false;
    if (index < 0 || index >= document.layers.length) return false;

    document.layers.removeAt(index);
    if (_currentLayerIndex >= document.layers.length) {
      _currentLayerIndex = document.layers.length - 1;
    }
    document.touch();
    onChange?.call();
    return true;
  }

  /// 删除当前图层。
  bool removeCurrentLayer() => removeLayer(_currentLayerIndex);

  /// 重排序图层（从 fromIndex 移动到 toIndex）。
  bool reorderLayer(int fromIndex, int toIndex) {
    if (fromIndex < 0 || fromIndex >= document.layers.length) return false;
    if (toIndex < 0 || toIndex >= document.layers.length) return false;
    if (fromIndex == toIndex) return false;

    final layer = document.layers.removeAt(fromIndex);
    document.layers.insert(toIndex, layer);

    // 更新当前图层索引
    if (_currentLayerIndex == fromIndex) {
      _currentLayerIndex = toIndex;
    } else if (fromIndex < _currentLayerIndex && toIndex >= _currentLayerIndex) {
      _currentLayerIndex--;
    } else if (fromIndex > _currentLayerIndex && toIndex <= _currentLayerIndex) {
      _currentLayerIndex++;
    }

    document.touch();
    onChange?.call();
    return true;
  }

  /// 向上移动当前图层。
  bool moveCurrentLayerUp() {
    if (_currentLayerIndex >= document.layers.length - 1) return false;
    return reorderLayer(_currentLayerIndex, _currentLayerIndex + 1);
  }

  /// 向下移动当前图层。
  bool moveCurrentLayerDown() {
    if (_currentLayerIndex <= 0) return false;
    return reorderLayer(_currentLayerIndex, _currentLayerIndex - 1);
  }

  /// 切换图层可见性。
  void toggleVisibility(int index) {
    if (index < 0 || index >= document.layers.length) return;
    document.layers[index].visible = !document.layers[index].visible;
    document.touch();
    onChange?.call();
  }

  /// 设置图层透明度。
  void setOpacity(int index, double opacity) {
    if (index < 0 || index >= document.layers.length) return;
    document.layers[index].opacity = opacity.clamp(0.0, 1.0);
    document.touch();
    onChange?.call();
  }

  /// 重命名图层。
  void renameLayer(int index, String name) {
    if (index < 0 || index >= document.layers.length) return;
    document.layers[index].name = name;
    document.touch();
    onChange?.call();
  }

  /// 合并当前图层到下方图层。
  bool mergeCurrentLayerDown() {
    if (_currentLayerIndex <= 0) return false;

    final upper = document.layers[_currentLayerIndex];
    final lower = document.layers[_currentLayerIndex - 1];

    // 将上层笔画追加到下层
    lower.strokes.addAll(upper.strokes);

    // 移除上层
    document.layers.removeAt(_currentLayerIndex);
    _currentLayerIndex--;

    document.touch();
    onChange?.call();
    return true;
  }

  /// 扁平化所有图层（合并为一个图层）。
  void flattenAll() {
    if (document.layers.length <= 1) return;

    final merged = Layer(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: '合并图层',
    );

    for (final layer in document.layers) {
      merged.strokes.addAll(layer.strokes);
    }

    document.layers
      ..clear()
      ..add(merged);
    _currentLayerIndex = 0;

    document.touch();
    onChange?.call();
  }

  /// 同步图层状态（从外部状态恢复）。
  void syncFromExternal({
    required int currentLayerIndex,
    required int layerCount,
  }) {
    _currentLayerIndex = currentLayerIndex.clamp(0, document.layers.length - 1);
  }
}
