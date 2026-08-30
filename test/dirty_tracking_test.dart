import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/features/drawing/application/document_commands.dart';
import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/core/canvas_model/document.dart';

/// 测试用命令：入栈验证保存状态跟踪。
class _TouchCommand extends DocCommand {
  _TouchCommand(this._controller);

  final DrawingController _controller;

  @override
  void redo() => _controller.touchDocument();

  @override
  void undo() => _controller.touchDocument();
}

void main() {
  group('保存状态跟踪（Saber markLastChangeAsSaved 借鉴）', () {
    late DrawingController controller;

    setUp(() {
      controller = DrawingController(
        DrawingDocument(id: 'dirty_test', title: '脏标记测试'),
      );
    });

    tearDown(() => controller.dispose());

    test('初始状态为已保存', () {
      expect(controller.isDirty, isFalse);
    });

    test('touchDocument 置脏，markSaved 清除', () {
      controller.touchDocument();
      expect(controller.isDirty, isTrue, reason: '内容变更应置脏');
      controller.markSaved();
      expect(controller.isDirty, isFalse, reason: 'markSaved 应清除脏标记');
    });

    test('命令入栈自动置脏', () {
      controller.pushTransaction([_TouchCommand(controller)]);
      expect(controller.isDirty, isTrue, reason: '命令入栈应置脏');
    });

    test('pushTransaction 空列表不置脏（无实际变更）', () {
      controller.pushTransaction([]);
      expect(controller.isDirty, isFalse, reason: '空事务不应产生变更');
    });

    test('undo/redo 也会置脏（内容已变化）', () {
      controller.pushTransaction([_TouchCommand(controller)]);
      controller.markSaved();
      controller.undo();
      expect(controller.isDirty, isTrue, reason: 'undo 改变内容应置脏');
    });
  });
}
