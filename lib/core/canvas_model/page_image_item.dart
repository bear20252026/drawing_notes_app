import 'dart:ui';

/// 分页画布中的图片元素。
///
/// 图片在导入时复制到应用文档目录；[filePath] 因而是可跨重启恢复的本地
/// 绝对路径，而非临时文件选择器路径。该模型同时服务笔记页和绘图编辑器，
/// 但不依赖 notes 聚合根，避免 UI 层为图片类型而横向依赖 notes。
class PageImageItem {
  PageImageItem({
    required this.id,
    required this.x,
    required this.y,
    required this.filePath,
    this.width = 200,
    this.height = 150,
    this.zOrder = 0,
    this.groupId,
    this.href,
    this.fractionalIndex,
  });

  final String id;
  double x;
  double y;
  String filePath;
  double width;
  double height;

  /// 图层顺序（借鉴 Excalidraw 图层操作）。
  int zOrder;

  /// 层级排序键：重排只需在相邻键之间生成新键；null 表示旧文档回退为
  /// 按 [zOrder] 排序。
  String? fractionalIndex;

  /// 元素分组。
  String? groupId;

  /// 元素超链接。
  String? href;

  Offset get position => Offset(x, y);

  /// 以同一对象标识的快照覆盖全部可变字段（[copy] 的逆，H-2 第二轮审计）。
  void restoreFrom(PageImageItem snapshot) {
    assert(snapshot.id == id, '只能恢复同一图片对象的状态');
    x = snapshot.x;
    y = snapshot.y;
    filePath = snapshot.filePath;
    width = snapshot.width;
    height = snapshot.height;
    zOrder = snapshot.zOrder;
    groupId = snapshot.groupId;
    href = snapshot.href;
    fractionalIndex = snapshot.fractionalIndex;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'x': x,
    'y': y,
    'filePath': filePath,
    'width': width,
    'height': height,
    'zOrder': zOrder,
    if (groupId != null) 'groupId': groupId,
    if (href != null) 'href': href,
    if (fractionalIndex != null) 'fractionalIndex': fractionalIndex,
  };

  /// 为命令历史创建独立快照（与 PageShapeItem.copy 同纪律）。
  PageImageItem copy() => PageImageItem(
    id: id,
    x: x,
    y: y,
    filePath: filePath,
    width: width,
    height: height,
    zOrder: zOrder,
    groupId: groupId,
    href: href,
    fractionalIndex: fractionalIndex,
  );

  factory PageImageItem.fromJson(Map<String, dynamic> json) => PageImageItem(
    id: json['id'] as String,
    x: (json['x'] as num).toDouble(),
    y: (json['y'] as num).toDouble(),
    filePath: json['filePath'] as String,
    width: (json['width'] as num?)?.toDouble() ?? 200,
    height: (json['height'] as num?)?.toDouble() ?? 150,
    zOrder: (json['zOrder'] as num?)?.toInt() ?? 0,
    groupId: json['groupId'] as String?,
    href: json['href'] as String?,
    fractionalIndex: json['fractionalIndex'] as String?,
  );
}
