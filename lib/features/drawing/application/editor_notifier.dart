// editor_notifier.dart——EditorViewModel 的 Riverpod Notifier 迁移（P2 #22 Phase 2）。
//
// 将 EditorViewModel (ChangeNotifier) 迁移为 EditorNotifier (Riverpod Notifier)。
// 迁移策略：不可变 EditorState + copyWith 模式 + 变更方法只赋 state。
//
// 状态字段（从 EditorViewModel 1:1 迁移）：
// - eyedropperActive：吸管模式
// - textToolActive：文字工具模式
// - selectionDone：选区完成
// - linkMode：链接模式
// - linkSourceId：链接源 ID
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 编辑器状态（不可变——应对 Riverpod == 过滤语义）。
class EditorState {
  const EditorState({
    this.eyedropperActive = false,
    this.textToolActive = false,
    this.selectionDone = false,
    this.linkMode = false,
    this.linkSourceId,
  });

  /// 吸管模式：激活时点击画布取色，取色后自动退出。
  final bool eyedropperActive;

  /// 文字工具模式：激活时点击画布弹出文字输入框。
  final bool textToolActive;

  /// 选区是否已完成（完成后再拖动 = 移动选中内容，而非新建选区）。
  final bool selectionDone;

  /// 链接模式：用于项目间链接创建流程。
  final bool linkMode;

  /// 链接源对象 ID（链接模式中，第一个被点击的对象 ID）。
  final String? linkSourceId;

  EditorState copyWith({
    bool? eyedropperActive,
    bool? textToolActive,
    bool? selectionDone,
    bool? linkMode,
    String? linkSourceId,
    bool clearLinkSourceId = false,
  }) => EditorState(
        eyedropperActive: eyedropperActive ?? this.eyedropperActive,
        textToolActive: textToolActive ?? this.textToolActive,
        selectionDone: selectionDone ?? this.selectionDone,
        linkMode: linkMode ?? this.linkMode,
        linkSourceId:
            clearLinkSourceId ? null : (linkSourceId ?? this.linkSourceId),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EditorState &&
          other.eyedropperActive == eyedropperActive &&
          other.textToolActive == textToolActive &&
          other.selectionDone == selectionDone &&
          other.linkMode == linkMode &&
          other.linkSourceId == linkSourceId;

  @override
  int get hashCode => Object.hash(
        eyedropperActive,
        textToolActive,
        selectionDone,
        linkMode,
        linkSourceId,
      );
}

/// 编辑器 UI 状态 Notifier（P2 #22 Phase 2——从 ChangeNotifier 迁移）。
///
/// 纯 UI 状态：吸管/文字工具/选区完成/链接模式。
/// 与 DrawingController 分离（DrawingController 管画笔域——后续 Phase 迁移）。
///
/// API 与旧 EditorViewModel 1:1 对应——减少调用方修改量。
class EditorNotifier extends Notifier<EditorState> {
  @override
  EditorState build() => const EditorState();

  // ── 纯状态 setter（供 editor_page 委托接入） ──

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
    state = state.copyWith(linkSourceId: v);
  }

  // ── 组合操作（从 EditorViewModel 迁移——设置多个状态字段） ──

  /// 退出吸管/文字模式（点击画布其他位置时）。
  void clearTools() {
    state = state.copyWith(
      eyedropperActive: false,
      textToolActive: false,
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
}

/// 编辑器 UI 状态 Provider。
final editorProvider =
    NotifierProvider<EditorNotifier, EditorState>(EditorNotifier.new);
