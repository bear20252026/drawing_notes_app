/// 就地文字编辑会话 Controller（C-04 交互状态机第二批）。
///
/// 把 `EditorPage` 里散落的 `_editingItemId` / `_pendingTextItem` 与
/// [TextEditSessionStateMachine] 收口为单一状态源：
/// - phase 迁移由纯逻辑状态机决定（begin/commit/cancel/reset）；
/// - 会话字段（编辑目标 id、临时文字块）由本 Controller 持有；
/// - 页面 part 经 getter 读、经 [beginEdit]/[completeCommit] 写。
///
/// 不持有 Widget / FocusNode / TextEditingController——这些仍由页面
/// 负责；Controller 只声明「何时该提交/取消/清空会话」。
library;

import 'package:flutter/foundation.dart';

import 'package:drawing_notes_app/core/canvas_model/text_item.dart';
import 'package:drawing_notes_app/features/drawing/application/text_edit_session_state_machine.dart';

/// 就地文字编辑会话状态（C-04：选区/文字/斜杠菜单之外的编辑会话机）。
class EditorInPlaceTextSessionController extends ChangeNotifier {
  EditorInPlaceTextSessionController({TextEditSessionStateMachine? stateMachine})
    : _stateMachine = stateMachine ?? TextEditSessionStateMachine();

  final TextEditSessionStateMachine _stateMachine;

  String? _editingItemId;
  PageTextItem? _pendingTextItem;

  /// 纯逻辑阶段（idle/editing/committing/canceling/settled）。
  TextEditSessionPhase get phase => _stateMachine.phase;

  String? get editingItemId => _editingItemId;
  PageTextItem? get pendingTextItem => _pendingTextItem;

  bool get isEditing => _editingItemId != null || _pendingTextItem != null;

  /// 进入就地编辑。若已在编辑中，先按取消语义收掉上一会话。
  TextEditSessionTransition beginEdit({
    required String id,
    required PageTextItem draft,
  }) {
    if (isEditing) {
      _stateMachine.event(TextEditSessionEvent.cancelRequest);
    }
    final transition = _stateMachine.event(TextEditSessionEvent.begin);
    _editingItemId = id;
    _pendingTextItem = draft;
    notifyListeners();
    return transition;
  }

  /// 显式请求提交（回车 / 点外 / 工具切换前）。
  TextEditSessionTransition requestCommit() =>
      _stateMachine.event(TextEditSessionEvent.commitRequest);

  /// 提交成功后调用：清空会话字段并进入 settled。
  TextEditSessionTransition completeCommit() {
    final transition = _stateMachine.event(TextEditSessionEvent.commitSucceeded);
    _editingItemId = null;
    _pendingTextItem = null;
    notifyListeners();
    return transition;
  }

  /// 请求取消（不生成历史快照的取消路径）。
  TextEditSessionTransition requestCancel() =>
      _stateMachine.event(TextEditSessionEvent.cancelRequest);

  /// 取消完成后调用：与 completeCommit 同样清空会话。
  TextEditSessionTransition completeCancel() => completeCommit();

  /// 强制回到 idle（页面销毁 / 新建画布时）。
  void reset() {
    _stateMachine.event(TextEditSessionEvent.reset);
    _editingItemId = null;
    _pendingTextItem = null;
    notifyListeners();
  }
}
