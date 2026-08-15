import 'package:drawing_notes_app/features/drawing/domain/stroke.dart';

/// 图层模型。
///
/// 每个图层保存一份笔画列表（矢量数据），外加显示属性：
/// - [visible]：是否可见（图层面板的"眼睛"开关）
/// - [opacity]：图层不透明度 0~1（Phase 3 提供滑块调节）
///
/// 说明：当前版本不含混合模式与蒙版（按开发计划明确"先不做"），
/// 因此渲染时只做"普通叠加 + 透明度"，逻辑简单可靠。
class Layer {
  Layer({
    required this.id,
    required this.name,
    this.visible = true,
    this.opacity = 1.0,
    List<Stroke>? strokes,
  }) : strokes = List.of(strokes ?? const []);

  /// 图层唯一标识（不可变），用于撤销历史、渲染缓存索引。
  final String id;
  String name;
  bool visible;

  /// 图层不透明度，范围 0.0 ~ 1.0。
  double opacity;

  /// 本图层上的所有笔画，按绘制先后顺序排列。
  final List<Stroke> strokes;

  // ---- 序列化 ----

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'visible': visible,
    'opacity': opacity,
    'strokes': strokes.map((s) => s.toJson()).toList(),
  };

  factory Layer.fromJson(Map<String, dynamic> json) => Layer(
    id: json['id'] as String,
    name: json['name'] as String? ?? '图层',
    visible: json['visible'] as bool? ?? true,
    opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
    strokes: (json['strokes'] as List? ?? const [])
        .map((e) => Stroke.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}
