import 'dart:ui';

/// 独立绘图文档中的图片元素。
///
/// 图片在导入时复制到应用数据目录；[filePath] 因而是可跨重启恢复的本地
/// 绝对路径，而非临时文件选择器路径。该模型与笔记页图片刻意分离，避免
/// `DrawingDocument` 与 `Notebook` 之间形成循环依赖。
class DocumentImageItem {
  DocumentImageItem({
    required this.id,
    required this.x,
    required this.y,
    required this.filePath,
    this.width = 200,
    this.height = 150,
    this.zOrder = 0,
    this.locked = false,
    this.fractionalIndex,
  });

  final String id;
  double x;
  double y;
  String filePath;
  double width;
  double height;
  int zOrder;

  /// 层级排序键（fractional indexing，参考 Excalidraw）：任意两次重排
  /// 只需在相邻键之间生成新键，无需重排其余元素。null = 旧文档，回退
  /// 按 [zOrder] 排序，序列化向后兼容。
  String? fractionalIndex;

  /// 锁定后仍可被选择以解除锁定，但拒绝移动、缩放和删除，防止资料底图误触。
  bool locked;

  Offset get position => Offset(x, y);

  Rect get bounds => Rect.fromLTWH(x, y, width, height);

  /// 为命令历史创建独立快照，避免编辑过程中的可变引用污染撤销状态。
  DocumentImageItem copy() => DocumentImageItem(
    id: id,
    x: x,
    y: y,
    filePath: filePath,
    width: width,
    height: height,
    zOrder: zOrder,
    locked: locked,
    fractionalIndex: fractionalIndex,
  );

  /// 以同一对象标识的快照覆盖可编辑几何与资源元数据。
  void restoreFrom(DocumentImageItem snapshot) {
    assert(snapshot.id == id, '只能恢复同一图片对象的状态');
    x = snapshot.x;
    y = snapshot.y;
    filePath = snapshot.filePath;
    width = snapshot.width;
    height = snapshot.height;
    zOrder = snapshot.zOrder;
    locked = snapshot.locked;
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
    'locked': locked,
    if (fractionalIndex != null) 'fractionalIndex': fractionalIndex,
  };

  factory DocumentImageItem.fromJson(Map<String, dynamic> json) =>
      DocumentImageItem(
        id: json['id'] as String,
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        filePath: json['filePath'] as String,
        width: (json['width'] as num?)?.toDouble() ?? 200,
        height: (json['height'] as num?)?.toDouble() ?? 150,
        zOrder: (json['zOrder'] as num?)?.toInt() ?? 0,
        locked: json['locked'] as bool? ?? false,
        fractionalIndex: json['fractionalIndex'] as String?,
      );
}
