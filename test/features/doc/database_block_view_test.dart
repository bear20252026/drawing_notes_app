// P3-2 契约测试：DatabaseBlockView 数据库块真视图。
// 表：渲染行/列、排序、切换视图、添加记录；写回 payload 为 props['database'] 的 JSON。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/features/notes/domain/note_block.dart';
import 'package:drawing_notes_app/features/notes/domain/note_database.dart';
import 'package:drawing_notes_app/features/doc/presentation/database_block_view.dart';

void main() {
  NoteBlock buildBlock([NoteDatabase? db]) {
    final d = db ??
        NoteDatabase.empty(title: '任务表')
            .addField(const NoteFieldDef(id: 'n', name: '名称', type: NoteFieldType.text))
            .addField(const NoteFieldDef(id: 's', name: '状态', type: NoteFieldType.select, options: ['待办', '完成']))
            .addRecord(const NoteRecord(id: 'r1', cells: {'n': '写文档', 's': '待办'}))
            .addRecord(const NoteRecord(id: 'r2', cells: {'n': '复盘', 's': '完成'}));
    return NoteBlock(
      id: 'db1',
      type: NoteBlockType.database,
      props: {'database': jsonEncode(d.toJson())},
    );
  }

  testWidgets('渲染标题与记录数', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DatabaseBlockView(block: buildBlock())),
    ));
    expect(find.text('任务表'), findsOneWidget);
    expect(find.text('2 条记录'), findsOneWidget);
    expect(find.text('写文档'), findsOneWidget);
    expect(find.text('复盘'), findsOneWidget);
  });

  testWidgets('点击表头切换排序', (tester) async {
    NoteBlock? last;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DatabaseBlockView(
          block: buildBlock(),
          onChanged: (b) => last = b,
        ),
      ),
    ));
    // 点“名称”表头
    await tester.tap(find.text('名称'));
    await tester.pumpAndSettle();
    expect(last, isNotNull, reason: '应写回新块');
    final db = DatabaseBlockView.decodeDatabase(last!);
    expect(db.sortFieldId, 'n');
    expect(db.sortAscending, isTrue);
  });

  testWidgets('添加记录增加一行', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DatabaseBlockView(block: buildBlock())),
    ));
    expect(find.text('2 条记录'), findsOneWidget);
    await tester.tap(find.byTooltip('添加记录'));
    await tester.pumpAndSettle();
    expect(find.text('3 条记录'), findsOneWidget);
  });

  testWidgets('切换看板视图', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DatabaseBlockView(block: buildBlock())),
    ));
    await tester.tap(find.byTooltip('看板'));
    await tester.pumpAndSettle();
    expect(find.text('待办'), findsWidgets);
    expect(find.text('完成'), findsWidgets);
  });

  testWidgets('空库显示空态提示', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DatabaseBlockView(block: buildBlock(NoteDatabase.empty()))),
    ));
    expect(find.textContaining('添加字段'), findsWidgets);
  });

  testWidgets('搜索框按字段值过滤记录', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DatabaseBlockView(block: buildBlock())),
    ));
    expect(find.text('写文档'), findsOneWidget);
    expect(find.text('复盘'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '复盘');
    await tester.pumpAndSettle();

    expect(find.text('写文档'), findsNothing);
    expect(find.text('1 条记录'), findsOneWidget);
  });

  testWidgets('搜索无命中显示空态且可清空恢复', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DatabaseBlockView(block: buildBlock())),
    ));
    await tester.enterText(find.byType(TextField), '不存在');
    await tester.pumpAndSettle();
    expect(find.textContaining('还没有记录'), findsOneWidget);
    expect(find.text('0 条记录'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.clear));
    await tester.pumpAndSettle();
    expect(find.text('写文档'), findsOneWidget);
    expect(find.text('2 条记录'), findsOneWidget);
  });
}
