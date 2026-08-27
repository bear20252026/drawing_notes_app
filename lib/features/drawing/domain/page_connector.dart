/// 画布元素之间的连接线。
///
/// 连接 [fromItemId] 与 [toItemId] 两个混排对象（文字或图片）。模型属于
/// 绘图画布语义，可由笔记页面持有，但不依赖 notes 聚合根。
class PageConnector {
  PageConnector({
    required this.id,
    required this.fromItemId,
    required this.toItemId,
    this.color = 0xFF42A5F5,
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
    color: (json['color'] as num?)?.toInt() ?? 0xFF42A5F5,
  );
}
