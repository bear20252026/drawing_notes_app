// core/abstractions — 图层合成抽象接口
// 遵循 Clean Architecture：定义抽象契约，实现由 Infrastructure 层提供

import 'dart:ui';

/// 图层合成器抽象接口
///
/// 负责将多个图层合成为单一图像
abstract class LayerCompositor {
  /// 合成图层为单一图像
  Future<Image> composeLayers(List<dynamic> layers, Size size);

  /// 合成图层为 Canvas
  void composeToCanvas(Canvas canvas, List<dynamic> layers, Size size);
}
