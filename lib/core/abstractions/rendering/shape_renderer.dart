// core/abstractions — 形状渲染抽象接口
// 遵循 Clean Architecture：定义抽象契约，实现由 Infrastructure 层提供

import 'dart:ui';

import '../../../features/drawing/domain/shape_item.dart';

/// 无 UI 依赖的几何形状渲染器抽象接口
///
/// 屏幕画布与文件导出共用本实现，防止出现"编辑器里看得到，导出后丢失"的
/// 伪功能。所有坐标均为逻辑画布坐标。
abstract class ShapeRenderer {
  /// 计算形状的边界矩形
  Rect bounds(PageShapeItem shape);

  /// 在画布上绘制文档形状
  void drawDocumentShape(Canvas canvas, PageShapeItem shape);

  /// 在元素自身的 0,0 → size 坐标系中绘制形状
  void drawLocal(Canvas canvas, PageShapeItem shape, Size size);
}
