import 'dart:ui';

import 'package:drawing_notes_app/core/canvas_model/page_image_item.dart';
import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';
import 'package:drawing_notes_app/core/canvas_model/text_item.dart';

/// 混排对象命中判定（R3 收敛，2026-11-17）。
///
/// 此前 _onPointerUp 的框选（rect.overlaps）与套索（path.contains）各持
/// 一份「文字/图片/形状三类边界换算 + 命中」的三段同构循环（约 60 行），
/// 边界口径（文字宽 = fontSize*2、套索取中心点）散在手势巨方法里不可单测。
/// 收敛进本纯函数类：不可变输入 → 确定性 id 列表，与 ShapeCreationGeometry
/// 同层同纪律（infrastructure 纯 Dart，禁 Widget/State）。
///
/// 行为契约（与抽取前逐字一致）：
/// - 框选：对象外接矩形与选区矩形 overlaps（文字矩形 = fontSize*2 × fontSize）；
/// - 套索：对象**中心点**落在多边形内（文字中心 = position + (fontSize, fontSize/2)）；
/// - 顺序：文字 → 图片 → 形状（与既有选中列表顺序一致，多选锚定语义依赖它）。
class MixedItemHitGeometry {
  const MixedItemHitGeometry._();

  /// 框选命中：返回与 [rect] 相交的混排对象 id（文字→图片→形状顺序）。
  static List<String> idsInRect({
    required Rect rect,
    required List<PageTextItem> textItems,
    required List<PageImageItem> imageItems,
    required List<PageShapeItem> shapes,
  }) {
    return <String>[
      for (final text in textItems)
        if (rect.overlaps(
          Rect.fromLTWH(text.x, text.y, text.fontSize * 2, text.fontSize),
        ))
          text.id,
      for (final image in imageItems)
        if (rect.overlaps(
          Rect.fromLTWH(image.x, image.y, image.width, image.height),
        ))
          image.id,
      for (final shape in shapes)
        if (rect.overlaps(
          Rect.fromLTWH(shape.x, shape.y, shape.width, shape.height),
        ))
          shape.id,
    ];
  }

  /// 套索命中：返回中心点落在 [polygon] 内的混排对象 id（同序）。
  static List<String> idsInPolygon({
    required List<Offset> polygon,
    required List<PageTextItem> textItems,
    required List<PageImageItem> imageItems,
    required List<PageShapeItem> shapes,
  }) {
    if (polygon.length < 3) return const <String>[];
    final path = Path()..addPolygon(polygon, true);
    return idsInPath(
      path: path,
      textItems: textItems,
      imageItems: imageItems,
      shapes: shapes,
    );
  }

  /// 套索命中（已构造 Path 的入口——调用方复用同一 Path 时免重复构造）。
  static List<String> idsInPath({
    required Path path,
    required List<PageTextItem> textItems,
    required List<PageImageItem> imageItems,
    required List<PageShapeItem> shapes,
  }) {
    return <String>[
      for (final text in textItems)
        if (path.contains(
          text.position + Offset(text.fontSize, text.fontSize / 2),
        ))
          text.id,
      for (final image in imageItems)
        if (path.contains(
          image.position + Offset(image.width / 2, image.height / 2),
        ))
          image.id,
      for (final shape in shapes)
        if (path.contains(
          shape.position + Offset(shape.width / 2, shape.height / 2),
        ))
          shape.id,
    ];
  }
}