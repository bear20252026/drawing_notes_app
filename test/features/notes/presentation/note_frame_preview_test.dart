// 由 Claude 团队生成 | Drawing Notes App
// NoteFramePreview 只读块预览测试。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/theme/apple_design.dart';
import 'package:drawing_notes_app/features/notes/domain/note_block.dart';
import 'package:drawing_notes_app/features/notes/domain/note_block_doc.dart';
import 'package:drawing_notes_app/features/notes/presentation/note_frame_preview.dart';

NoteBlockDoc _doc(String title, List<NoteBlock> blocks) => NoteBlockDoc(
  id: 'd1',
  title: title,
  body: blocks,
  createdAt: DateTime.fromMillisecondsSinceEpoch(0),
  updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
);

Future<void> _pump(WidgetTester tester, NoteBlockDoc doc, {bool showTitle = true}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: NoteFramePreview(doc: doc, showTitle: showTitle),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('showTitle 为 true 且标题非空时渲染标题', (tester) async {
    await _pump(
      tester,
      _doc('我的标题', [NoteBlock.textBlock('b0', text: '正文')]),
    );
    expect(find.text('我的标题'), findsOneWidget);
  });

  testWidgets('showTitle 为 false 时渲染标题隐藏', (tester) async {
    await _pump(
      tester,
      _doc('我的标题', [NoteBlock.textBlock('b0', text: '正文')]),
      showTitle: false,
    );
    expect(find.text('我的标题'), findsNothing);
  });

  testWidgets('heading 块渲染为大号加粗', (tester) async {
    await _pump(
      tester,
      _doc(
        '',
        [
          NoteBlock.headingBlock('b0', level: 3, text: '三级标题'),
        ],
      ),
    );
    final text = tester.widget<Text>(find.text('三级标题'));
    expect(text.style?.fontSize, 19);
    expect(text.style?.fontWeight, FontWeight.w700);
  });

  testWidgets('bullet 块带圆点前缀', (tester) async {
    await _pump(
      tester,
      _doc('', [NoteBlock.bulletBlock('b0', text: '列表项')]),
    );
    expect(find.text('•  列表项'), findsOneWidget);
  });

  testWidgets('ordered 块编号递增', (tester) async {
    await _pump(
      tester,
      _doc(
        '',
        [
          NoteBlock.orderedBlock('b1', text: '第一'),
          NoteBlock.orderedBlock('b2', text: '第二'),
        ],
      ),
    );
    expect(find.text('1.  第一'), findsOneWidget);
    expect(find.text('2.  第二'), findsOneWidget);
  });

  testWidgets('todo 勾选显示完成态（删除线）', (tester) async {
    await _pump(
      tester,
      _doc('', [NoteBlock.todoBlock('b0', text: '待办', checked: true)]),
    );
    final text = tester.widget<Text>(find.text('待办'));
    expect(text.style?.decoration, TextDecoration.lineThrough);
    expect(find.byIcon(Icons.check_box), findsOneWidget);
  });

  testWidgets('todo 未勾选显示空框', (tester) async {
    await _pump(
      tester,
      _doc('', [NoteBlock.todoBlock('b0', text: '待办', checked: false)]),
    );
    expect(find.byIcon(Icons.check_box_outline_blank), findsOneWidget);
  });

  testWidgets('quote 块渲染斜体文本', (tester) async {
    await _pump(
      tester,
      _doc('', [NoteBlock.quoteBlock('b0', text: '引用内容')]),
    );
    final text = tester.widget<Text>(find.text('引用内容'));
    expect(text.style?.fontStyle, FontStyle.italic);
  });

  testWidgets('code 块渲染等宽字体', (tester) async {
    await _pump(
      tester,
      _doc('', [NoteBlock.codeBlock('b0', text: 'void main() {}', language: 'dart')]),
    );
    final text = tester.widget<Text>(find.text('void main() {}'));
    expect(text.style?.fontFamily, 'monospace');
  });

  testWidgets('divider 块渲染分割线', (tester) async {
    await _pump(
      tester,
      _doc('', [NoteBlock.dividerBlock('b0')]),
    );
    expect(find.byType(Divider), findsOneWidget);
  });

  testWidgets('image 块渲染 src 文本', (tester) async {
    await _pump(
      tester,
      _doc('', [NoteBlock.imageBlock('b0', src: 'http://x/a.png')]),
    );
    expect(find.text('http://x/a.png'), findsOneWidget);
  });

  testWidgets('link 块渲染蓝色下划线文本', (tester) async {
    await _pump(
      tester,
      _doc('', [NoteBlock(id: 'b0', type: NoteBlockType.link, text: 'Google', props: {'href': 'https://g.com'})]),
    );
    final text = tester.widget<Text>(find.text('Google'));
    expect(text.style?.decoration, TextDecoration.underline);
    expect(text.style?.color, AppleColor.actionBlue);
  });

  testWidgets('内嵌占位（画布/图表/表格/数据库）显示标签', (tester) async {
    await _pump(
      tester,
      _doc(
        '',
        [
          NoteBlock(id: 'b0', type: NoteBlockType.canvas),
          NoteBlock(id: 'b1', type: NoteBlockType.chart),
          NoteBlock(id: 'b2', type: NoteBlockType.table),
          NoteBlock(id: 'b3', type: NoteBlockType.database),
        ],
      ),
    );
    expect(find.text('画布'), findsOneWidget);
    expect(find.text('图表'), findsOneWidget);
    expect(find.text('表格'), findsOneWidget);
    expect(find.text('数据库'), findsOneWidget);
  });

  testWidgets('children 递归渲染（嵌套子文本可见）', (tester) async {
    await _pump(
      tester,
      _doc(
        '',
        [
          NoteBlock(
            id: 'b0',
            type: NoteBlockType.bullet,
            text: '父项',
            children: [
              NoteBlock(id: 'b0c', type: NoteBlockType.bullet, text: '子项'),
            ],
          ),
        ],
      ),
    );
    expect(find.text('•  父项'), findsOneWidget);
    expect(find.text('•  子项'), findsOneWidget);
  });
}
