// 无限画布 note 帧：承载 NoteBlockDoc 及画布位置/层级（F9 自
// edgeless_doc.dart 抽出，2026-09-24）。使用方继续 import
// edgeless_doc.dart（re-export 兼容）或直接本文件。
import 'dart:ui' show Offset, Rect;

import 'package:drawing_notes_app/core/documents/note_block_doc.dart';
/// 无限画布上的 note 帧：承载一个 NoteBlockDoc 及其在画布上的位置/层级。
class NoteFrame {
  const NoteFrame({
    required this.id,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.doc,
    required this.zIndex,
    this.background = '#FFFFFF',
  });

  /// 帧唯一标识。
  final String id;

  /// 画布 X 坐标。
  final double x;

  /// 画布 Y 坐标。
  final double y;

  /// 帧宽度。
  final double w;

  /// 帧高度。
  final double h;

  /// 帧内块文档。
  final NoteBlockDoc doc;

  /// 层级（越大越靠前）。
  final int zIndex;

  /// 背景色（CSS 颜色字符串）。
  final String background;

  /// 矩形区域（由 x/y/w/h 派生）。
  Rect get rect => Rect.fromLTWH(x, y, w, h);

  /// 中心点。
  Offset get center => rect.center;

  /// 是否包含世界坐标点。
  bool contains(Offset worldPoint) => rect.contains(worldPoint);

  NoteFrame copyWith({
    String? id,
    double? x,
    double? y,
    double? w,
    double? h,
    NoteBlockDoc? doc,
    int? zIndex,
    String? background,
  }) => NoteFrame(
    id: id ?? this.id,
    x: x ?? this.x,
    y: y ?? this.y,
    w: w ?? this.w,
    h: h ?? this.h,
    doc: doc ?? this.doc,
    zIndex: zIndex ?? this.zIndex,
    background: background ?? this.background,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'x': x,
    'y': y,
    'w': w,
    'h': h,
    'doc': doc.toJson(),
    'zIndex': zIndex,
    'background': background,
  };

  factory NoteFrame.fromJson(Map<String, dynamic> json) => NoteFrame(
    id: json['id'] as String,
    x: (json['x'] as num).toDouble(),
    y: (json['y'] as num).toDouble(),
    w: (json['w'] as num).toDouble(),
    h: (json['h'] as num).toDouble(),
    doc: NoteBlockDoc.fromJson(json['doc'] as Map<String, dynamic>),
    zIndex: json['zIndex'] as int,
    background: json['background'] as String? ?? '#FFFFFF',
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NoteFrame &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          x == other.x &&
          y == other.y &&
          w == other.w &&
          h == other.h &&
          doc == other.doc &&
          zIndex == other.zIndex &&
          background == other.background;

  @override
  int get hashCode => Object.hash(id, x, y, w, h, doc, zIndex, background);

  @override
  String toString() =>
      'NoteFrame(id: $id, x: $x, y: $y, w: $w, h: $h, z: $zIndex)';
}
