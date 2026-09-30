// C-04 第二批：就地文字编辑会话 + 工具模式互斥 Controller。
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';
import 'package:drawing_notes_app/core/canvas_model/text_item.dart';
import 'package:drawing_notes_app/features/drawing/application/editor_interaction_controllers.dart';
import 'package:drawing_notes_app/features/drawing/application/text_edit_session_state_machine.dart';

PageTextItem draft(String id) =>
    PageTextItem(id: id, x: 0, y: 0, text: 'hi');

void main() {
  group('EditorInPlaceTextSessionController', () {
    test('beginEdit 进入 editing；字段成对写入', () {
      final c = EditorInPlaceTextSessionController();
      expect(c.isEditing, isFalse);
      final t = c.beginEdit(id: 't1', draft: draft('t1'));
      expect(t.phase, TextEditSessionPhase.editing);
      expect(c.phase, TextEditSessionPhase.editing);
      expect(c.editingItemId, 't1');
      expect(c.pendingTextItem?.id, 't1');
      expect(c.isEditing, isTrue);
    });

    test('重复 beginEdit 先取消上一会话再 begin', () {
      final c = EditorInPlaceTextSessionController();
      c.beginEdit(id: 'a', draft: draft('a'));
      c.beginEdit(id: 'b', draft: draft('b'));
      expect(c.editingItemId, 'b');
      expect(c.pendingTextItem?.id, 'b');
    });

    test('completeCommit 清空会话并 settled', () {
      final c = EditorInPlaceTextSessionController();
      c.beginEdit(id: 't1', draft: draft('t1'));
      c.requestCommit();
      final t = c.completeCommit();
      expect(t.phase, TextEditSessionPhase.settled);
      expect(c.isEditing, isFalse);
      expect(c.editingItemId, isNull);
      expect(c.pendingTextItem, isNull);
    });

    test('requestCancel → completeCancel 清空会话', () {
      final c = EditorInPlaceTextSessionController();
      c.beginEdit(id: 't1', draft: draft('t1'));
      final cancel = c.requestCancel();
      expect(cancel.phase, TextEditSessionPhase.canceling);
      final done = c.completeCancel();
      expect(done.phase, TextEditSessionPhase.settled);
      expect(c.isEditing, isFalse);
    });

    test('reset 强制回 idle', () {
      final c = EditorInPlaceTextSessionController();
      c.beginEdit(id: 't1', draft: draft('t1'));
      c.reset();
      expect(c.phase, TextEditSessionPhase.idle);
      expect(c.isEditing, isFalse);
    });
  });

  group('EditorToolModeController', () {
    test('hand/marquee/shape 互斥', () {
      final c = EditorToolModeController();
      expect(c.toggleHand(), isTrue);
      expect(c.marqueeActive, isFalse);
      expect(c.toggleMarquee(), isTrue);
      expect(c.handActive, isFalse);
      c.selectShape(ShapeType.rect);
      expect(c.marqueeActive, isFalse);
      expect(c.activeShape, ShapeType.rect);
      c.clearPointerModes();
      expect(c.activeShape, isNull);
      expect(c.handActive, isFalse);
      expect(c.marqueeActive, isFalse);
    });
  });
}
