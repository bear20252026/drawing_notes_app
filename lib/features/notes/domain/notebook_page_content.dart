import 'dart:convert';

import 'package:drawing_notes_app/features/drawing/domain/document.dart';
import 'package:drawing_notes_app/core/canvas_model/page_chart_item.dart';
import 'package:drawing_notes_app/core/canvas_model/page_connector.dart';
import 'package:drawing_notes_app/core/canvas_model/page_image_item.dart';
import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';
import 'package:drawing_notes_app/core/canvas_model/text_item.dart';

/// 笔记页的完整可编辑载荷。
///
/// 页面库元数据（标题、标签、模板、收藏、克隆引用和历史）不属于该对象；
/// 它只协调画布与混排对象的复制、比较、序列化及恢复。所有集合保持可变，
/// 以便既有编辑器会话继续持有活动页面的同一份内容引用。
class NotebookPageContent {
  NotebookPageContent({
    required this.document,
    List<PageTextItem>? textItems,
    List<PageImageItem>? imageItems,
    List<PageConnector>? connectors,
    List<PageShapeItem>? shapes,
    List<PageChartItem>? charts,
  }) : textItems = textItems ?? [],
       imageItems = imageItems ?? [],
       connectors = connectors ?? [],
       shapes = shapes ?? [],
       charts = charts ?? [];

  final DrawingDocument document;
  final List<PageTextItem> textItems;
  final List<PageImageItem> imageItems;
  final List<PageConnector> connectors;
  final List<PageShapeItem> shapes;
  final List<PageChartItem> charts;

  /// 是否不含任何可编辑对象。
  bool get isEmpty =>
      document.layers.every((layer) => layer.strokes.isEmpty) &&
      document.shapes.isEmpty &&
      document.imageItems.isEmpty &&
      document.textItems.isEmpty &&
      textItems.isEmpty &&
      imageItems.isEmpty &&
      connectors.isEmpty &&
      shapes.isEmpty &&
      charts.isEmpty;

  /// 用于判断内容是否变化的稳定 JSON 表示。
  ///
  /// 不暴露可变集合本身，避免保存调度在展示层重复维护六类字段的比较规则。
  String get signature => jsonEncode(toJson());

  bool hasSameContentAs(NotebookPageContent other) =>
      signature == other.signature;

  /// 以 JSON 往返复制所有嵌套领域对象，确保历史版本不会与活动页面共享引用。
  NotebookPageContent deepCopy() => NotebookPageContent.fromJson(toJson());

  /// 以 [source] 的深拷贝覆盖当前活动内容。
  ///
  /// `DrawingDocument` 对象身份会保留，因为编辑器控制器可能正在持有该对象；
  /// 文档中可变的渲染与纸张状态，以及页面级混排集合都会被完整更新。
  void replaceWith(NotebookPageContent source) {
    final copied = source.deepCopy();
    final activeDocument = document;
    final restoredDocument = copied.document;
    activeDocument.layers
      ..clear()
      ..addAll(restoredDocument.layers);
    activeDocument.title = restoredDocument.title;
    activeDocument.infinite = restoredDocument.infinite;
    activeDocument.paperType = restoredDocument.paperType;
    activeDocument.shapes
      ..clear()
      ..addAll(restoredDocument.shapes);
    activeDocument.imageItems
      ..clear()
      ..addAll(restoredDocument.imageItems);
    activeDocument.textItems
      ..clear()
      ..addAll(restoredDocument.textItems);
    activeDocument.updatedAt = restoredDocument.updatedAt;

    textItems
      ..clear()
      ..addAll(copied.textItems);
    imageItems
      ..clear()
      ..addAll(copied.imageItems);
    connectors
      ..clear()
      ..addAll(copied.connectors);
    shapes
      ..clear()
      ..addAll(copied.shapes);
    charts
      ..clear()
      ..addAll(copied.charts);
  }

  Map<String, dynamic> toJson() => {
    'document': document.toJson(),
    'textItems': textItems.map((item) => item.toJson()).toList(),
    'imageItems': imageItems.map((item) => item.toJson()).toList(),
    'connectors': connectors.map((item) => item.toJson()).toList(),
    'shapes': shapes.map((item) => item.toJson()).toList(),
    'charts': charts.map((item) => item.toJson()).toList(),
  };

  factory NotebookPageContent.fromJson(Map<String, dynamic> json) =>
      NotebookPageContent(
        document: DrawingDocument.fromJson(
          json['document'] as Map<String, dynamic>,
        ),
        textItems: (json['textItems'] as List? ?? const [])
            .map((item) => PageTextItem.fromJson(item as Map<String, dynamic>))
            .toList(),
        imageItems: (json['imageItems'] as List? ?? const [])
            .map((item) => PageImageItem.fromJson(item as Map<String, dynamic>))
            .toList(),
        connectors: (json['connectors'] as List? ?? const [])
            .map((item) => PageConnector.fromJson(item as Map<String, dynamic>))
            .toList(),
        shapes: (json['shapes'] as List? ?? const [])
            .map((item) => PageShapeItem.fromJson(item as Map<String, dynamic>))
            .toList(),
        charts: (json['charts'] as List? ?? const [])
            .map((item) => PageChartItem.fromJson(item as Map<String, dynamic>))
            .toList(),
      );
}
