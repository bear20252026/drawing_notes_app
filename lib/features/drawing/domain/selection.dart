import 'value_objects/geometry.dart';

/// 选区工具类型（Phase 4）。
///
/// - [none]：未启用选区工具（正常绘制）
/// - [rect]：矩形选区（拖拽框选一个矩形区域）
/// - [lasso]：套索选区（自由绘制闭合多边形区域）
enum SelectionTool { none, rect, lasso }

/// 选区模型：多边形 + 命中结果。
///
/// 设计说明（矢量笔画级选区）：
/// 本 App 的图层内容为矢量笔画（[Stroke] 列表），
/// 因此选区命中检测作用于"笔画"而非像素：
/// 只要某条笔画上有任意采样点落在选区多边形内，该笔画即被选中。
/// 选中后可对整条笔画做几何变换（移动/缩放/旋转），
/// 这与 Procreate/CSP 的矢量图层行为一致，且天然支持无损缩放与撤销。
class Selection {
  const Selection({
    this.polygon = const [],
    this.selectedStrokeIndices = const [],
  });

  /// 选区多边形顶点（画布坐标）。
  /// 矩形选区为 4 个顶点；套索选区为自由点列。
  final List<FOffset> polygon;

  /// 当前图层中被命中的笔画索引列表（升序）。
  final List<int> selectedStrokeIndices;

  bool get isEmpty => polygon.length < 3;

  /// 选区中心点（多边形包围盒中心），作为缩放/旋转的基准点。
  FOffset get center {
    if (polygon.isEmpty) return FOffset.zero;
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final p in polygon) {
      if (p.x < minX) minX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.x > maxX) maxX = p.x;
      if (p.y > maxY) maxY = p.y;
    }
    return FOffset((minX + maxX) / 2, (minY + maxY) / 2);
  }
}
