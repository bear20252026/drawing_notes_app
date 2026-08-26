// core/abstractions — 笔画几何缓存抽象接口
// 遵循 Clean Architecture：定义抽象契约，实现由 Infrastructure 层提供

import 'dart:ui';

import '../../../features/drawing/domain/stroke.dart';

/// 笔画几何缓存抽象接口
///
/// 缓存笔画的几何计算结果，避免重复计算
abstract class StrokeGeometryCache {
  /// 获取笔画的边界矩形
  Rect getBounds(Stroke stroke);

  /// 获取笔画的路径
  Path getPath(Stroke stroke);

  /// 清除缓存
  void clear();

  /// 移除特定笔画的缓存
  void remove(Stroke stroke);
}
