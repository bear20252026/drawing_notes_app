import 'dart:math';
import 'dart:ui';

import 'shape_endpoint_binding.dart';

/// 图形工具形状类型。
enum ShapeType { rect, ellipse, diamond, arrow, line }

/// 可同时存在于笔记页和独立绘图文档中的几何形状元素。
///
/// [x]/[y] 为外接框左上角，宽高始终为正值。线性元素的原始拖拽方向由
/// [flipX]/[flipY] 保存，因此从右下向左上拖拽的箭头或直线不会被错误翻转。
class PageShapeItem {
  PageShapeItem({
    required this.id,
    required this.shapeType,
    required this.x,
    required this.y,
    this.width = 120,
    this.height = 80,
    this.color = 0xFF3A6EA5,
    this.fillColor,
    this.strokeWidth = 3,
    this.zOrder = 0,
    this.rotation = 0,
    this.dash = false,
    this.rough = false,
    this.elbow = false,
    this.flipX = false,
    this.flipY = false,
    this.boundElementId,
    this.locked = false,
    this.startBinding,
    this.endBinding,
    this.groupId,
    this.href,
    int? seed,
    this.version = 0,
    this.versionNonce = 0,
    this.fractionalIndex,
    this.lineStart,
    this.lineEnd,
  }) : seed = seed ?? _newSeed();

  final String id;
  ShapeType shapeType;
  double x;
  double y;
  double width;
  double height;
  int color;
  int? fillColor;
  double strokeWidth;
  int zOrder;
  double rotation;
  bool dash;
  bool rough;

  /// 弯折箭头（对齐 Excalidraw binding.ts 的 elbow 箭头）：
  /// 启用后箭头线在两端点之间以 90° 直角弯折（三段式），
  /// 适合流程图中连接节点时规避重叠的文本/元素。
  bool elbow;

  /// 随机种子：手绘风格/rough 抖动的稳定随机源（对齐 Excalidraw 元素模型），
  /// 同一形状重复渲染时使用同一 seed 保证质感一致。
  int seed;

  /// 层级排序键（fractional indexing，参考 Excalidraw）：重排只需在相邻
  /// 键之间生成新键，无需重排其余元素。null = 旧文档，回退按 [zOrder] 排序。
  String? fractionalIndex;

  /// 元素版本号：每次内容变更单调递增，供协作/增量同步的冲突检测。
  int version;

  /// 每次编辑递增的快速变化指示器；比 [version] 更细粒度。
  int versionNonce;

  /// 线性元素（直线/箭头）的真实起点（相对外接框左上角）。
  ///
  /// 参考 Saber shape_pen 的 `convertToLine()`（保存真实端点）：仅靠
  /// [flipX]/[flipY] 无法表达"从左往右画一条水平线"这类方向（渲染端固定
  /// 画对角线会翻转或变形）。保存相对端点后，渲染与命中按真实轨迹绘制；
  /// 旧文档缺失时回退为原"左下→右上"对角线行为。
  Offset? lineStart;
  Offset? lineEnd;

  static int _newSeed() => Random().nextInt(0x7FFFFFFF);

  /// 内容变更后调用：递增版本号，为增量同步/冲突检测提供依据。
  void bumpVersion() {
    version++;
    versionNonce++;
  }

  /// 相对外接框的水平翻转；用于保持箭头与直线的拖拽方向。
  bool flipX;

  /// 相对外接框的垂直翻转；用于保持箭头与直线的拖拽方向。
  bool flipY;

  String? boundElementId;

  /// 锁定形状仍可被选择以解除锁定，但拒绝移动、缩放与删除。
  bool locked;

  /// 箭头起点/终点的对象绑定。仅独立绘图文档的 [ShapeType.arrow] 使用；
  /// 旧文档和自由箭头保持 null，因而序列化完全向后兼容。
  ShapeEndpointBinding? startBinding;
  ShapeEndpointBinding? endBinding;

  String? groupId;
  String? href;

  Offset get position => Offset(x, y);

  /// 创建完整副本，供渲染投影、历史快照和复制粘贴使用。
  PageShapeItem copy() => PageShapeItem(
    id: id,
    shapeType: shapeType,
    x: x,
    y: y,
    width: width,
    height: height,
    color: color,
    fillColor: fillColor,
    strokeWidth: strokeWidth,
    zOrder: zOrder,
    rotation: rotation,
    dash: dash,
    rough: rough,
    flipX: flipX,
    flipY: flipY,
    boundElementId: boundElementId,
    locked: locked,
    startBinding: startBinding?.copy(),
    endBinding: endBinding?.copy(),
    groupId: groupId,
    href: href,
    seed: seed,
    version: version,
    versionNonce: versionNonce,
    fractionalIndex: fractionalIndex,
    lineStart: lineStart,
    lineEnd: lineEnd,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'shapeType': shapeType.name,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'color': color,
    if (fillColor != null) 'fillColor': fillColor,
    'strokeWidth': strokeWidth,
    'zOrder': zOrder,
    'rotation': rotation,
    'dash': dash,
    'rough': rough,
    'elbow': elbow,
    'flipX': flipX,
    'flipY': flipY,
    if (boundElementId != null) 'boundElementId': boundElementId,
    'locked': locked,
    if (startBinding != null) 'startBinding': startBinding!.toJson(),
    if (endBinding != null) 'endBinding': endBinding!.toJson(),
    if (groupId != null) 'groupId': groupId,
    if (href != null) 'href': href,
    'seed': seed,
    'version': version,
    'versionNonce': versionNonce,
    if (fractionalIndex != null) 'fractionalIndex': fractionalIndex,
    if (lineStart != null)
      'lineStart': [lineStart!.dx, lineStart!.dy],
    if (lineEnd != null) 'lineEnd': [lineEnd!.dx, lineEnd!.dy],
  };

  factory PageShapeItem.fromJson(Map<String, dynamic> json) => PageShapeItem(
    id: json['id'] as String,
    shapeType: ShapeType.values.firstWhere(
      (shape) => shape.name == json['shapeType'],
      orElse: () => ShapeType.rect,
    ),
    x: (json['x'] as num).toDouble(),
    y: (json['y'] as num).toDouble(),
    width: (json['width'] as num?)?.toDouble() ?? 120,
    height: (json['height'] as num?)?.toDouble() ?? 80,
    color: (json['color'] as num?)?.toInt() ?? 0xFF3A6EA5,
    fillColor: (json['fillColor'] as num?)?.toInt(),
    strokeWidth: (json['strokeWidth'] as num?)?.toDouble() ?? 3,
    zOrder: (json['zOrder'] as num?)?.toInt() ?? 0,
    rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
    dash: json['dash'] as bool? ?? false,
    rough: json['rough'] as bool? ?? false,
    elbow: json['elbow'] as bool? ?? false,
    flipX: json['flipX'] as bool? ?? false,
    flipY: json['flipY'] as bool? ?? false,
    boundElementId: json['boundElementId'] as String?,
    locked: json['locked'] as bool? ?? false,
    startBinding: _bindingFromJson(json['startBinding']),
    endBinding: _bindingFromJson(json['endBinding']),
    groupId: json['groupId'] as String?,
    href: json['href'] as String?,
    seed: (json['seed'] as num?)?.toInt(),
    version: (json['version'] as num?)?.toInt() ?? 0,
    versionNonce: (json['versionNonce'] as num?)?.toInt() ?? 0,
    fractionalIndex: json['fractionalIndex'] as String?,
    lineStart: _offsetFromJson(json['lineStart']),
    lineEnd: _offsetFromJson(json['lineEnd']),
  );

  static Offset? _offsetFromJson(Object? value) {
    if (value is! List || value.length != 2) return null;
    final dx = value[0];
    final dy = value[1];
    if (dx is! num || dy is! num) return null;
    return Offset(dx.toDouble(), dy.toDouble());
  }

  static ShapeEndpointBinding? _bindingFromJson(Object? value) {
    if (value is! Map) return null;
    return ShapeEndpointBinding.fromJson(Map<String, dynamic>.from(value));
  }
}
