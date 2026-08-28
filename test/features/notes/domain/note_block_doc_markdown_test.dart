import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/features/notes/domain/note_block.dart';
import 'package:drawing_notes_app/features/notes/domain/note_block_doc.dart';
import 'package:drawing_notes_app/features/notes/domain/note_block_doc_markdown.dart';

void main() {
  group('noteBlockDocToMarkdown', () {
    test('空文档导出空字符串', () {
      final doc = NoteBlockDoc(
        id: 'empty',
        title: '',
        body: [],
        createdAt: DateTime(2026, 8, 28),
        updatedAt: DateTime(2026, 8, 28),
      );
      final md = noteBlockDocToMarkdown(doc);
      expect(md, '');
    });

    test('文档标题导出为 H1', () {
      final doc = NoteBlockDoc(
        id: 'doc',
        title: 'My Document',
        body: [],
        createdAt: DateTime(2026, 8, 28),
        updatedAt: DateTime(2026, 8, 28),
      );
      final md = noteBlockDocToMarkdown(doc);
      expect(md, contains('# My Document'));
    });

    test('heading 块导出为对应级别标题', () {
      final doc = NoteBlockDoc(
        id: 'doc',
        title: '',
        body: [
          NoteBlock.headingBlock('h1', level: 1, text: 'Title 1'),
          NoteBlock.headingBlock('h3', level: 3, text: 'Title 3'),
          NoteBlock.headingBlock('h6', level: 6, text: 'Title 6'),
        ],
        createdAt: DateTime(2026, 8, 28),
        updatedAt: DateTime(2026, 8, 28),
      );
      final md = noteBlockDocToMarkdown(doc);
      expect(md, contains('# Title 1'));
      expect(md, contains('### Title 3'));
      expect(md, contains('###### Title 6'));
    });

    test('text 块导出为纯文本', () {
      final doc = NoteBlockDoc(
        id: 'doc',
        title: '',
        body: [NoteBlock.textBlock('t1', text: 'Hello World')],
        createdAt: DateTime(2026, 8, 28),
        updatedAt: DateTime(2026, 8, 28),
      );
      final md = noteBlockDocToMarkdown(doc);
      expect(md, contains('Hello World'));
    });

    test('bullet 块导出为无序列表', () {
      final doc = NoteBlockDoc(
        id: 'doc',
        title: '',
        body: [NoteBlock.bulletBlock('b1', text: 'Item A')],
        createdAt: DateTime(2026, 8, 28),
        updatedAt: DateTime(2026, 8, 28),
      );
      final md = noteBlockDocToMarkdown(doc);
      expect(md, contains('- Item A'));
    });

    test('ordered 块导出为有序列表', () {
      final doc = NoteBlockDoc(
        id: 'doc',
        title: '',
        body: [
          NoteBlock.orderedBlock('o1', text: 'First'),
          NoteBlock.orderedBlock('o2', text: 'Second'),
          NoteBlock.orderedBlock('o3', text: 'Third'),
        ],
        createdAt: DateTime(2026, 8, 28),
        updatedAt: DateTime(2026, 8, 28),
      );
      final md = noteBlockDocToMarkdown(doc);
      expect(md, contains('1. First'));
      expect(md, contains('2. Second'));
      expect(md, contains('3. Third'));
    });

    test('todo 块导出为任务列表', () {
      final doc = NoteBlockDoc(
        id: 'doc',
        title: '',
        body: [
          NoteBlock.todoBlock('td1', text: 'Done', checked: true),
          NoteBlock.todoBlock('td2', text: 'Pending', checked: false),
        ],
        createdAt: DateTime(2026, 8, 28),
        updatedAt: DateTime(2026, 8, 28),
      );
      final md = noteBlockDocToMarkdown(doc);
      expect(md, contains('- [x] Done'));
      expect(md, contains('- [ ] Pending'));
    });

    test('quote 块导出为引用', () {
      final doc = NoteBlockDoc(
        id: 'doc',
        title: '',
        body: [NoteBlock.quoteBlock('q1', text: 'Quoted text')],
        createdAt: DateTime(2026, 8, 28),
        updatedAt: DateTime(2026, 8, 28),
      );
      final md = noteBlockDocToMarkdown(doc);
      expect(md, contains('> Quoted text'));
    });

    test('code 块导出为围栏代码', () {
      final doc = NoteBlockDoc(
        id: 'doc',
        title: '',
        body: [NoteBlock.codeBlock('c1', language: 'dart', text: 'print("hi")')],
        createdAt: DateTime(2026, 8, 28),
        updatedAt: DateTime(2026, 8, 28),
      );
      final md = noteBlockDocToMarkdown(doc);
      expect(md, contains('```dart'));
      expect(md, contains('print("hi")'));
      expect(md, contains('```'));
    });

    test('divider 块导出为分隔线', () {
      final doc = NoteBlockDoc(
        id: 'doc',
        title: '',
        body: [NoteBlock.dividerBlock('d1')],
        createdAt: DateTime(2026, 8, 28),
        updatedAt: DateTime(2026, 8, 28),
      );
      final md = noteBlockDocToMarkdown(doc);
      expect(md, contains('---'));
    });

    test('callout 块导出为 NOTE 引用', () {
      final doc = NoteBlockDoc(
        id: 'doc',
        title: '',
        body: [NoteBlock(
          id: 'co1',
          type: NoteBlockType.callout,
          text: 'Important note',
        )],
        createdAt: DateTime(2026, 8, 28),
        updatedAt: DateTime(2026, 8, 28),
      );
      final md = noteBlockDocToMarkdown(doc);
      expect(md, contains('> [!NOTE]'));
      expect(md, contains('Important note'));
    });

    test('image 块导出为 Markdown 图片', () {
      final doc = NoteBlockDoc(
        id: 'doc',
        title: '',
        body: [NoteBlock.imageBlock('img1',
            src: 'https://example.com/img.png', alt: 'My Image')],
        createdAt: DateTime(2026, 8, 28),
        updatedAt: DateTime(2026, 8, 28),
      );
      final md = noteBlockDocToMarkdown(doc);
      expect(md, contains('![My Image](https://example.com/img.png)'));
    });

    test('link 块导出为 Markdown 链接', () {
      final doc = NoteBlockDoc(
        id: 'doc',
        title: '',
        body: [NoteBlock(
          id: 'link1',
          type: NoteBlockType.link,
          text: 'Click here',
          props: {'href': 'https://example.com', 'title': 'Example'},
        )],
        createdAt: DateTime(2026, 8, 28),
        updatedAt: DateTime(2026, 8, 28),
      );
      final md = noteBlockDocToMarkdown(doc);
      expect(md, contains('[Example](https://example.com)'));
    });

    test('table 块导出为 Markdown 表格', () {
      final doc = NoteBlockDoc(
        id: 'doc',
        title: '',
        body: [
          NoteBlock(
            id: 'tbl1',
            type: NoteBlockType.table,
            props: {'rows': 2, 'cols': 2},
            children: [
              NoteBlock.textBlock('c1', text: 'H1'),
              NoteBlock.textBlock('c2', text: 'H2'),
              NoteBlock.textBlock('c3', text: 'D1'),
              NoteBlock.textBlock('c4', text: 'D2'),
            ],
          ),
        ],
        createdAt: DateTime(2026, 8, 28),
        updatedAt: DateTime(2026, 8, 28),
      );
      final md = noteBlockDocToMarkdown(doc);
      expect(md, contains('| H1 | H2 |'));
      expect(md, contains('| --- | --- |'));
      expect(md, contains('| D1 | D2 |'));
    });

    test('内嵌块（canvas）导出为注释 + JSON', () {
      final doc = NoteBlockDoc(
        id: 'doc',
        title: '',
        body: [NoteBlock(
          id: 'cv1',
          type: NoteBlockType.canvas,
          props: {'width': 300, 'height': 200},
        )],
        createdAt: DateTime(2026, 8, 28),
        updatedAt: DateTime(2026, 8, 28),
      );
      final md = noteBlockDocToMarkdown(doc);
      expect(md, contains('<!-- canvas -->'));
      expect(md, contains('[!canvas]'));
      expect(md, contains('"width"'));
    });
  });

  group('noteBlockDocFromMarkdown', () {
    test('解析标题', () {
      final md = '# Hello\n## World';
      final doc = noteBlockDocFromMarkdown(md);
      // H1 被提取为文档标题
      expect(doc.title, 'Hello');
      expect(doc.body.length, 1);
      expect(doc.body[0].type, NoteBlockType.heading);
      expect(doc.body[0].text, 'World');
      expect(doc.body[0].props['level'], 2);
    });

    test('解析无序列表', () {
      final md = '- Item A\n- Item B';
      final doc = noteBlockDocFromMarkdown(md);
      expect(doc.body.length, 2);
      expect(doc.body[0].type, NoteBlockType.bullet);
      expect(doc.body[0].text, 'Item A');
    });

    test('解析有序列表', () {
      final md = '1. First\n2. Second';
      final doc = noteBlockDocFromMarkdown(md);
      expect(doc.body.length, 2);
      expect(doc.body[0].type, NoteBlockType.ordered);
      expect(doc.body[0].text, 'First');
    });

    test('解析 todo 列表', () {
      final md = '- [x] Done\n- [ ] Todo';
      final doc = noteBlockDocFromMarkdown(md);
      expect(doc.body.length, 2);
      expect(doc.body[0].type, NoteBlockType.todo);
      expect(doc.body[0].props['checked'], true);
      expect(doc.body[1].props['checked'], false);
    });

    test('解析引用块', () {
      final md = '> Quoted line';
      final doc = noteBlockDocFromMarkdown(md);
      expect(doc.body.length, 1);
      expect(doc.body[0].type, NoteBlockType.quote);
      expect(doc.body[0].text, 'Quoted line');
    });

    test('解析代码围栏', () {
      final md = '```dart\nprint("hi")\n```';
      final doc = noteBlockDocFromMarkdown(md);
      expect(doc.body.length, 1);
      expect(doc.body[0].type, NoteBlockType.code);
      expect(doc.body[0].text, 'print("hi")');
      expect(doc.body[0].props['language'], 'dart');
    });

    test('解析分隔线', () {
      final md = '---';
      final doc = noteBlockDocFromMarkdown(md);
      expect(doc.body.length, 1);
      expect(doc.body[0].type, NoteBlockType.divider);
    });

    test('解析图片', () {
      final md = '![Alt](https://example.com/img.png)';
      final doc = noteBlockDocFromMarkdown(md);
      expect(doc.body.length, 1);
      expect(doc.body[0].type, NoteBlockType.image);
      expect(doc.body[0].props['src'], 'https://example.com/img.png');
      expect(doc.body[0].props['alt'], 'Alt');
    });

    test('解析普通段落', () {
      final md = 'Just a paragraph.';
      final doc = noteBlockDocFromMarkdown(md);
      expect(doc.body.length, 1);
      expect(doc.body[0].type, NoteBlockType.text);
      expect(doc.body[0].text, 'Just a paragraph.');
    });
  });

  group('Round-trip 测试', () {
    test('纯文本块导出→导入保序', () {
      final original = NoteBlockDoc(
        id: 'rt1',
        title: 'Round Trip',
        body: [
          NoteBlock.textBlock('t1', text: 'Line 1'),
          NoteBlock.textBlock('t2', text: 'Line 2'),
          NoteBlock.textBlock('t3', text: 'Line 3'),
        ],
        createdAt: DateTime(2026, 8, 28),
        updatedAt: DateTime(2026, 8, 28),
      );
      final md = noteBlockDocToMarkdown(original);
      final restored = noteBlockDocFromMarkdown(md);

      // 标题应保留
      expect(restored.title, 'Round Trip');
      // 文本块应保序
      final textBlocks =
          restored.body.where((b) => b.type == NoteBlockType.text).toList();
      expect(textBlocks.length, 3);
      expect(textBlocks[0].text, 'Line 1');
      expect(textBlocks[1].text, 'Line 2');
      expect(textBlocks[2].text, 'Line 3');
    });

    test('heading + bullet 混合 round-trip', () {
      final original = NoteBlockDoc(
        id: 'rt2',
        title: '',
        body: [
          NoteBlock.headingBlock('h1', level: 2, text: 'Section'),
          NoteBlock.bulletBlock('b1', text: 'Point 1'),
          NoteBlock.bulletBlock('b2', text: 'Point 2'),
        ],
        createdAt: DateTime(2026, 8, 28),
        updatedAt: DateTime(2026, 8, 28),
      );
      final md = noteBlockDocToMarkdown(original);
      final restored = noteBlockDocFromMarkdown(md);

      expect(restored.body.length, 3);
      expect(restored.body[0].type, NoteBlockType.heading);
      expect(restored.body[0].text, 'Section');
      expect(restored.body[1].type, NoteBlockType.bullet);
      expect(restored.body[1].text, 'Point 1');
    });
  });
}
