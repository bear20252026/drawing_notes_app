import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/features/notes/domain/note_block.dart';
import 'package:drawing_notes_app/features/notes/presentation/embedded_block_view.dart';
import 'package:drawing_notes_app/features/notes/presentation/note_editor_page.dart';

void main() {
  group('EmbeddedBlockView isEmbeddedType', () {
    test('文本类型不是内嵌块', () {
      expect(EmbeddedBlockView.isEmbeddedType(NoteBlockType.text), false);
      expect(EmbeddedBlockView.isEmbeddedType(NoteBlockType.heading), false);
      expect(EmbeddedBlockView.isEmbeddedType(NoteBlockType.bullet), false);
      expect(EmbeddedBlockView.isEmbeddedType(NoteBlockType.ordered), false);
      expect(EmbeddedBlockView.isEmbeddedType(NoteBlockType.todo), false);
      expect(EmbeddedBlockView.isEmbeddedType(NoteBlockType.quote), false);
      expect(EmbeddedBlockView.isEmbeddedType(NoteBlockType.code), false);
      expect(EmbeddedBlockView.isEmbeddedType(NoteBlockType.divider), false);
      expect(EmbeddedBlockView.isEmbeddedType(NoteBlockType.callout), false);
    });

    test('内嵌类型是内嵌块', () {
      expect(EmbeddedBlockView.isEmbeddedType(NoteBlockType.canvas), true);
      expect(EmbeddedBlockView.isEmbeddedType(NoteBlockType.chart), true);
      expect(EmbeddedBlockView.isEmbeddedType(NoteBlockType.image), true);
      expect(EmbeddedBlockView.isEmbeddedType(NoteBlockType.link), true);
      expect(EmbeddedBlockView.isEmbeddedType(NoteBlockType.table), true);
      expect(EmbeddedBlockView.isEmbeddedType(NoteBlockType.database), true);
    });
  });

  group('EmbeddedBlockView 图片渲染', () {
    testWidgets('有 src 时渲染 Image.network', (tester) async {
      final block = NoteBlock(
        id: 'img1',
        type: NoteBlockType.image,
        props: const {'src': 'https://example.com/photo.jpg', 'alt': '示例图片'},
      );

      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: EmbeddedBlockView(block: block))),
      );
      await tester.pump();

      expect(find.byType(Image), findsOneWidget);
      expect(find.text('示例图片'), findsOneWidget);
    });

    testWidgets('无 src 时渲染占位卡片', (tester) async {
      final block = NoteBlock(
        id: 'img2',
        type: NoteBlockType.image,
        props: const {'alt': '无图说明'},
      );

      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: EmbeddedBlockView(block: block))),
      );
      await tester.pumpAndSettle();

      // 占位卡片显示"图片（无来源）"
      expect(find.text('图片（无来源）'), findsOneWidget);
      expect(find.text('无图说明'), findsOneWidget);
    });

    testWidgets('src 为空字符串时渲染占位卡片', (tester) async {
      final block = NoteBlock(
        id: 'img3',
        type: NoteBlockType.image,
        props: const {'src': ''},
      );

      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: EmbeddedBlockView(block: block))),
      );
      await tester.pumpAndSettle();

      expect(find.text('图片（无来源）'), findsOneWidget);
    });
  });

  group('EmbeddedBlockView 链接渲染', () {
    testWidgets('有 href 时渲染可点击链接', (tester) async {
      final block = NoteBlock(
        id: 'link1',
        type: NoteBlockType.link,
        props: const {'href': 'https://example.com', 'title': '示例链接'},
      );

      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: EmbeddedBlockView(block: block))),
      );
      await tester.pumpAndSettle();

      expect(find.byType(InkWell), findsOneWidget);
      expect(find.text('示例链接'), findsOneWidget);
      expect(find.byIcon(Icons.link), findsOneWidget);
    });

    testWidgets('无 href 时渲染占位卡片', (tester) async {
      final block = NoteBlock(
        id: 'link2',
        type: NoteBlockType.link,
        props: const {'title': '无效链接'},
      );

      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: EmbeddedBlockView(block: block))),
      );
      await tester.pumpAndSettle();

      expect(find.text('链接（无地址）'), findsOneWidget);
    });

    testWidgets('href 为空字符串时渲染占位卡片', (tester) async {
      final block = NoteBlock(
        id: 'link3',
        type: NoteBlockType.link,
        props: const {'href': ''},
      );

      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: EmbeddedBlockView(block: block))),
      );
      await tester.pumpAndSettle();

      expect(find.text('链接（无地址）'), findsOneWidget);
    });
  });

  group('EmbeddedBlockView 表格渲染', () {
    testWidgets('按 rows×cols 渲染网格', (tester) async {
      final block = NoteBlock(
        id: 'table1',
        type: NoteBlockType.table,
        props: const {'rows': 2, 'cols': 3},
        children: [
          const NoteBlock(id: 'c1', type: NoteBlockType.text, text: 'A1'),
          const NoteBlock(id: 'c2', type: NoteBlockType.text, text: 'A2'),
          const NoteBlock(id: 'c3', type: NoteBlockType.text, text: 'A3'),
          const NoteBlock(id: 'c4', type: NoteBlockType.text, text: 'B1'),
          const NoteBlock(id: 'c5', type: NoteBlockType.text, text: 'B2'),
          const NoteBlock(id: 'c6', type: NoteBlockType.text, text: 'B3'),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: EmbeddedBlockView(block: block))),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Table), findsOneWidget);
      expect(find.text('A1'), findsOneWidget);
      expect(find.text('B3'), findsOneWidget);
    });

    testWidgets('缺少 children 时格子为空', (tester) async {
      final block = NoteBlock(
        id: 'table2',
        type: NoteBlockType.table,
        props: const {'rows': 2, 'cols': 2},
        children: [
          const NoteBlock(id: 'c1', type: NoteBlockType.text, text: '仅有'),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: EmbeddedBlockView(block: block))),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Table), findsOneWidget);
      expect(find.text('仅有'), findsOneWidget);
    });
  });

  group('EmbeddedBlockView 数据库渲染', () {
    testWidgets('渲染记录数统计和 JSON 面片', (tester) async {
      final block = NoteBlock(
        id: 'db1',
        type: NoteBlockType.database,
        props: const {
          'records': [
            {'name': 'Alice', 'age': 30},
            {'name': 'Bob', 'age': 25},
          ],
        },
      );

      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: EmbeddedBlockView(block: block))),
      );
      await tester.pumpAndSettle();

      expect(find.text('数据库'), findsOneWidget);
      expect(find.text('2 条记录'), findsOneWidget);
    });

    testWidgets('无 records 时显示 0 条记录', (tester) async {
      final block = NoteBlock(
        id: 'db2',
        type: NoteBlockType.database,
        props: const <String, dynamic>{},
      );

      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: EmbeddedBlockView(block: block))),
      );
      await tester.pumpAndSettle();

      expect(find.text('0 条记录'), findsOneWidget);
    });
  });

  group('EmbeddedBlockView canvas/chart 占位', () {
    testWidgets('canvas 无 builder 时渲染占位卡片', (tester) async {
      final block = NoteBlock(
        id: 'canvas1',
        type: NoteBlockType.canvas,
        props: const <String, dynamic>{},
      );

      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: EmbeddedBlockView(block: block))),
      );
      await tester.pumpAndSettle();

      expect(find.text('内嵌画布'), findsOneWidget);
      expect(find.byIcon(Icons.dashboard_customize_outlined), findsOneWidget);
    });

    testWidgets('chart 无 builder 时渲染占位卡片', (tester) async {
      final block = NoteBlock(
        id: 'chart1',
        type: NoteBlockType.chart,
        props: const <String, dynamic>{},
      );

      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: EmbeddedBlockView(block: block))),
      );
      await tester.pumpAndSettle();

      expect(find.text('内嵌图表'), findsOneWidget);
      expect(find.byIcon(Icons.bar_chart), findsOneWidget);
    });
  });

  group('EmbeddedBlockView builder 优先', () {
    testWidgets('传入 builder 时优先使用 builder 产物', (tester) async {
      final block = NoteBlock(
        id: 'canvas2',
        type: NoteBlockType.canvas,
        props: const <String, dynamic>{},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmbeddedBlockView(
              block: block,
              embeddedBuilder: (b) => const Text('自定义画布渲染'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // builder 产物优先
      expect(find.text('自定义画布渲染'), findsOneWidget);
      // 不显示默认占位
      expect(find.text('内嵌画布'), findsNothing);
    });

    testWidgets('builder 返回 null 时降级到默认渲染', (tester) async {
      final block = NoteBlock(
        id: 'chart2',
        type: NoteBlockType.chart,
        props: const <String, dynamic>{},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmbeddedBlockView(
              block: block,
              embeddedBuilder: (b) => null, // 无害 builder，返回 null
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 降级到默认占位
      expect(find.text('内嵌图表'), findsOneWidget);
    });
  });

  group('NoteEditorPage 集成内嵌块', () {
    testWidgets('canvas 块渲染 EmbeddedBlockView 而非 TextField', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: NoteEditorPage(
            embeddedBlockBuilder: (b) => null, // 无害 builder
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 初始状态只有一个文本块（无 canvas）
      expect(find.byType(TextField), findsOneWidget);

      // 通过工具栏将第一个块切换为 canvas 类型
      await tester.tap(find.byTooltip('内嵌画布'));
      await tester.pumpAndSettle();

      // canvas 块不渲染 TextField
      // 注意：初始只有一个文本块，切换后变成 canvas，所以 TextField 应为 0
      expect(find.byType(TextField), findsNothing);
      // 占位卡片显示 canvas 占位文本（工具栏按钮也有"内嵌画布"文本，
      // 故用占位卡片特有的提示文案断言）
      expect(find.text('由宿主提供 builder 以渲染完整内容'), findsOneWidget);
    });

    testWidgets('image 块渲染图片视图而非 TextField', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: NoteEditorPage()),
      );
      await tester.pumpAndSettle();

      // 切换到 image 类型
      await tester.tap(find.byTooltip('图片'));
      await tester.pumpAndSettle();

      // image 块无 src，显示占位
      expect(find.byType(TextField), findsNothing);
      expect(find.text('图片（无来源）'), findsOneWidget);
    });

    testWidgets('embeddedBlockBuilder 参数传递给 EmbeddedBlockView', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: NoteEditorPage(
            embeddedBlockBuilder: (b) {
              if (b.type == NoteBlockType.canvas) {
                return const Text('注入的画布');
              }
              return null;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 切换到 canvas 类型
      await tester.tap(find.byTooltip('内嵌画布'));
      await tester.pumpAndSettle();

      // 使用注入的 builder，占位卡片不应出现
      expect(find.text('注入的画布'), findsOneWidget);
      // 占位卡片的提示文案不应出现（工具栏按钮有"内嵌画布"文本，故不检查它）
      expect(find.text('由宿主提供 builder 以渲染完整内容'), findsNothing);
    });
  });
}
