// C-04：斜杠菜单 + 指针采样状态机控制器单测。
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/features/drawing/application/editor_pointer_sample_state.dart';
import 'package:drawing_notes_app/features/drawing/application/editor_slash_menu_controller.dart';

void main() {
  group('EditorSlashMenuController', () {
    test('setOpen(true) 归零高亮；false 关闭', () {
      final c = EditorSlashMenuController();
      c.setOpen(true);
      expect(c.open, isTrue);
      expect(c.highlight, 0);
      c.setOpen(true); // 幂等
      expect(c.open, isTrue);
      c.close();
      expect(c.open, isFalse);
    });

    test('moveNext/Prev 循环', () {
      final c = EditorSlashMenuController()..setOpen(true);
      c.moveNext(3);
      expect(c.highlight, 1);
      c.moveNext(3);
      c.moveNext(3);
      expect(c.highlight, 0, reason: '边界循环回 0');
      c.movePrev(3);
      expect(c.highlight, 2);
    });

    test('selected 越界钳制；空列表 null', () {
      final c = EditorSlashMenuController()..setHighlight(99);
      expect(c.selected(<int>[10, 20]), 20);
      expect(c.selected(<int>[]), isNull);
    });
  });

  group('EditorPointerSampleState', () {
    test('拖动/压感/取色采样与 reset', () {
      final s = EditorPointerSampleState();
      s.noteDrag(const Offset(10, 20));
      expect(s.lastDragCanvas, const Offset(10, 20));
      s.resetDrag();
      expect(s.lastDragCanvas, isNull);

      final t = DateTime(2026, 9, 29, 12);
      s.notePen(const Offset(1, 2), t);
      expect(s.lastPenPos, const Offset(1, 2));
      expect(s.lastPenTime, t);
      s.resetPen();
      expect(s.lastPenPos, isNull);
      expect(s.lastPenTime, isNull);

      s.notePickColor(t);
      expect(s.lastPickColorAt, t);
    });
  });
}
