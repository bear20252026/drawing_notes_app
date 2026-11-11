import 'package:drawing_notes_app/core/utils/wire_enum.dart';

/// 橡皮擦的用户可选行为。
///
/// [stroke] 会删除命中的完整笔画或形状，适合课堂笔记中的“擦掉这一条线”；
/// [pixel] 保留一条透明合成擦除轨迹，适合自由绘图中的局部挖空。
enum EraserMode implements WireEnum {
  stroke,
  pixel;

  /// 落盘 wire 名（`eraser_mode.v1` 首选项，CTL-03 ②）。
  @override
  String get wireName => switch (this) {
    EraserMode.stroke => 'stroke',
    EraserMode.pixel => 'pixel',
  };
}
