import 'dart:ui';

import '../../domain/value_objects/geometry.dart';

/// Domain 值对象 ↔ dart:ui 类型转换扩展。
///
/// 这些扩展仅在 Infrastructure 层和 Presentation 层使用，
/// 使 Domain 层保持零 Flutter 依赖。

/// FOffset ↔ Offset 转换。
extension FOffsetToUi on FOffset {
  Offset toUi() => Offset(x, y);
}

extension UiToFOffset on Offset {
  FOffset toFOffset() => FOffset(dx, dy);
}

/// FSize ↔ Size 转换。
extension FSizeToUi on FSize {
  Size toUi() => Size(width, height);
}

extension UiToFSize on Size {
  FSize toFSize() => FSize(width, height);
}

/// FRect ↔ Rect 转换。
extension FRectToUi on FRect {
  Rect toUi() => Rect.fromLTWH(x, y, width, height);
}

extension UiToFRect on Rect {
  FRect toFRect() => FRect(left, top, width, height);
}
