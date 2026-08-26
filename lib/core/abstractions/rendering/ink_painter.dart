// core/abstractions — 墨迹绘制抽象接口
// 遵循 Clean Architecture：定义抽象契约，实现由 Infrastructure 层提供

import 'dart:ui';

import '../../../features/drawing/domain/stroke.dart';

/// 墨迹分层绘制策略抽象接口
///
/// 高亮笔不是普通的半透明线条。将同色高亮笔先绘入独立图层并以
/// BlendMode.darken 合成，可以避免交叠区域变脏，同时保证普通墨迹
/// 始终绘制在高亮笔上方。
abstract class InkPainter {
  /// 绘制一个完整图层的笔画
  ///
  /// 为确保文字/普通笔画可读，所有高亮笔始终先绘制；橡皮擦则保留在
  /// 普通队列中，依序以 BlendMode.clear 作用于已合成的内容。
  void paintStrokes(
    Canvas canvas,
    Rect bounds,
    Iterable<Stroke> strokes,
  );
}
