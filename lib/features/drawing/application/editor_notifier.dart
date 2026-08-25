// editor_notifier.dart — Riverpod Notifier 版 EditorViewModel（2026-08-24）。
//
// 迁移自 EditorViewModel (ChangeNotifier)。
// 职责：编辑器顶层工具/模式/选取控制。
// 注意：EditorViewModel 还管理防抖自动保存，该逻辑移至 editor_page_persistence.dart。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/text_item.dart';

/// 编辑器不可变状态。
@immutable
class EditorState {
  const EditorState({
    this.eyedropperActive = false,
    this.textToolActive = false,
    this.linkMode = false,
    this.linkSourceId,
    this.selectionDone = false,
    this.selectedItemId,
    this.editingItemId,
    this.pendingTextItem,
  });

  final bool eyedropperActive;
  final bool textToolActive;
  final bool linkMode;
  final String? linkSourceId;
  final bool selectionDone;
  final String? selectedItemId;
  final String? editingItemId;
  final PageTextItem? pendingTextItem;

  EditorState copyWith({
    bool? eyedropperActive,
    bool? textToolActive,
    bool? linkMode,
    String? linkSourceId,
    bool clearLinkSourceId = false,
    bool? selectionDone,
    String? selectedItemId,
    bool clearSelectedItemId = false,
    String? editingItemId,
    bool clearEditingItemId = false,
    PageTextItem? pendingTextItem,
    bool clearPendingTextItem = false,
  }) {
    return EditorState(
      eyedropperActive: eyedropperActive ?? this.eyedropperActive,
      textToolActive: textToolActive ?? this.textToolActive,
      linkMode: linkMode ?? this.linkMode,
      linkSourceId: clearLinkSourceId ? null : (linkSourceId ?? this.linkSourceId),
      selectionDone: selectionDone ?? this.selectionDone,
      selectedItemId: clearSelectedItemId ? null : (selectedItemId ?? this.selectedItemId),
      editingItemId: clearEditingItemId ? null : (editingItemId ?? this.editingItemId),
      pendingTextItem: clearPendingTextItem ? null : (pendingTextItem ?? this.pendingTextItem),
    );
  }
}

/// 编辑器工具/模式状态管理（Riverpod Notifier）。
///
/// 替代原 EditorViewModel (ChangeNotifier)。
/// 注意：防抖自动保存逻辑由 editor_page_persistence.dart 的 _scheduleAutosave 处理。
class EditorNotifier extends Notifier<EditorState> {
  @override
  EditorState build() => const EditorState();

  // ─── 工具状态 ───

  void setEyedropperActive(bool v) {
    state = state.copyWith(eyedropperActive: v);
  }

  void setTextToolActive(bool v) {
    state = state.copyWith(textToolActive: v);
  }

  void setSelectionDone(bool v) {
    state = state.copyWith(selectionDone: v);
  }

  void setLinkMode(bool v) {
    state = state.copyWith(linkMode: v);
  }

  void setLinkSourceId(String? v) {
    state = state.copyWith(
      linkSourceId: v,
      clearLinkSourceId: v == null,
    );
  }

  // ─── 便捷只读属性（供 EditorPage part 文件兼容使用） ───

  bool get eyedropperActive => state.eyedropperActive;
  bool get textToolActive => state.textToolActive;
  bool get linkMode => state.linkMode;
  String? get linkSourceId => state.linkSourceId;
  bool get selectionDone => state.selectionDone;
  String? get selectedItemId => state.selectedItemId;
  String? get editingItemId => state.editingItemId;
  PageTextItem? get pendingTextItem => state.pendingTextItem;

  // ─── 工具切换（UI 只调用这些方法） ───

  /// 进入吸管取色模式。
  void selectEyedropper() {
    state = state.copyWith(
      eyedropperActive: true,
      textToolActive: false,
    );
  }

  /// 切到文字工具（点击画布放置文字）。
  void selectText() {
    state = state.copyWith(
      textToolActive: true,
      eyedropperActive: false,
    );
  }

  /// 连线模式开关（D1：依次点选两个元素创建连接）。
  void toggleLinkMode() {
    state = state.copyWith(
      linkMode: !state.linkMode,
      clearLinkSourceId: true,
    );
  }

  /// 选区完成后置位（供画布手势回调调用）。
  void markSelectionDone() {
    state = state.copyWith(selectionDone: true);
  }

  /// 退出吸管/文字模式（点击画布其他位置时）。
  void clearTools() {
    state = state.copyWith(
      eyedropperActive: false,
      textToolActive: false,
    );
  }

  // ─── 混排对象 ───

  void selectItem(String id) {
    state = state.copyWith(selectedItemId: id);
  }

  void clearSelection() {
    state = state.copyWith(clearSelectedItemId: true);
  }

  void startEditing(String id, PageTextItem pending) {
    state = state.copyWith(
      editingItemId: id,
      pendingTextItem: pending,
    );
  }

  void finishEditing() {
    state = state.copyWith(
      clearEditingItemId: true,
      clearPendingTextItem: true,
    );
  }
}

/// 编辑器状态 Provider。
final editorProvider = NotifierProvider<EditorNotifier, EditorState>(
  EditorNotifier.new,
);
