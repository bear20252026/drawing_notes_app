// 无限画布连接线（edgeless connector）领域模块，1:1 对标 AFFiNE 的 `affine:connector`。
// 纯 Dart，仅依赖 dart:ui 的 Offset / Rect（几何），不依赖 EdgelessDoc / NoteFrame，
// 从而与聚合根 edgeless_doc.dart 解耦、避免循环引用。
//
// 设计要点（科学 / 可维护）：
//  1. 声明式而非过程式——NoteConnector 只记录「来源帧 + 目标帧 + 各自锚点 + 样式」，
//     不缓存任何世界坐标；锚点坐标由帧的当前 rect 在渲染时即时推导（见 connectorAnchorPoint）。
//  2. 因此移动/缩放/置顶任一帧，连接线都自动跟随，无需任何额外同步逻辑——没有陈旧坐标风险。
//  3. 几何纯函数与模型分离，可独立单测。

import 'dart:ui' show Offset, Rect;

/// 连接线锚点：帧上朝向对端的那一侧边中点。
enum ConnectorAnchor { top, right, bottom, left }

/// 默认连接线颜色（AFFiNE 品牌紫）。
const String kDefaultConnectorColor = '#7C4DFF';

/// 默认连接线宽度。
const double kDefaultConnectorWidth = 2.0;

/// 帧一侧锚点的世界坐标。
///
/// - [frameRect]：帧的世界矩形（`NoteFrame.rect`）。
/// - [anchor]：锚定到帧的哪一侧。
Offset connectorAnchorPoint(Rect frameRect, ConnectorAnchor anchor) {
  switch (anchor) {
    case ConnectorAnchor.top:
      return Offset(frameRect.center.dx, frameRect.top);
    case ConnectorAnchor.bottom:
      return Offset(frameRect.center.dx, frameRect.bottom);
    case ConnectorAnchor.left:
      return Offset(frameRect.left, frameRect.center.dy);
    case ConnectorAnchor.right:
      return Offset(frameRect.right, frameRect.center.dy);
  }
}

/// 根据两帧相对位置自动推荐「朝彼此」的锚点组合。
///
/// 以两帧中心连线占优的轴为准：
///   - 水平占优 → 来源在左则 (right, left)，否则 (left, right)；
///   - 垂直占优 → 来源在上则 (bottom, top)，否则 (top, bottom)。
({ConnectorAnchor from, ConnectorAnchor to}) autoConnectorAnchors(
  Rect source,
  Rect target,
) {
  final dx = target.center.dx - source.center.dx;
  final dy = target.center.dy - source.center.dy;
  if (dx.abs() >= dy.abs()) {
    return dx >= 0
        ? (from: ConnectorAnchor.right, to: ConnectorAnchor.left)
        : (from: ConnectorAnchor.left, to: ConnectorAnchor.right);
  }
  return dy >= 0
      ? (from: ConnectorAnchor.bottom, to: ConnectorAnchor.top)
      : (from: ConnectorAnchor.top, to: ConnectorAnchor.bottom);
}

/// 无限画布连接线元素。
///
/// 一条连接线连接两个帧的指定边。方向语义：[fromFrameId] 为起点帧、[toFrameId] 为终点帧。
class NoteConnector {
  const NoteConnector({
    required this.id,
    required this.fromFrameId,
    required this.toFrameId,
    required this.fromAnchor,
    required this.toAnchor,
    this.color = kDefaultConnectorColor,
    this.width = kDefaultConnectorWidth,
    this.label,
  });

  /// 唯一标识。
  final String id;

  /// 起点帧 id。
  final String fromFrameId;

  /// 终点帧 id。
  final String toFrameId;

  /// 起点帧锚点。
  final ConnectorAnchor fromAnchor;

  /// 终点帧锚点。
  final ConnectorAnchor toAnchor;

  /// 线色（CSS 颜色字符串）。
  final String color;

  /// 线宽。
  final double width;

  /// 可选标签。
  final String? label;

  /// 是否自环（连接到自己）。
  bool get isSelfLoop => fromFrameId == toFrameId;

  NoteConnector copyWith({
    String? id,
    String? fromFrameId,
    String? toFrameId,
    ConnectorAnchor? fromAnchor,
    ConnectorAnchor? toAnchor,
    String? color,
    double? width,
    String? label,
    bool clearLabel = false,
  }) =>
      NoteConnector(
        id: id ?? this.id,
        fromFrameId: fromFrameId ?? this.fromFrameId,
        toFrameId: toFrameId ?? this.toFrameId,
        fromAnchor: fromAnchor ?? this.fromAnchor,
        toAnchor: toAnchor ?? this.toAnchor,
        color: color ?? this.color,
        width: width ?? this.width,
        label: clearLabel ? null : (label ?? this.label),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'fromFrameId': fromFrameId,
        'toFrameId': toFrameId,
        'fromAnchor': fromAnchor.name,
        'toAnchor': toAnchor.name,
        'color': color,
        'width': width,
        if (label != null) 'label': label,
      };

  factory NoteConnector.fromJson(Map<String, dynamic> json) => NoteConnector(
        id: json['id'] as String,
        fromFrameId: json['fromFrameId'] as String,
        toFrameId: json['toFrameId'] as String,
        fromAnchor: ConnectorAnchor.values.byName(json['fromAnchor'] as String),
        toAnchor: ConnectorAnchor.values.byName(json['toAnchor'] as String),
        color: json['color'] as String? ?? kDefaultConnectorColor,
        width: (json['width'] as num?)?.toDouble() ?? kDefaultConnectorWidth,
        label: json['label'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NoteConnector &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          fromFrameId == other.fromFrameId &&
          toFrameId == other.toFrameId &&
          fromAnchor == other.fromAnchor &&
          toAnchor == other.toAnchor &&
          color == other.color &&
          width == other.width &&
          label == other.label;

  @override
  int get hashCode => Object.hash(
      id, fromFrameId, toFrameId, fromAnchor, toAnchor, color, width, label);

  @override
  String toString() =>
      'NoteConnector(id: $id, $fromFrameId:${fromAnchor.name}→$toFrameId:${toAnchor.name})';
}
