import 'dart:math' as math;
import 'dart:ui' show Offset;

/// 绘图画布的运行时视口状态与坐标投影。
///
/// 视口不属于持久化文档：缩放、平移和旋转只服务当前编辑会话。将其从
/// [DrawingController] 提取后，控制器仍负责工具、手势和文档变更，而该类
/// 负责保持 CanvasPainter 所使用变换的正逆关系。
class DrawingViewport {
  /// 画布缩放比例（1.0 = 实际大小）。
  double scale = 1.0;

  /// 画布在视口中的平移偏移（画布中心相对视口中心的位移）。
  Offset offset = Offset.zero;

  /// 画布旋转角度（弧度）。
  double rotation = 0.0;

  /// 将视图坐标（像素）转换为画布逻辑坐标。
  ///
  /// 变换模型：`view = R(rotation) · (scale · (canvas - center)) + center + offset`。
  Offset viewToCanvas(Offset viewPoint, {required Offset canvasCenter}) {
    final rotated = _rotate(viewPoint - canvasCenter - offset, -rotation);
    return rotated / scale + canvasCenter;
  }

  /// 将画布逻辑坐标转换为视图坐标（与 [viewToCanvas] 严格互逆）。
  Offset canvasToView(Offset canvasPoint, {required Offset canvasCenter}) {
    final rotated = _rotate((canvasPoint - canvasCenter) * scale, rotation);
    return rotated + canvasCenter + offset;
  }

  static Offset _rotate(Offset point, double angle) {
    final cos = math.cos(angle);
    final sin = math.sin(angle);
    return Offset(
      point.dx * cos - point.dy * sin,
      point.dx * sin + point.dy * cos,
    );
  }
}
