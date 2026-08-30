import 'dart:ui' show Size;

import 'package:drawing_notes_app/features/drawing/domain/document_image_item.dart';
import 'package:drawing_notes_app/features/drawing/domain/layer.dart';
import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';
import 'package:drawing_notes_app/core/canvas_model/text_item.dart';

/// 纸张模板类型（借鉴 Relatum / GoodNotes 等笔记软件的纸张背景）。
///
/// - [blank]：纯白空白页（默认）
/// - [grid]：网格纸（适合绘图/坐标类笔记）
/// - [lined]：横线纸（适合书写文字）
/// - [dot]：点阵纸（适合手写与绘图混合）
enum PaperType { blank, grid, lined, dot }

/// 画布文档（一幅画/一页笔记的数据根）。
///
/// 包含：画布物理尺寸（逻辑像素）、所有图层、元信息。
/// 序列化结构见 core/storage/document_codec.dart。
class DrawingDocument {
  DrawingDocument({
    required this.id,
    required this.title,
    this.width = 2048,
    this.height = 1536,
    this.infinite = false,
    this.paperType = PaperType.blank,
    this.folder = '',
    List<Layer>? layers,
    List<PageShapeItem>? shapes,
    List<DocumentImageItem>? imageItems,
    List<PageTextItem>? textItems,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : layers = layers != null
           ? List.of(layers)
           : [Layer(id: 'layer_1', name: '图层 1')],
       shapes = shapes != null ? List.of(shapes) : <PageShapeItem>[],
       imageItems = imageItems != null
           ? List.of(imageItems)
           : <DocumentImageItem>[],
       textItems = textItems != null ? List.of(textItems) : <PageTextItem>[],
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String id;
  String title;

  /// 所属文件夹路径（如 `工作/项目A`），空串表示根目录。
  ///
  /// 与笔记本页面的 [NotebookPage.folder] 共用同一套「文件目录」语义，
  /// 让画板与笔记可以在同一个文件夹里混排。向后兼容：旧文档缺失时为 ''。
  String folder;

  /// 画布宽度（逻辑像素），新建画布时可自定义（见 Phase 6 新建流程）。
  final int width;

  /// 画布高度（逻辑像素）。
  final int height;

  /// 无限画布模式（对齐 Excalidraw 无限场景）：
  /// 开启后画布尺寸随视口/内容动态扩展，元素可超出默认 A4 边界。
  bool infinite;

  /// 图层列表，索引 0 为最底层。渲染时按顺序自下而上绘制。
  final List<Layer> layers;

  /// 纸张模板类型（借鉴 Relatum/GoodNotes 等笔记软件的纸张背景）。
  PaperType paperType;

  /// 独立绘图文档的几何元素。笔记页仍可拥有独立的混排形状集合。
  final List<PageShapeItem> shapes;

  /// 独立绘图文档的离线图片元素。
  final List<DocumentImageItem> imageItems;

  /// 画布模式下的文字块（问题5：画布不再禁用文字工具）。
  ///
  /// 独立于图层位图的对象，与笔记本页面的文字块共用 [PageTextItem]；
  /// 序列化向后兼容（旧文档缺失时为空列表）。
  final List<PageTextItem> textItems;

  final DateTime createdAt;
  DateTime updatedAt;

  /// 标记文档已修改，由存储层在自动保存时调用（Phase 6）。
  void touch() => updatedAt = DateTime.now();

  /// 获取画布尺寸。
  Size get size => Size(width.toDouble(), height.toDouble());

  // ---- 序列化（与 core/storage/document_codec.dart 的文件格式一致）----

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'width': width,
    'height': height,
    'infinite': infinite,
    'paperType': paperType.name,
    'folder': folder,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'layers': layers.map((l) => l.toJson()).toList(),
    'shapes': shapes.map((shape) => shape.toJson()).toList(),
    'imageItems': imageItems.map((item) => item.toJson()).toList(),
    if (textItems.isNotEmpty)
      'textItems': textItems.map((item) => item.toJson()).toList(),
  };

  factory DrawingDocument.fromJson(
    Map<String, dynamic> json,
  ) => DrawingDocument(
    id: json['id'] as String,
    title: json['title'] as String? ?? '未命名',
    width: (json['width'] as num?)?.toInt() ?? 2048,
    height: (json['height'] as num?)?.toInt() ?? 1536,
    infinite: json['infinite'] as bool? ?? false,
    paperType: PaperType.values.firstWhere(
      (p) => p.name == json['paperType'],
      orElse: () => PaperType.blank,
    ),
    folder: json['folder'] as String? ?? '',
    layers: (json['layers'] as List? ?? const [])
        .map((e) => Layer.fromJson(e as Map<String, dynamic>))
        .toList(),
    shapes: (json['shapes'] as List? ?? const [])
        .map((e) => PageShapeItem.fromJson(e as Map<String, dynamic>))
        .toList(),
    imageItems: (json['imageItems'] as List? ?? const [])
        .map((e) => DocumentImageItem.fromJson(e as Map<String, dynamic>))
        .toList(),
    textItems: (json['textItems'] as List? ?? const [])
        .map((e) => PageTextItem.fromJson(e as Map<String, dynamic>))
        .toList(),
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    updatedAt:
        DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
  );
}
