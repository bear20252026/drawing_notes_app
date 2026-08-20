// editor_core——NoteItem 便签块（AFFiNE 借鉴——2026-08-21）。
//
// sticky note（便签块——背景色 + 文本）本地化——不可变——纯 Dart。
// AFFiNE edgeless 画布便签（sticky note）本地化——不搞崩。
library;

/// 便签块（AFFiNE sticky note 借鉴——不可变）。
class NoteItem {
  const NoteItem({
    required this.id,
    required this.content,
    required this.x,
    required this.y,
    this.width = 200,
    this.height = 150,
    this.backgroundColor = '#FFF9C4', // 默认黄便签（AFFiNE 风格）。
  });

  final String id;
  final String content;
  final double x;
  final double y;
  final double width;
  final double height;

  /// 背景色（十六进制 #RRGGBB）。
  final String backgroundColor;

  NoteItem copyWith({
    String? content,
    double? x,
    double? y,
    double? width,
    double? height,
    String? backgroundColor,
  }) {
    return NoteItem(
      id: id,
      content: content ?? this.content,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      backgroundColor: backgroundColor ?? this.backgroundColor,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NoteItem &&
          id == other.id &&
          content == other.content &&
          x == other.x &&
          y == other.y &&
          backgroundColor == other.backgroundColor;

  @override
  int get hashCode => Object.hash(id, content, x, y, backgroundColor);
}
