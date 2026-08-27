import 'package:drawing_notes_app/features/drawing/application/document_commands.dart';

/// 绘图文档的可逆编辑历史与保存状态。
///
/// 此协作者只管理命令入栈、撤销/重做游标、重做分支裁剪和未保存标记；具体命令
/// 仍由调用方执行，并通过 [DocCommand] 内部的窄上下文回写文档与渲染缓存。
class DocumentEditHistory {
  DocumentEditHistory({required this.maxEntries})
    : assert(maxEntries > 0, '历史栈上限必须大于 0');

  final int maxEntries;
  final List<DocCommand> _entries = <DocCommand>[];
  int _position = 0;
  bool _isDirty = false;

  bool get canUndo => _position > 0;
  bool get canRedo => _position < _entries.length;
  bool get isDirty => _isDirty;

  /// 当前历史条目数，仅用于测试、诊断和后续编辑器遥测。
  int get entryCount => _entries.length;

  /// 当前撤销游标；[0] 表示未应用任何历史命令。
  int get position => _position;

  /// 文档内容在不生成历史条目时发生变化（例如命令回放）时调用。
  void markDirty() => _isDirty = true;

  void markSaved() => _isDirty = false;

  /// 记录一条已执行的命令。
  ///
  /// 若游标处于历史中间位置，先裁剪不可再重做的旧分支；超出容量时丢弃最早
  /// 条目并同步校正游标，行为与常见绘图编辑器一致。
  void push(DocCommand command) {
    markDirty();
    if (_position < _entries.length) {
      _entries.removeRange(_position, _entries.length);
    }
    _entries.add(command);
    if (_entries.length > maxEntries) {
      final overflow = _entries.length - maxEntries;
      _entries.removeRange(0, overflow);
      _position = (_position - overflow).clamp(0, _entries.length);
    }
    _position = _entries.length;
  }

  /// 撤销最新已应用的命令；无命令时返回 false。
  bool undo() {
    if (!canUndo) return false;
    _position--;
    _entries[_position].undo();
    return true;
  }

  /// 重做下一条已撤销的命令；无命令时返回 false。
  bool redo() {
    if (!canRedo) return false;
    _entries[_position].redo();
    _position++;
    return true;
  }
}
