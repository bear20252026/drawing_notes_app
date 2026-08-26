import 'dart:ui';

import '../domain/shape_item.dart';
import '../domain/stroke.dart';
import '../../../core/abstractions/rendering/shape_renderer.dart';
import '../../../core/abstractions/rendering/stroke_renderer.dart';

/// 空间索引：矩形分区（借鉴 Excalidraw spatial index 优化元素选择和渲染）。
///
/// 将画布划分为固定大小的网格（默认 64x64 像素），每个网格存储该区域内的
/// 元素 ID 列表。查找操作从 O(N) 降低到 O(K)，其中 K 为查询区域内的元素数。
///
/// 使用场景：
/// 1. 元素选择（点击/框选）：快速定位可能被选中的元素
/// 2. 渲染优化：只渲染视口内的元素
/// 3. 碰撞检测：快速排除不可能相交的元素
class SpatialIndex {
  SpatialIndex({this.cellSize = 64.0});

  /// 网格单元大小（逻辑像素）。
  final double cellSize;

  /// 网格到元素 ID 的映射。
  final Map<int, Set<String>> _grid = {};

  /// 元素 ID 到边界框的缓存。
  final Map<String, Rect> _boundsCache = {};

  /// 调试用：获取网格到元素 ID 映射的只读副本。
  Map<int, Set<String>> get debugGrid => Map.unmodifiable(_grid);

  /// 清空空间索引。
  void clear() {
    _grid.clear();
    _boundsCache.clear();
  }

  /// 插入元素到空间索引。
  void insert(String id, Rect bounds) {
    _boundsCache[id] = bounds;
    final cells = _cellsForRect(bounds);
    for (final cell in cells) {
      _grid.putIfAbsent(cell, () => {}).add(id);
    }
  }

  /// 从空间索引移除元素。
  void remove(String id) {
    final bounds = _boundsCache.remove(id);
    if (bounds == null) return;
    final cells = _cellsForRect(bounds);
    for (final cell in cells) {
      _grid[cell]?.remove(id);
      if (_grid[cell]?.isEmpty ?? false) {
        _grid.remove(cell);
      }
    }
  }

  /// 查询与给定矩形相交的所有元素 ID。
  Set<String> query(Rect rect) {
    final result = <String>{};
    final cells = _cellsForRect(rect);
    for (final cell in cells) {
      final ids = _grid[cell];
      if (ids != null) {
        for (final id in ids) {
          final cachedBounds = _boundsCache[id];
          if (cachedBounds != null && cachedBounds.overlaps(rect)) {
            result.add(id);
          }
        }
      }
    }
    return result;
  }

  /// 查询包含给定点的所有元素 ID。
  Set<String> queryPoint(Offset point) {
    return query(Rect.fromCenter(
      center: point,
      width: 1,
      height: 1,
    ));
  }

  /// 获取指定元素的边界框（从缓存）。
  Rect? boundsFor(String id) => _boundsCache[id];

  /// 计算矩形覆盖的所有网格单元。
  Set<int> _cellsForRect(Rect rect) {
    final cells = <int>{};
    final minCol = (rect.left / cellSize).floor();
    final maxCol = (rect.right / cellSize).floor();
    final minRow = (rect.top / cellSize).floor();
    final maxRow = (rect.bottom / cellSize).floor();

    for (var row = minRow; row <= maxRow; row++) {
      for (var col = minCol; col <= maxCol; col++) {
        cells.add(_cellKey(col, row));
      }
    }
    return cells;
  }

  /// 计算网格单元的唯一键。
  int _cellKey(int col, int row) {
    // 使用 Cantor pairing function 将二维坐标映射到一维
    // 处理负数：偏移到正数范围
    final c = col >= 0 ? col * 2 : -col * 2 - 1;
    final r = row >= 0 ? row * 2 : -row * 2 - 1;
    return c + r;
  }
}

/// 元素边界计算辅助类。
class ElementBounds {
  /// 计算笔画的边界框。
  static Rect? strokeBounds(Stroke stroke) {
    return StrokeRenderer.strokeBounds(stroke);
  }

  /// 计算形状的边界框。
  static Rect shapeBounds(PageShapeItem shape) {
    return ShapeRenderer.bounds(shape);
  }

  /// 批量更新空间索引中的所有元素。
  static void updateAll(
    SpatialIndex index, {
    required List<Stroke> strokes,
    required List<PageShapeItem> shapes,
    String? layerPrefix,
  }) {
    index.clear();

    // 插入所有笔画
    for (var i = 0; i < strokes.length; i++) {
      final stroke = strokes[i];
      final id = '${layerPrefix ?? ''}stroke_$i';
      final bounds = strokeBounds(stroke);
      if (bounds != null) {
        index.insert(id, bounds);
      }
    }

    // 插入所有形状
    for (var i = 0; i < shapes.length; i++) {
      final shape = shapes[i];
      final id = '${layerPrefix ?? ''}shape_${shape.id}';
      final bounds = shapeBounds(shape);
      index.insert(id, bounds);
    }
  }
}
