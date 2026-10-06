import 'package:drawing_notes_app/features/drawing/application/document_commands.dart';
import 'package:drawing_notes_app/features/drawing/application/document_edit_history.dart';

import 'drawing_service.dart';

/// Owns command history and saved state for one drawing document.
/// Commands passed to [push] have already been applied by the editing session.
final class HistoryService implements DrawingService {
  HistoryService({int maxEntries = 60})
    : _history = DocumentEditHistory(maxEntries: maxEntries);

  final DocumentEditHistory _history;
  bool _disposed = false;

  bool get isDisposed => _disposed;
  bool get canUndo => !_disposed && _groupDepth == 0 && _history.canUndo;
  bool get canRedo => !_disposed && _groupDepth == 0 && _history.canRedo;
  bool get isDirty => _history.isDirty;
  int get entryCount => _history.entryCount;

  void push(DocCommand command) {
    if (_disposed) return;
    if (_groupDepth > 0) {
      // 分组窗口内：条目等最外层闭合时一次性写入。但「已弄脏」必须当场成立
      // ——否则自动保存会以为这批操作没改过文档，用户的编辑就此丢失。
      _history.markDirty();
      _group.add(command);
      return;
    }
    _history.push(command);
  }

  // ---------------- 命令分组（一批操作 = 一次撤销） ----------------

  int _groupDepth = 0;
  final List<DocCommand> _group = <DocCommand>[];

  /// 分组窗口是否开着（窗口内通知合并、undo/redo 一律拒绝）。
  bool get isGroupOpen => !_disposed && _groupDepth > 0;

  /// 窗口内已累积、尚未写进历史的命令数。
  int get groupedCommandCount => _group.length;

  /// 开启一层分组。支持嵌套：内层并入外层，只有最外层闭合才产出条目。
  void beginGroup() {
    if (_disposed) return;
    _groupDepth++;
  }

  /// 闭合一层分组，返回应交由调用方处置的命令列表（提交=合成一条历史；
  /// 回滚=由调用方逆序 `undo`）；仍在嵌套中时返回 null，调用方据此什么都不做。
  List<DocCommand>? closeGroup() {
    if (_disposed || _groupDepth == 0) return null;
    _groupDepth--;
    if (_groupDepth > 0) return null;
    final commands = List<DocCommand>.of(_group);
    _group.clear();
    return commands;
  }

  /// 直接拆掉全部分组（含嵌套层）并取回窗口内的命令，供回滚逆序撤销。
  List<DocCommand> discardGroup() {
    _groupDepth = 0;
    if (_disposed) return const <DocCommand>[];
    final commands = List<DocCommand>.of(_group);
    _group.clear();
    return commands;
  }

  /// 窗口内拒绝撤销/重做：分组中的命令还没进历史，此时撤销会打到
  /// 分组之前的条目上，把「一批操作」撕成半批——宁可拒绝，不留半成品。
  bool undo() => !_disposed && _groupDepth == 0 && _history.undo();
  bool redo() => !_disposed && _groupDepth == 0 && _history.redo();

  void markDirty() {
    if (!_disposed) _history.markDirty();
  }

  void markSaved() {
    if (!_disposed) _history.markSaved();
  }

  @override
  void dispose() => _disposed = true;
}
