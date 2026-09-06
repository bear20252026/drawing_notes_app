import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/features/drawing/application/document_commands.dart';
import 'package:drawing_notes_app/features/drawing/application/document_transaction.dart';

/// 测试用假命令：记录调用顺序，验证事务的 redo/undo 顺序与原子性。
class _RecordingCommand extends DocCommand {
  _RecordingCommand(this.name, this._log, {this.failOnRedo = false});

  final String name;
  final List<String> _log;
  final bool failOnRedo;

  @override
  void redo() {
    _log.add('redo:$name');
    if (failOnRedo) throw StateError('$name redo 失败');
  }

  @override
  void undo() => _log.add('undo:$name');
}

void main() {
  group('DocumentTransaction', () {
    test('redo 按序执行全部子命令', () {
      final log = <String>[];
      final txn = DocumentTransaction([
        _RecordingCommand('a', log),
        _RecordingCommand('b', log),
        _RecordingCommand('c', log),
      ]);
      txn.redo();
      expect(log, ['redo:a', 'redo:b', 'redo:c']);
    });

    test('undo 逆序回滚全部子命令', () {
      final log = <String>[];
      final txn = DocumentTransaction([
        _RecordingCommand('a', log),
        _RecordingCommand('b', log),
      ]);
      txn.redo();
      log.clear();
      txn.undo();
      expect(log, ['undo:b', 'undo:a']);
    });

    test('redo 失败时原子回滚已执行部分并重抛', () {
      final log = <String>[];
      final txn = DocumentTransaction([
        _RecordingCommand('a', log),
        _RecordingCommand('b', log, failOnRedo: true),
        _RecordingCommand('c', log),
      ]);
      expect(() => txn.redo(), throwsStateError);
      // b 失败 → 回滚已执行的 a；c 未执行。
      expect(log, ['redo:a', 'redo:b', 'undo:a']);
    });

    test('空事务构造抛 ArgumentError', () {
      expect(() => DocumentTransaction([]), throwsArgumentError);
    });

    test('子命令列表不可变（不可变快照语义）', () {
      final txn = DocumentTransaction([_RecordingCommand('a', [])]);
      expect(
        () => txn.commands.add(_RecordingCommand('x', [])),
        throwsUnsupportedError,
      );
      expect(txn.length, 1);
    });

    test('undo 不重抛（撤销路径不回滚自身）', () {
      final log = <String>[];
      final txn = DocumentTransaction([
        _RecordingCommand('a', log),
        _RecordingCommand('b', log),
      ]);
      txn.undo(); // 未 redo 直接 undo：子命令各自幂等处理
      expect(log, ['undo:b', 'undo:a']);
    });
  });
}
