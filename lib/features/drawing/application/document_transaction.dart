import 'package:flutter/foundation.dart' show debugPrint;
import 'document_commands.dart';

/// 批量命令事务（借鉴 iwb_canvas_engine SceneWriteTxn 的原子提交思想，
/// 见 docs/SOURCE_READ_ADAPTATION_REPORT.md）。
///
/// 把多个 [DocCommand] 打包为一个**原子提交**：
/// - [redo]：按序执行全部子命令；任一步抛出异常则逆序回滚已执行部分，
///   保证"全部成功或全部回滚"（原子性）。
/// - [undo]：逆序回滚全部子命令（撤销语义与单命令一致）。
/// - 不可变快照：构造后子命令列表只读，符合 iwb CommittedDocument
///   不可变语义，供审计留痕。
///
/// 用法（批量操作原子化）：
/// ```dart
/// final txn = DocumentTransaction([cmd1, cmd2, cmd3]);
/// txn.redo();          // 原子提交
/// controller.push(txn); // 入撤销栈（undo 整体回滚）
/// ```
class DocumentTransaction extends DocCommand {
  DocumentTransaction(List<DocCommand> commands)
      : _commands = List.unmodifiable(commands) {
    if (commands.isEmpty) {
      throw ArgumentError('DocumentTransaction 至少需要一个子命令');
    }
  }

  /// 子命令列表（不可变快照，构造后只读）。
  final List<DocCommand> _commands;

  /// 子命令数量（供审计/统计）。
  int get length => _commands.length;

  /// 只读访问子命令（审计留痕用）。
  List<DocCommand> get commands => _commands;

  @override
  void redo() {
    var executed = 0;
    try {
      for (final cmd in _commands) {
        cmd.redo();
        executed++;
      }
    } catch (_) {
      // 原子性：回滚已执行部分，保持文档一致后重抛。
      _rollback(executed);
      rethrow;
    }
  }

  @override
  void undo() {
    // 逆序回滚全部子命令（与单命令 undo 语义一致）。
    for (final cmd in _commands.reversed) {
      cmd.undo();
    }
  }

  /// 回滚前 [count] 个已执行的子命令（redo 失败时调用）。
  void _rollback(int count) {
    for (var i = count - 1; i >= 0; i--) {
      try {
        _commands[i].undo();
      } catch (_) {
        // 回滚过程异常不吞掉原始异常，仅记录继续尝试其余回滚。
        debugPrint('[DocumentTransaction] 回滚第 $i 个命令失败');
      }
    }
  }
}
