import 'value_objects/geometry.dart';

/// 文字对齐方式。
enum TextAlignType { left, center, right }

/// 画布/页面上的文字块。
///
/// 位置为画布坐标（左上角）。从 notebook.dart 独立出来，使
/// [DrawingDocument]（无限画布）与笔记本页面都能持有文字项，
/// 从而修复"画布模式下文字工具不可用"的问题（问题5）。
class PageTextItem {
  PageTextItem({
    required this.id,
    required this.x,
    required this.y,
    required this.text,
    this.fontSize = 24,
    this.color = 0xFF1A1A1A,
    this.isSticky = false,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strikethrough = false,
    this.isTodo = false,
    this.todoChecked = false,
    this.align = TextAlignType.left,
    this.zOrder = 0,
    this.width,
    this.groupId,
    this.href,
    this.fontFamily,
    this.fractionalIndex,
    this.runs,
  });

  final String id;

  /// 位置（画布坐标，左上角）。
  double x;
  double y;
  String text;
  double fontSize;

  /// 颜色（ARGB int，便于 JSON 序列化）。
  int color;

  /// 是否为"特殊标签"（便利贴样式）：带背景色块、圆角、可拖动移动。
  /// 普通文字块为透明无边框文本；标签为醒目色块，便于在页面内分类标注。
  bool isSticky;

  /// 加粗（借鉴 AbiWord/Umo Editor 文字属性）。
  bool bold;

  /// 斜体（借鉴 AbiWord/Umo Editor 文字属性）。
  bool italic;

  /// 下划线（借鉴 AbiWord/Umo Editor 文字属性）。
  bool underline;

  /// 删除线（借鉴 AbiWord/Umo Editor 文字属性）。
  bool strikethrough;

  /// 是否为待办清单项（借鉴 QOwnNotes 待办，文字前显示 checkbox）。
  bool isTodo;

  /// 待办是否已勾选。
  bool todoChecked;

  /// 对齐方式（借鉴 AbiWord/Umo Editor 文字属性）。
  TextAlignType align;

  /// 图层顺序（借鉴 Excalidraw 图层操作：置顶/置底/上移/下移）。
  int zOrder;

  /// 层级排序键（fractional indexing，参考 Excalidraw）：重排只需在相邻
  /// 键之间生成新键，无需重排其余元素。null = 旧文档，回退按 [zOrder] 排序。
  String? fractionalIndex;

  /// 元素超链接（借鉴 Excalidraw hyperlink）：点击打开链接。
  String? href;

  /// 元素分组（借鉴 Excalidraw groupIds）：同组元素整体移动/删除。
  String? groupId;

  /// 字体族（借鉴 Excalidraw FontPicker）：null=默认，
  /// 'serif'/'monospace'/'handwriting' 为可选字体。
  String? fontFamily;

  /// 文字框宽度（画布像素；null = 单行自动宽度）。
  /// 非 null 时文本超宽自动换行（Excalidraw 文本框多行体验），
  /// 可拖拽右侧手柄调整（对齐 Excalidraw 宽度拖拽）。
  double? width;

  /// 富文本片段（借鉴 Quill Delta runs，独立实现）：null = 整块样式
  /// （旧文档），非 null 时按片段渲染 [TextRun] 各自的样式。
  List<TextRun>? runs;

  FOffset get position => FOffset(x, y);

  Map<String, dynamic> toJson() => {
    'id': id,
    'x': x,
    'y': y,
    'text': text,
    'fontSize': fontSize,
    'color': color,
    'isSticky': isSticky,
    'bold': bold,
    'italic': italic,
    'underline': underline,
    'strikethrough': strikethrough,
    'isTodo': isTodo,
    'todoChecked': todoChecked,
    'align': align.name,
    'zOrder': zOrder,
    if (width != null) 'width': width,
    if (groupId != null) 'groupId': groupId,
    if (href != null) 'href': href,
    if (fontFamily != null) 'fontFamily': fontFamily,
    if (fractionalIndex != null) 'fractionalIndex': fractionalIndex,
    if (runs != null) 'runs': runs!.map((r) => r.toJson()).toList(),
  };

  factory PageTextItem.fromJson(Map<String, dynamic> json) => PageTextItem(
    id: json['id'] as String,
    x: (json['x'] as num).toDouble(),
    y: (json['y'] as num).toDouble(),
    text: json['text'] as String? ?? '',
    fontSize: (json['fontSize'] as num?)?.toDouble() ?? 24,
    color: (json['color'] as num?)?.toInt() ?? 0xFF1A1A1A,
    isSticky: json['isSticky'] as bool? ?? false,
    bold: json['bold'] as bool? ?? false,
    italic: json['italic'] as bool? ?? false,
    underline: json['underline'] as bool? ?? false,
    strikethrough: json['strikethrough'] as bool? ?? false,
    isTodo: json['isTodo'] as bool? ?? false,
    todoChecked: json['todoChecked'] as bool? ?? false,
    zOrder: (json['zOrder'] as num?)?.toInt() ?? 0,
    width: (json['width'] as num?)?.toDouble(),
    groupId: json['groupId'] as String?,
    href: json['href'] as String?,
    fontFamily: json['fontFamily'] as String?,
    align: TextAlignType.values.firstWhere(
      (a) => a.name == json['align'],
      orElse: () => TextAlignType.left,
    ),
    fractionalIndex: json['fractionalIndex'] as String?,
    runs: (json['runs'] as List?)
        ?.map((e) => TextRun.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

/// 富文本片段（借鉴 Quill Delta runs 的思想，独立实现）。
///
/// 一个文字块可以由多个 [TextRun] 组成，每段拥有独立的样式
/// （加粗/斜体/下划线/删除线/颜色）。旧文档没有 runs 时回退为整块
/// 样式（[PageTextItem.bold] 等块级字段），序列化完全向后兼容。
class TextRun {
  const TextRun({
    required this.text,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strikethrough = false,
    this.color,
  });

  final String text;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strikethrough;

  /// 片段颜色（ARGB int）；null = 继承块级 [PageTextItem.color]。
  final int? color;

  Map<String, dynamic> toJson() => {
    'text': text,
    'bold': bold,
    'italic': italic,
    'underline': underline,
    'strikethrough': strikethrough,
    if (color != null) 'color': color,
  };

  factory TextRun.fromJson(Map<String, dynamic> json) => TextRun(
    text: json['text'] as String? ?? '',
    bold: json['bold'] as bool? ?? false,
    italic: json['italic'] as bool? ?? false,
    underline: json['underline'] as bool? ?? false,
    strikethrough: json['strikethrough'] as bool? ?? false,
    color: (json['color'] as num?)?.toInt(),
  );
}
