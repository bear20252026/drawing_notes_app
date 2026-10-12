import 'dart:math';
import 'dart:ui';

import 'package:drawing_notes_app/core/canvas_model/shape_endpoint_binding.dart';

/// 图形工具形状类型。
enum ShapeType { rect, ellipse, diamond, arrow, line }

/// 线型（格式 v4 可选键 `strokeStyle`）。
///
/// **null 的含义是「按 v3 的 `dash` 布尔推导」**，不是「实线」：
/// 旧文件不带这个键，读出来就是 null，观感必须与升级前逐像素一致。
/// 只有在用户显式选了 `dotted`（`dash` 表达不了的第三态）或显式改回
/// `solid`/`dashed` 时才会写入。
enum StrokeStyle { solid, dashed, dotted }

/// 填充样式（格式 v4 可选键 `fillStyle`）。
///
/// null 同样表示沿用旧推导：有 `fillColor` 时 `rough` → 斜排线、否则实心。
/// 未知字符串一律降级为 null（迁移层与解码都不新增拒绝路径）。
enum FillStyle { solid, hachure, crossHatch }

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
    bool dash = false,
    this.rough = false,
    this.elbow = false,
    this.strokeStyle,
    this.fillStyle,
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
  }) : // 私有字段无法用命名初始化形参（`this._dashLegacy` 非法）。
       // ignore: prefer_initializing_formals
       _dashLegacy = dash,
       seed = seed ?? _newSeed();

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
  bool _dashLegacy;

  /// v3 遗留布尔 `dash`。自 v4 起它是 [strokeStyle] 的**投影**，不是第二套真相：
  /// 读时由显式线型回答（**任何非实线都是 true**），写时同步回落显式键。
  ///
  /// 取「非实线」而不是「等于 dashed」，是为了旧版本：v3 及更早只认这个布尔，
  /// 若 dotted 记成 false，旧版本会把点线画成实线（观感静默消失）；记成 true
  /// 至多降级成虚线，用户至少还看得出「这条线不是实线」。
  ///
  /// 规则收在这里而不是各调用点，是因为写 `dash` 的入口分散在 `editor_page.dart`
  /// 的 part 文件里，而那个库受行数棘轮约束（抬基线不是选项）——
  /// 一处实现，工具条的「虚线」开关就永远有效，也不会出现
  /// `strokeStyle: dashed` 与 `dash: false` 同时成立的分裂态。
  bool get dash =>
      strokeStyle != null ? strokeStyle != StrokeStyle.solid : _dashLegacy;

  set dash(bool value) {
    if (strokeStyle != null) {
      strokeStyle = value ? StrokeStyle.dashed : StrokeStyle.solid;
    }
    _dashLegacy = value;
  }
  bool rough;

  /// 弯折箭头（对齐 Excalidraw binding.ts 的 elbow 箭头）：
  /// 启用后箭头线在两端点之间以 90° 直角弯折（三段式），
  /// 适合流程图中连接节点时规避重叠的文本/元素。
  bool elbow;

  /// 线型显式值（格式 v4 可选键）。null = 按 [dash] 推导，见 [StrokeStyle]。
  StrokeStyle? strokeStyle;

  /// 填充样式显式值（格式 v4 可选键）。null = 按 [rough]/[fillColor] 推导，见 [FillStyle]。
  FillStyle? fillStyle;

  /// 有效线型：显式键优先，缺省沿用 v3 的 `dash` 语义。渲染与导出只读这里，
  /// 避免「显式值」与「dash 布尔」在两条绘制路径上各说一半。
  StrokeStyle get effectiveStrokeStyle =>
      strokeStyle ?? (dash ? StrokeStyle.dashed : StrokeStyle.solid);

  /// 有效填充样式：无填充色即不画填充；有填充色且缺省时按 `rough` 推导（与升级前一致）。
  FillStyle? get effectiveFillStyle => fillColor == null
      ? null
      : (fillStyle ?? (rough ? FillStyle.hachure : FillStyle.solid));

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

  static int _newSeed() => Random.secure().nextInt(0x7FFFFFFF);

  /// 内容变更后调用：递增版本号，为增量同步/冲突检测提供依据。
  void bumpVersion() {
    version++;
    versionNonce++;
  }

  /// 工具条「线型」按钮的三档循环：实线 → 虚线 → 点线。
  ///
  /// 循环（而不是二态开关）是这个面板既有的惯例（`onCycleFont` 同形），
  /// 这样 v4 的第三档不需要给 `editor_page.dart` 那批 part 文件加新回调——
  /// 那个库有行数棘轮（`test/editor_page_line_ratchet_test.dart`），
  /// 加控件的正当出路是把语义收进模型，而不是抬基线。
  void cycleStrokeStyle() {
    strokeStyle = switch (effectiveStrokeStyle) {
      StrokeStyle.solid => StrokeStyle.dashed,
      StrokeStyle.dashed => StrokeStyle.dotted,
      StrokeStyle.dotted => StrokeStyle.solid,
    };
    bumpVersion();
  }

  /// 工具条「填充」按钮的四档循环：无 → 实心 → 斜线 → 交叉线。
  ///
  /// 从「无」起步时用 [defaultFill] 作起色（沿用面板既有取色），
  /// 因为样式在没有填充色时不可见——让用户点一下就看到变化。
  void cycleFillStyle(int defaultFill) {
    if (fillColor == null) {
      fillColor = defaultFill;
      fillStyle = FillStyle.solid;
      bumpVersion();
      return;
    }
    final next = switch (effectiveFillStyle) {
      FillStyle.solid => FillStyle.hachure,
      FillStyle.hachure => FillStyle.crossHatch,
      FillStyle.crossHatch => null,
      null => FillStyle.solid,
    };
    if (next == null) {
      fillColor = null;
      fillStyle = null;
    } else {
      fillStyle = next;
    }
    bumpVersion();
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
    elbow: elbow,
    strokeStyle: strokeStyle,
    fillStyle: fillStyle,
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
    // 只写**偏离旧推导**的显式值：这样 v3 文件重存不长新键，工具条的
    // dash/rough 开关也不会被定格下来的显式值压住（写两条真相的代价）。
    if (strokeStyle != null &&
        strokeStyle != (dash ? StrokeStyle.dashed : StrokeStyle.solid))
      'strokeStyle': strokeStyle!.name,
    if (fillStyle != null &&
        fillStyle !=
            (fillColor == null
                ? null
                : (rough ? FillStyle.hachure : FillStyle.solid)))
      'fillStyle': fillStyle!.name,
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
    if (lineStart != null) 'lineStart': [lineStart!.dx, lineStart!.dy],
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
    strokeStyle: _enumFromJson(StrokeStyle.values, json['strokeStyle']),
    fillStyle: _enumFromJson(FillStyle.values, json['fillStyle']),
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

  /// 宽容解析可选枚举键：缺失、类型不符或未知取值一律返回 null，
  /// 由 `effective*` 属性回落到 v3 的推导结果（解码层不新增拒绝路径）。
  static T? _enumFromJson<T extends Enum>(List<T> values, Object? raw) {
    if (raw is! String) return null;
    for (final value in values) {
      if (value.name == raw) return value;
    }
    return null;
  }

  static Offset? _offsetFromJson(Object? value) {
    if (value is! List || value.length != 2) return null;
    final dx = value[0];
    final dy = value[1];
    if (dx is! num || dy is! num) return null;
    return Offset(dx.toDouble(), dy.toDouble());
  }

  static ShapeEndpointBinding? _bindingFromJson(Object? value) {    if (value is! Map) return null;
    return ShapeEndpointBinding.fromJson(Map<String, dynamic>.from(value));
  }
}
