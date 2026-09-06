import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/features/drawing/application/document_commands.dart';
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';

/// 测试用命令：记录 undo/redo 次数，验证事务入栈与原子撤销。
class _CountCommand extends DocCommand {
  _CountCommand(this._redoCount, this._undoCount);

  final List<String> _redoCount;
  final List<String> _undoCount;

  @override
  void redo() => _redoCount.add('r');

  @override
  void undo() => _undoCount.add('u');
}

void main() {
  group('pushTransaction 撤销栈接入', () {
    test('空列表直接忽略（不产生历史条目）', () {
      final controller = DrawingController(
        DrawingDocument(id: 'txn_test', title: '事务测试'),
      );
      controller.pushTransaction([]);
      expect(controller.canUndo, isFalse, reason: '空事务不应入栈');
      controller.dispose();
    });

    test('多命令打包为单条目：一次 undo 整体回滚', () {
      final controller = DrawingController(
        DrawingDocument(id: 'txn_test', title: '事务测试'),
      );
      final redo = <String>[];
      final undo = <String>[];
      controller.pushTransaction([
        _CountCommand(redo, undo),
        _CountCommand(redo, undo),
        _CountCommand(redo, undo),
      ]);
      expect(controller.canUndo, isTrue);
      expect(redo, isEmpty, reason: '命令不自动执行，只入栈');

      controller.undo();
      expect(undo, ['u', 'u', 'u'], reason: '一次 undo 逆序回滚全部 3 个命令');

      controller.redo();
      expect(redo, ['r', 'r', 'r'], reason: '一次 redo 按序重做全部 3 个命令');
      controller.dispose();
    });

    test('事务与单命令共享同一撤销栈（顺序正确）', () {
      final controller = DrawingController(
        DrawingDocument(id: 'txn_test', title: '事务测试'),
      );
      final redo = <String>[];
      final undo = <String>[];

      // 先入单个命令，再入 2 命令事务
      final single = _CountCommand(redo, undo);
      final t1 = _CountCommand(redo, undo);
      final t2 = _CountCommand(redo, undo);
      controller.pushTransaction([single]);
      controller.pushTransaction([t1, t2]);

      controller.undo();
      expect(undo, ['u', 'u'], reason: '先撤销最近的事务（2 命令）');
      controller.undo();
      expect(undo, ['u', 'u', 'u'], reason: '再撤销单命令');
      controller.dispose();
    });
  });
}
