// editor_core——InlineEditState 行内编辑（Excalidraw WYSIWYG 借鉴——2026-08-21）。
//
// Excalidraw wysiwyg/ 本地化——行内文本编辑状态机。
// 纯 Dart 不可变模型——可独立测试——不搞崩。
//
// Excalidraw 原版参考：
// - wysiwyg/ 目录——What You See Is What You Get 行内编辑
// - 编辑状态机（idle → editing → committing/aborting）
// - 光标位置/选区/格式状态
library;

import 'rich_text_block.dart';

/// 行内编辑状态枚举（Excalidraw WYSIWYG 状态机借鉴）。
enum InlineEditPhase {
  /// 空闲（未编辑）。
  idle,

  /// 编辑中（光标激活——输入/选区/格式操作）。
  editing,

  /// 提交中（保存变更——退出编辑）。
  committing,

  /// 中止中（取消变更——恢复原值）。
  aborting,
}

/// 光标位置（行内编辑——不可变）。
class CursorPosition {
  const CursorPosition({required this.offset, this.selectionEnd});

  /// 光标偏移量（字符位置）。
  final int offset;

  /// 选区结束位置（null = 无选区——光标闪烁）。
  final int? selectionEnd;

  /// 是否有选区。
  bool get hasSelection => selectionEnd != null && selectionEnd != offset;

  /// 选区长度。
  int get selectionLength => hasSelection ? (selectionEnd! - offset).abs() : 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CursorPosition && offset == other.offset && selectionEnd == other.selectionEnd;

  @override
  int get hashCode => Object.hash(offset, selectionEnd);
}

/// 行内编辑状态（Excalidraw WYSIWYG 本地化——不可变）。
///
/// 管理文本编辑状态机：idle → editing → committing/aborting。
/// 包含编辑内容/光标/格式/原始值（用于回滚）。
class InlineEditState {
  const InlineEditState({
    this.phase = InlineEditPhase.idle,
    this.elementId = '',
    this.content = '',
    this.originalContent = '',
    this.cursor = const CursorPosition(offset: 0),
    this.format = const TextFormat(),
    this.originalFormat = const TextFormat(),
  });

  final InlineEditPhase phase;
  final String elementId;
  final String content;
  final String originalContent;
  final CursorPosition cursor;
  final TextFormat format;
  final TextFormat originalFormat;

  /// 是否在编辑中。
  bool get isEditing => phase == InlineEditPhase.editing;

  /// 是否有未保存变更。
  bool get hasChanges => content != originalContent || format != originalFormat;

  InlineEditState copyWith({
    InlineEditPhase? phase,
    String? elementId,
    String? content,
    String? originalContent,
    CursorPosition? cursor,
    TextFormat? format,
    TextFormat? originalFormat,
  }) {
    return InlineEditState(
      phase: phase ?? this.phase,
      elementId: elementId ?? this.elementId,
      content: content ?? this.content,
      originalContent: originalContent ?? this.originalContent,
      cursor: cursor ?? this.cursor,
      format: format ?? this.format,
      originalFormat: originalFormat ?? this.originalFormat,
    );
  }

  /// 开始编辑（idle → editing）。
  InlineEditState startEditing(String elementId, String content, TextFormat format) {
    return InlineEditState(
      phase: InlineEditPhase.editing,
      elementId: elementId,
      content: content,
      originalContent: content,
      cursor: CursorPosition(offset: content.length),
      format: format,
      originalFormat: format,
    );
  }

  /// 提交编辑（editing → committing）。
  InlineEditState commit() {
    return copyWith(phase: InlineEditPhase.committing);
  }

  /// 中止编辑（editing → aborting——恢复原值）。
  InlineEditState abort() {
    return InlineEditState(
      phase: InlineEditPhase.aborting,
      elementId: elementId,
      content: originalContent,
      originalContent: originalContent,
      cursor: const CursorPosition(offset: 0),
      format: originalFormat,
      originalFormat: originalFormat,
    );
  }

  /// 完成（committing/aborting → idle）。
  InlineEditState finish() {
    return const InlineEditState();
  }

  /// 输入字符（editing 状态）。
  InlineEditState insertText(String text) {
    if (!isEditing) return this;
    final before = content.substring(0, cursor.offset);
    final after = content.substring(cursor.offset);
    final newContent = before + text + after;
    return copyWith(
      content: newContent,
      cursor: CursorPosition(offset: cursor.offset + text.length),
    );
  }

  /// 删除字符（backspace——editing 状态）。
  InlineEditState deleteBackward() {
    if (!isEditing || cursor.offset == 0) return this;
    final before = content.substring(0, cursor.offset - 1);
    final after = content.substring(cursor.offset);
    return copyWith(
      content: before + after,
      cursor: CursorPosition(offset: cursor.offset - 1),
    );
  }

  /// 移动光标。
  InlineEditState moveCursor(int offset) {
    final clamped = offset.clamp(0, content.length);
    return copyWith(cursor: CursorPosition(offset: clamped));
  }

  /// 切换格式（加粗/斜体——editing 状态）。
  InlineEditState toggleBold() {
    if (!isEditing) return this;
    return copyWith(format: format.copyWith(bold: !format.bold));
  }

  InlineEditState toggleItalic() {
    if (!isEditing) return this;
    return copyWith(format: format.copyWith(italic: !format.italic));
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InlineEditState && phase == other.phase && elementId == other.elementId && content == other.content;

  @override
  int get hashCode => Object.hash(phase, elementId, content);
}
