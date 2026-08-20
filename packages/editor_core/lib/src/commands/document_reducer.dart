// editor_core——DocumentReducer（批次 C——2026-08-18——专家方案 V2 命令模式）。
//
// 状态 + 命令 → 新状态 + 逆命令（immutable 模式——撤销/重做基础）。
// Reducer 是命令应用的单一入口，保证状态变更的一致性。
library;

import '../domain/document_v2.dart';
import 'document_command.dart';

/// 历史条目（撤销/重做栈单元）。
class HistoryEntry {
  const HistoryEntry({
    required this.command,
    required this.inverseCommand,
    required this.revisionBefore,
  });

  /// 执行的命令。
  final DocumentCommand command;

  /// 逆命令（用于撤销）。
  final DocumentCommand inverseCommand;

  /// 执行前的 revision（用于 undo 时恢复）。
  final int revisionBefore;
}

/// DocumentReducer（状态 + 命令 → 新状态 + 逆命令）。
///
/// 遵循专家方案批次 C：
/// - state + command → new state + inverse command
/// - 不直接修改旧对象（immutable）
/// - 实现撤销/重做（history stack）
class DocumentReducer {
  DocumentReducer(this._current);

  /// 当前文档状态。
  DocumentV2 _current;

  /// 当前文档状态（只读）。
  DocumentV2 get current => _current;

  /// 撤销栈（执行命令时记录逆命令）。
  final List<HistoryEntry> _undoStack = [];

  /// 重做栈（撤销时记录命令）。
  final List<HistoryEntry> _redoStack = [];

  /// 是否可撤销。
  bool get canUndo => _undoStack.isNotEmpty;

  /// 是否可重做。
  bool get canRedo => _redoStack.isNotEmpty;

  /// 执行命令（状态 + 命令 → 新状态 + 逆命令入栈）。
  ///
  /// 返回执行后的文档状态。
  DocumentV2 execute(DocumentCommand command) {
    final inverseCommand = command.inverse();
    final revisionBefore = _current.revision;
    final newState = command.apply(_current);

    // 入撤销栈。
    _undoStack.add(HistoryEntry(
      command: command,
      inverseCommand: inverseCommand,
      revisionBefore: revisionBefore,
    ));

    // 清空重做栈（新命令覆盖重做历史）。
    _redoStack.clear();

    // 更新当前状态（immutable）。
    _current = newState;
    return _current;
  }

  /// 撤销（执行逆命令，返回撤销后的文档状态）。
  ///
  /// 关键：恢复到执行前的 revision（不是让逆命令再增加 revision）。
  DocumentV2? undo() {
    if (!canUndo) return null;

    final entry = _undoStack.removeLast();
    final undoneState = entry.inverseCommand.apply(_current);

    // 恢复到执行前的 revision（逆命令本身会增加 revision，这里纠正）。
    final correctedState = undoneState.copyWith(revision: entry.revisionBefore);

    // 入重做栈（重做时执行原命令——记录 undo 前的 revision）。
    _redoStack.add(HistoryEntry(
      command: entry.command,
      inverseCommand: entry.inverseCommand,
      revisionBefore: _current.revision,
    ));

    _current = correctedState;
    return _current;
  }

  /// 重做（执行命令，返回重做后的文档状态）。
  ///
  /// 关键：恢复到撤销前的 revision。
  DocumentV2? redo() {
    if (!canRedo) return null;

    final entry = _redoStack.removeLast();
    final redoneState = entry.command.apply(_current);

    // 恢复到撤销前的 revision。
    final correctedState = redoneState.copyWith(revision: entry.revisionBefore);

    // 入撤销栈。
    _undoStack.add(HistoryEntry(
      command: entry.command,
      inverseCommand: entry.inverseCommand,
      revisionBefore: _current.revision,
    ));

    _current = correctedState;
    return _current;
  }

  /// 清空历史（用于加载新文档时）。
  void clearHistory() {
    _undoStack.clear();
    _redoStack.clear();
  }
}
