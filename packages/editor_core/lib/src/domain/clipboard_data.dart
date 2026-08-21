// editor_core——ClipboardData 剪贴板（Excalidraw 借鉴——2026-08-21）。
//
// Excalidraw Clipboard 本地化——复制/粘贴/剪切元素。
// 纯 Dart 不可变模型——可独立测试——不搞崩。
//
// Excalidraw 原版参考：
// - clipboard.ts——复制/粘贴/剪切操作
// - 元素集合 + 偏移量（粘贴时偏移避免重叠）
library;

import 'line_item.dart';
import 'document_v2.dart';

/// 剪贴板数据（Excalidraw Clipboard 本地化——不可变）。
///
/// 存储被复制/剪切的元素集合，粘贴时可带偏移量。
class ClipboardData {
  const ClipboardData({
    this.strokes = const [],
    this.shapes = const [],
    this.texts = const [],
    this.images = const [],
    this.tables = const [],
    this.notes = const [],
    this.offsetX = 20.0,
    this.offsetY = 20.0,
  });

  final List<LineItem> strokes;
  final List<ShapeItem> shapes;
  final List<TextItem> texts;
  final List<ImageItem> images;
  final List<dynamic> tables; // TableV2
  final List<dynamic> notes; // NoteItem
  final double offsetX;
  final double offsetY;

  /// 是否为空。
  bool get isEmpty =>
      strokes.isEmpty &&
      shapes.isEmpty &&
      texts.isEmpty &&
      images.isEmpty &&
      tables.isEmpty &&
      notes.isEmpty;

  /// 元素总数。
  int get count =>
      strokes.length + shapes.length + texts.length + images.length + tables.length + notes.length;

  ClipboardData copyWith({
    List<LineItem>? strokes,
    List<ShapeItem>? shapes,
    List<TextItem>? texts,
    List<ImageItem>? images,
    List<dynamic>? tables,
    List<dynamic>? notes,
    double? offsetX,
    double? offsetY,
  }) {
    return ClipboardData(
      strokes: strokes ?? this.strokes,
      shapes: shapes ?? this.shapes,
      texts: texts ?? this.texts,
      images: images ?? this.images,
      tables: tables ?? this.tables,
      notes: notes ?? this.notes,
      offsetX: offsetX ?? this.offsetX,
      offsetY: offsetY ?? this.offsetY,
    );
  }

  /// 增加偏移量（连续粘贴时避免重叠——Excalidraw 模式）。
  ClipboardData withNextOffset() {
    return copyWith(offsetX: offsetX + 20, offsetY: offsetY + 20);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClipboardData && count == other.count;

  @override
  int get hashCode => count.hashCode;
}
