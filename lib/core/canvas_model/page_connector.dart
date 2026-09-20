/// 画布元素之间的连接线。
///
/// 连接 [fromItemId] 与 [toItemId] 两个混排对象（文字或图片）。模型属于
/// 绘图画布语义，可由笔记页面持有，但不依赖 notes 聚合根。
///
/// 颜色默认值（审计 2026-09-18 P2-6）：新建对齐 Action Blue `#0066CC`；
/// JSON 缺省 `color` 字段时仍回落历史 Material Blue，保证旧文档语义不变。
class PageConnector {
  /// 新建连接线默认色 = Apple Action Blue（与 UI 铬层一致）。
  /// domain 层不依赖 `AppleColor`，用 ARGB 字面量对齐 `0xFF0066CC`。
  static const int kDefaultColor = 0xFF0066CC;

  /// 历史默认连接色（Material Blue 42A5F5）——仅作旧数据读侧兼容。
  static const int kLegacyDefaultColor = 0xFF42A5F5;

  PageConnector({
    required this.id,
    required this.fromItemId,
    required this.toItemId,
    this.color = kDefaultColor,
  });

  final String id;
  final String fromItemId;
  final String toItemId;
  final int color;

  Map<String, dynamic> toJson() => {
    'id': id,
    'fromItemId': fromItemId,
    'toItemId': toItemId,
    'color': color,
  };

  factory PageConnector.fromJson(Map<String, dynamic> json) => PageConnector(
    id: json['id'] as String,
    fromItemId: json['fromItemId'] as String,
    toItemId: json['toItemId'] as String,
    color: (json['color'] as num?)?.toInt() ?? kLegacyDefaultColor,
  );
}
