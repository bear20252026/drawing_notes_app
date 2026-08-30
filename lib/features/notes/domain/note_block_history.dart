/// 块文档撤销/重做历史栈（纯逻辑）。
///
/// 基于 [NoteBlockDoc] 快照实现 undo/redo，支持：
/// - 连续同块文本编辑按时间窗合并（一次 undo 回退整段输入）
/// - 快照去重（相同文档不重复压栈）
/// - 撤销上限（防内存膨胀）
/// - 注入时钟（纯逻辑可测）
library;

import 'package:drawing_notes_app/features/notes/domain/note_block_doc.dart';

/// 历史条目：记录一次文档快照及元数据（用于合并判断）。
class _HistoryEntry {
  _HistoryEntry(this.doc, this.timestamp, {this.editedBlockId});

  /// 文档快照。
  final NoteBlockDoc doc;

  /// 入栈时间戳（毫秒）。
  final int timestamp;

  /// 本次编辑的块 ID（纯文本编辑时记录，用于合并判断）。
  final String? editedBlockId;
}

/// 块文档撤销/重做历史栈。
///
/// 纯 Dart 实现，无 Flutter/io 依赖，通过注入 [clock] 保持可测性。
class NoteBlockHistory {
  /// 创建历史栈。
  ///
  /// [maxSteps] 为撤销上限（默认 100）。
  /// [mergeWindowMs] 为同块文本编辑合并时间窗（默认 800ms）。
  /// [clock] 为时钟函数，返回当前毫秒时间戳（默认 DateTime.now）。
  NoteBlockHistory({
    this.maxSteps = 100,
    this.mergeWindowMs = 800,
    int Function()? clock,
  }) : _clock = clock ?? _defaultClock;

  /// 撤销上限。
  final int maxSteps;

  /// 同块文本编辑合并时间窗（毫秒）。
  final int mergeWindowMs;

  /// 时钟函数。
  final int Function() _clock;

  /// 撤销栈（栈底=最旧，栈顶=最新）。
  final List<_HistoryEntry> _undoStack = [];

  /// 重做栈。
  final List<NoteBlockDoc> _redoStack = [];

  /// 静态默认时钟。
  static int _defaultClock() => DateTime.now().millisecondsSinceEpoch;

  /// 当前指针（指向下一次 undo 要返回的文档在 _undoStack 中的索引）。
  int _pointer = -1;

  /// 是否可以撤销。
  bool get canUndo => _pointer >= 0;

  /// 是否可以重做。
  bool get canRedo => _redoStack.isNotEmpty;

  /// 当前文档（栈顶快照，若无历史返回 null）。
  NoteBlockDoc? get current => (_pointer >= 0 && _pointer < _undoStack.length)
      ? _undoStack[_pointer].doc
      : null;

  /// 压入新快照。
  ///
  /// - 若新文档与栈顶快照相同（去重），不压栈。
  /// - 若新文档是对同一块的纯文本编辑且在合并时间窗内，替换栈顶（合并）。
  /// - 否则压入新条目。
  /// - undo 后 push 会清空 redo 分支（标准编辑器语义）。
  void push(NoteBlockDoc doc) {
    // 去重：与栈顶相同则不压
    if (_undoStack.isNotEmpty && _lastDoc == doc) return;

    // 判断是否可以合并（同块纯文本编辑 + 时间窗内）
    final now = _clock();
    final lastEntry = _undoStack.isNotEmpty ? _undoStack.last : null;
    final editedBlockId = _detectSingleBlockTextEdit(lastEntry?.doc, doc);

    if (lastEntry != null &&
        editedBlockId != null &&
        lastEntry.editedBlockId == editedBlockId &&
        now - lastEntry.timestamp < mergeWindowMs) {
      // 合并：替换栈顶
      _undoStack[_undoStack.length - 1] = _HistoryEntry(
        doc,
        now,
        editedBlockId: editedBlockId,
      );
      // undo 后 push 清空 redo
      _redoStack.clear();
      return;
    }

    // 新条目：如果 undo 过，截断指针之后的分支
    if (_pointer < _undoStack.length - 1) {
      _undoStack.removeRange(_pointer + 1, _undoStack.length);
    }

    // undo 后 push 清空 redo
    _redoStack.clear();

    _undoStack.add(_HistoryEntry(doc, now, editedBlockId: editedBlockId));
    _pointer = _undoStack.length - 1;

    // 超上限丢弃最旧
    if (_undoStack.length > maxSteps) {
      _undoStack.removeAt(0);
      _pointer--;
    }
  }

  /// 撤销：返回上一个文档快照。
  ///
  /// 若无可撤销返回 null。
  NoteBlockDoc? undo() {
    if (!canUndo) return null;
    final entry = _undoStack[_pointer];
    _redoStack.add(entry.doc);
    _pointer--;
    return current;
  }

  /// 重做：返回下一个文档快照。
  ///
  /// 若无可重做返回 null。
  NoteBlockDoc? redo() {
    if (!canRedo) return null;
    _pointer++;
    return _undoStack[_pointer].doc;
  }

  /// 清空历史。
  void clear() {
    _undoStack.clear();
    _redoStack.clear();
    _pointer = -1;
  }

  /// 栈顶文档。
  NoteBlockDoc? get _lastDoc =>
      _undoStack.isNotEmpty ? _undoStack.last.doc : null;

  /// 检测两次快照之间是否只有一个块的纯文本发生变化。
  ///
  /// 若是，返回被编辑块 ID；否则返回 null（结构变化或多次编辑）。
  String? _detectSingleBlockTextEdit(NoteBlockDoc? prev, NoteBlockDoc? next) {
    if (prev == null || next == null) return null;

    final prevBody = prev.body;
    final nextBody = next.body;

    // 结构不同（块数量变化）→ 不是纯文本编辑
    if (prevBody.length != nextBody.length) return null;

    String? editedId;
    for (var i = 0; i < prevBody.length; i++) {
      final p = prevBody[i];
      final n = nextBody[i];
      if (p == n) continue;

      // 块 ID 必须相同
      if (p.id != n.id) return null;
      // 类型必须相同
      if (p.type != n.type) return null;
      // props 必须相同（浅比较）
      if (!_propsEqual(p.props, n.props)) return null;
      // children 必须相同（引用或结构）
      if (p.children.length != n.children.length) return null;

      // 只允许 text 字段变化
      if (p.text != n.text) {
        if (editedId != null) return null; // 第二个块也有变化 → 非单次编辑
        editedId = p.id;
      }
    }

    return editedId;
  }

  bool _propsEqual(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || a[key] != b[key]) return false;
    }
    return true;
  }

  @override
  String toString() =>
      'NoteBlockHistory(undo: ${_undoStack.length}, redo: ${_redoStack.length}, pointer: $_pointer)';
}
