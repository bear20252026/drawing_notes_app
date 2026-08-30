// 无限画布群组框（edgeless group）领域模块，1:1 对标 AFFiNE 的 `affine:group`。
// 纯 Dart，仅依赖 dart:ui 的 Offset / Rect（几何），依赖注向 edgeless_doc.dart（聚合根），
// 与 edgeless_connector.dart 同级，为可独立单测的声明式模型。
//
// 设计要点（科学 / 可维护）：
//  1. `EdgelessGroup` 只描述「一组帧的成员关系 + 可选标签 + 颜色」，不持有几何状态；
//     组的外接矩形 `EdgelessDoc.groupBounds` 由成员帧矩形即时推导。
//  2. 组移动语义在聚合根 `moveFrame` 中实现：拖动组内任一帧 → 整组平移（成员相对布局不变），
//     这是 AFFiNE 群组行为的关键一致点。

import 'dart:ui' show Rect;

/// 默认群组框颜色（AFFiNE 群组识别色）。
const String kDefaultGroupColor = '#4CAF50';

/// 无限画布群组框。
class EdgelessGroup {
  const EdgelessGroup({
    required this.id,
    required this.frameIds,
    this.name,
    this.color = kDefaultGroupColor,
  });

  /// 唯一标识。
  final String id;

  /// 成员帧 id 集合（有序，保持成员相对布局）。
  final List<String> frameIds;

  /// 可选组名。
  final String? name;

  /// 组框颜色（CSS 颜色字符串）。
  final String color;

  /// 帧是否为该组成员。
  bool contains(String frameId) => frameIds.contains(frameId);

  EdgelessGroup copyWith({
    List<String>? frameIds,
    String? name,
    String? color,
    bool clearName = false,
  }) => EdgelessGroup(
    id: id,
    frameIds: frameIds ?? this.frameIds,
    name: clearName ? null : (name ?? this.name),
    color: color ?? this.color,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'frameIds': frameIds,
    if (name != null) 'name': name,
    'color': color,
  };

  factory EdgelessGroup.fromJson(Map<String, dynamic> json) => EdgelessGroup(
    id: json['id'] as String,
    frameIds: (json['frameIds'] as List? ?? const [])
        .map((e) => e as String)
        .toList(),
    name: json['name'] as String?,
    color: json['color'] as String? ?? kDefaultGroupColor,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EdgelessGroup &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          _listEquals(frameIds, other.frameIds) &&
          name == other.name &&
          color == other.color;

  @override
  int get hashCode => Object.hash(id, Object.hashAll(frameIds), name, color);

  @override
  String toString() => 'EdgelessGroup(id: $id, frames: ${frameIds.length})';
}

/// 组外接矩形（由成员帧矩形求并集）。空输入返回 null。
///
/// 纯函数、仅依赖 Rect：供群组框渲染、整组缩放/居中计算复用。
/// 聚合根在调用时把成员帧的 `rect` 收集成 `List<Rect>` 传入。
Rect? groupBoundsOf(List<Rect> memberRects) {
  if (memberRects.isEmpty) return null;
  var rect = memberRects.first;
  for (final r in memberRects.skip(1)) {
    rect = rect.expandToInclude(r);
  }
  return rect;
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
