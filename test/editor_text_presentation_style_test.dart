import 'package:drawing_notes_app/features/drawing/presentation/editor_text_presentation_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EditorTextPresentationStyle', () {
    test('有宽度时按视图缩放约束并换行，无宽度时保持无限布局', () {
      final constrained = EditorTextPresentationStyle.layout(
        width: 120,
        viewScale: 1.5,
      );
      final unconstrained = EditorTextPresentationStyle.layout(
        width: null,
        viewScale: 2,
      );

      expect(constrained.softWrap, isTrue);
      expect(constrained.constraints.maxWidth, 180);
      expect(unconstrained.softWrap, isFalse);
      expect(unconstrained.constraints, const BoxConstraints());
    });

    test('整块文字样式保留字号、字体族、颜色和装饰规则', () {
      final style = EditorTextPresentationStyle.plainTextStyle(
        fontSize: 16,
        viewScale: 1.5,
        color: 0xFF336699,
        fontFamily: 'monospace',
        isTodo: false,
        todoChecked: false,
        isSticky: false,
        bold: true,
        italic: true,
        underline: true,
        strikethrough: true,
      );

      expect(style.fontSize, 24);
      expect(style.fontFamily, 'monospace');
      expect(style.color, const Color(0xFF336699));
      expect(style.fontWeight, FontWeight.bold);
      expect(style.fontStyle, FontStyle.italic);
      expect(
        style.decoration,
        TextDecoration.combine([
          TextDecoration.underline,
          TextDecoration.lineThrough,
        ]),
      );
    });

    test('待办完成态和默认便利贴颜色保持现有视觉规则', () {
      final completedTodo = EditorTextPresentationStyle.plainTextColor(
        color: 0xFF336699,
        isTodo: true,
        todoChecked: true,
        isSticky: false,
      );
      final sticky = EditorTextPresentationStyle.plainTextColor(
        color: 0xFFFFF59D,
        isTodo: false,
        todoChecked: false,
        isSticky: true,
      );

      expect(completedTodo.toARGB32(), const Color(0x73336699).toARGB32());
      expect(sticky, const Color(0xFF3E2723));
    });

    test('富文本 run 使用自己的样式并在未指定颜色时回退基础颜色', () {
      final run = EditorTextPresentationStyle.richRunStyle(
        fallbackColor: 0xFF112233,
        color: null,
        bold: true,
        italic: false,
        underline: false,
        strikethrough: true,
      );

      expect(run.color, const Color(0xFF112233));
      expect(run.fontWeight, FontWeight.bold);
      expect(run.fontStyle, FontStyle.normal);
      expect(run.decoration, TextDecoration.lineThrough);
    });

    test('字体族和对齐只接受已支持的语义值', () {
      expect(
        EditorTextPresentationStyle.fontFamilyFor('handwriting'),
        'cursive',
      );
      expect(EditorTextPresentationStyle.fontFamilyFor('unknown'), isNull);
      expect(
        EditorTextPresentationStyle.textAlignFor('center'),
        TextAlign.center,
      );
      expect(
        EditorTextPresentationStyle.textAlignFor('unknown'),
        TextAlign.left,
      );
    });
  });
}
