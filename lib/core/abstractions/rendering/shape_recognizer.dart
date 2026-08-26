// core/abstractions — 形状识别抽象接口
// 遵循 Clean Architecture：定义抽象契约，实现由 Infrastructure 层提供

import '../../../features/drawing/domain/stroke.dart';
import '../../../features/drawing/domain/shape_item.dart';

/// 形状识别器抽象接口
///
/// 识别手绘笔画中的几何形状
abstract class ShapeRecognizer {
  /// 识别笔画中的形状
  List<PageShapeItem> recognizeShapes(List<Stroke> strokes);

  /// 识别单个形状
  PageShapeItem? recognizeSingleShape(Stroke stroke);
}
