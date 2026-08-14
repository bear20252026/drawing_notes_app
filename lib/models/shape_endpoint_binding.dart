/// 线性形状端点与目标形状之间的持久化关系。
///
/// 锚点采用目标外接框内的归一化比例，`(0, 0)` 为左上、`(1, 1)` 为右下。
/// 这样目标形状移动或缩放后，端点无需保存失效的绝对坐标，只需按最新 bounds
/// 重投影即可。第一版只供独立绘图文档的直线箭头使用。
class ShapeEndpointBinding {
  ShapeEndpointBinding({
    required this.targetShapeId,
    required double anchorX,
    required double anchorY,
  }) : anchorX = anchorX.clamp(0.0, 1.0),
       anchorY = anchorY.clamp(0.0, 1.0);

  final String targetShapeId;
  final double anchorX;
  final double anchorY;

  ShapeEndpointBinding copy() => ShapeEndpointBinding(
    targetShapeId: targetShapeId,
    anchorX: anchorX,
    anchorY: anchorY,
  );

  Map<String, dynamic> toJson() => {
    'targetShapeId': targetShapeId,
    'anchorX': anchorX,
    'anchorY': anchorY,
  };

  factory ShapeEndpointBinding.fromJson(Map<String, dynamic> json) =>
      ShapeEndpointBinding(
        targetShapeId: json['targetShapeId'] as String,
        anchorX: (json['anchorX'] as num?)?.toDouble() ?? 0.5,
        anchorY: (json['anchorY'] as num?)?.toDouble() ?? 0.5,
      );
}
