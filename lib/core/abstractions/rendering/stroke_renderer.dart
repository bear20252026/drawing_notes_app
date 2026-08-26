// core/abstractions — 笔画渲染抽象接口
// 遵循 Clean Architecture：定义抽象契约，实现由 Infrastructure 层提供

import 'dart:ui';

import '../../../features/drawing/domain/stroke.dart';

/// 笔画渲染器抽象接口
///
/// 将原始输入点转为连续、填充式的压感笔触轮廓。
/// 使用 perfect_freehand 的轮廓算法，把完整点列生成单一封闭路径，因此
/// 粗笔、快速转向与压感变化都保持连续的触笔感。
abstract class StrokeRenderer {
  /// 绘制单个笔画到画布
  void drawStroke(Canvas canvas, Stroke stroke);

  /// 获取笔画的轮廓路径
  Path outlinePath(Stroke stroke);

  /// 获取笔画的边界矩形
  Rect bounds(Stroke stroke);
}
