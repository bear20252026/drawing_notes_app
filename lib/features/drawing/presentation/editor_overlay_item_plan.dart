import 'package:drawing_notes_app/core/canvas_model/page_chart_item.dart';
import 'package:drawing_notes_app/core/canvas_model/page_image_item.dart';
import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';
import 'package:drawing_notes_app/core/canvas_model/text_item.dart';

/// 编辑器叠加对象的显示类别。
///
/// 类型信息由计划协作者保留，避免页面在按层级排序后再次遍历多个集合推断对象类型。
enum EditorOverlayItemKind { text, image, shape, chart }

/// 一个按显示层级排序的编辑器叠加对象。
///
/// 该值对象只暴露恰好一种领域载荷。它不引用页面状态、控制器或 Widget，因而
/// 可在无 Flutter Widget 树的环境中直接验证排序和对象分派语义。
class EditorOverlayItemPlanEntry {
  const EditorOverlayItemPlanEntry._({
    required this.id,
    required this.zOrder,
    required this.kind,
    this.text,
    this.image,
    this.shape,
    this.chart,
  });

  factory EditorOverlayItemPlanEntry.text(PageTextItem item) =>
      EditorOverlayItemPlanEntry._(
        id: item.id,
        zOrder: item.zOrder,
        kind: EditorOverlayItemKind.text,
        text: item,
      );

  factory EditorOverlayItemPlanEntry.image(PageImageItem item) =>
      EditorOverlayItemPlanEntry._(
        id: item.id,
        zOrder: item.zOrder,
        kind: EditorOverlayItemKind.image,
        image: item,
      );

  factory EditorOverlayItemPlanEntry.shape(PageShapeItem item) =>
      EditorOverlayItemPlanEntry._(
        id: item.id,
        zOrder: item.zOrder,
        kind: EditorOverlayItemKind.shape,
        shape: item,
      );

  factory EditorOverlayItemPlanEntry.chart(PageChartItem item) =>
      EditorOverlayItemPlanEntry._(
        id: item.id,
        zOrder: item.zOrder,
        kind: EditorOverlayItemKind.chart,
        chart: item,
      );

  final String id;
  final int zOrder;
  final EditorOverlayItemKind kind;
  final PageTextItem? text;
  final PageImageItem? image;
  final PageShapeItem? shape;
  final PageChartItem? chart;
}

/// 编辑器混排对象的只读显示计划。
///
/// 画布模式只计划文字块；笔记页模式在同一稳定输入顺序下合并文字、图片、形状
/// 和图表。调用方负责把计划条目映射成具体 Widget，以及处理正在编辑的文字块。
class EditorOverlayItemPlan {
  const EditorOverlayItemPlan._();

  static List<EditorOverlayItemPlanEntry> forCanvas(
    Iterable<PageTextItem> textItems,
  ) => _ordered(textItems.map(EditorOverlayItemPlanEntry.text));

  static List<EditorOverlayItemPlanEntry> forPage({
    required Iterable<PageTextItem> textItems,
    required Iterable<PageImageItem> imageItems,
    required Iterable<PageShapeItem> shapes,
    required Iterable<PageChartItem> charts,
  }) => _ordered([
    ...textItems.map(EditorOverlayItemPlanEntry.text),
    ...imageItems.map(EditorOverlayItemPlanEntry.image),
    ...shapes.map(EditorOverlayItemPlanEntry.shape),
    ...charts.map(EditorOverlayItemPlanEntry.chart),
  ]);

  static List<EditorOverlayItemPlanEntry> _ordered(
    Iterable<EditorOverlayItemPlanEntry> entries,
  ) {
    final ordered = entries.toList()
      ..sort((a, b) => a.zOrder.compareTo(b.zOrder));
    return List<EditorOverlayItemPlanEntry>.unmodifiable(ordered);
  }
}
