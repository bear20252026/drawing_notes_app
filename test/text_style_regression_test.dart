import 'package:drawing_notes_app/features/drawing/domain/document.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';
import 'package:flutter_test/flutter_test.dart';

/// 文字属性增强回归测试（加粗/斜体/对齐 + 快捷键语义）。
///
/// 覆盖：
/// - 文字块 bold/italic/align 属性设置与序列化保留（含向后兼容回退）；
/// - 快捷键 Ctrl+B/Ctrl+I/Ctrl+E 对应的模型操作（切换加粗/斜体/循环对齐）；
/// - 便利贴与普通文字块混排时属性各自独立保留。
void main() {
  group('文字属性（加粗/斜体/对齐）', () {
    test('默认属性：不粗、不斜、左对齐', () {
      final item = PageTextItem(id: 't1', x: 0, y: 0, text: '默认');
      expect(item.bold, isFalse);
      expect(item.italic, isFalse);
      expect(item.align, TextAlignType.left);
    });

    test('设置属性后序列化往返保留', () {
      final item = PageTextItem(
        id: 't2',
        x: 10,
        y: 20,
        text: '样式文字',
        bold: true,
        italic: true,
        align: TextAlignType.center,
      );
      final restored = PageTextItem.fromJson(item.toJson());
      expect(restored.bold, isTrue, reason: '加粗应序列化保留');
      expect(restored.italic, isTrue, reason: '斜体应序列化保留');
      expect(restored.align, TextAlignType.center, reason: '对齐应序列化保留');
      expect(restored.text, '样式文字');
    });

    test('旧数据（无属性字段）回退为默认值（向后兼容）', () {
      final json = PageTextItem(id: 't3', x: 0, y: 0, text: '旧数据').toJson();
      json.remove('bold');
      json.remove('italic');
      json.remove('align');
      final restored = PageTextItem.fromJson(json);
      expect(restored.bold, isFalse);
      expect(restored.italic, isFalse);
      expect(restored.align, TextAlignType.left);
    });

    test('三种对齐方式均可序列化往返', () {
      for (final a in TextAlignType.values) {
        final item = PageTextItem(id: 't4', x: 0, y: 0, text: 'a', align: a);
        final restored = PageTextItem.fromJson(item.toJson());
        expect(restored.align, a);
      }
    });

    test('快捷键语义：切换加粗/斜体/循环对齐（Ctrl+B/Ctrl+I/Ctrl+E）', () {
      final item = PageTextItem(id: 't5', x: 0, y: 0, text: '快捷键');

      // Ctrl+B 切换加粗
      item.bold = !item.bold;
      expect(item.bold, isTrue);
      item.bold = !item.bold;
      expect(item.bold, isFalse);

      // Ctrl+I 切换斜体
      item.italic = !item.italic;
      expect(item.italic, isTrue);

      // Ctrl+E 循环对齐：left -> center -> right -> left
      item.align = TextAlignType
          .values[(item.align.index + 1) % TextAlignType.values.length];
      expect(item.align, TextAlignType.center);
      item.align = TextAlignType
          .values[(item.align.index + 1) % TextAlignType.values.length];
      expect(item.align, TextAlignType.right);
      item.align = TextAlignType
          .values[(item.align.index + 1) % TextAlignType.values.length];
      expect(item.align, TextAlignType.left);
    });

    test('便利贴与普通文字块混排时属性独立保留', () {
      final page = NotebookPage(
        id: 'pg_mix',
        title: '混排',
        document: DrawingDocument(id: 'd1', title: '页'),
      );
      page.textItems.add(
        PageTextItem(
          id: 'a',
          x: 0,
          y: 0,
          text: '普通',
          bold: true,
          align: TextAlignType.right,
        ),
      );
      page.textItems.add(
        PageTextItem(
          id: 'b',
          x: 100,
          y: 100,
          text: '标签',
          isSticky: true,
          italic: true,
          align: TextAlignType.center,
        ),
      );
      final restored = NotebookPage.fromJson(page.toJson());
      expect(restored.textItems[0].bold, isTrue);
      expect(restored.textItems[0].italic, isFalse);
      expect(restored.textItems[0].align, TextAlignType.right);
      expect(restored.textItems[1].isSticky, isTrue);
      expect(restored.textItems[1].italic, isTrue);
      expect(restored.textItems[1].align, TextAlignType.center);
      expect(restored.textItems[1].bold, isFalse);
    });
  });
}
