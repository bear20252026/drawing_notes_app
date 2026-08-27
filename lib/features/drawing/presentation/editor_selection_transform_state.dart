import 'dart:math' as math;

/// 选中内容的缩放与旋转滑块暂态。
///
/// 状态仅服务于展示层控件：它把新的滑块值转换为控制器所需的缩放倍率或旋转
/// 弧度增量。实际对象变换、事务提交、文档通知和持久化仍由 `EditorPage` 协调。
class EditorSelectionTransformState {
  double _scaleValue = 1.0;
  double _rotationDegrees = 0.0;

  double get scaleValue => _scaleValue;
  double get rotationDegrees => _rotationDegrees;

  /// 应用新的缩放滑块值并返回相对上次值的倍率。
  double updateScale(double value) {
    final factor = value / _scaleValue;
    _scaleValue = value;
    return factor;
  }

  /// 应用新的旋转滑块值并返回相对上次值的弧度增量。
  double updateRotationDegrees(double value) {
    final delta = (value - _rotationDegrees) * math.pi / 180;
    _rotationDegrees = value;
    return delta;
  }

  /// 在选择被清理或新建时复位控件显示值。
  void reset() {
    _scaleValue = 1.0;
    _rotationDegrees = 0.0;
  }
}
