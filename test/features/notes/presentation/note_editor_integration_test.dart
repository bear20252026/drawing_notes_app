import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block_doc.dart';
import 'package:drawing_notes_app/features/doc/infrastructure/note_block_doc_store.dart';
import 'package:drawing_notes_app/features/doc/doc_editor.dart';

/// M4 集成测试：验证 DocEditor + NoteBlockDoc 双向绑定。
///
/// 覆盖场景：
/// - 打开文档 → 显示块列表
/// - 编辑文本 → onSave 回调传出更新后的 NoteBlockDoc
/// - 真实文件 IO：保存 → 重新加载 → 看到变更
void main() {
  final now = DateTime(2026, 8, 28);

  NoteBlockDoc makeDoc({
    required String id,
    String title = '',
    required List<NoteBlock> body,
  }) => NoteBlockDoc(
    id: id,
    title: title,
    body: body,
    createdAt: now,
    updatedAt: now,
  );

  group('M4 DocEditor 文档绑定（widget）', () {
    testWidgets('加载文档后显示所有块', (tester) async {
      final doc = makeDoc(
        id: 'test-doc-1',
        title: 'My Notes',
        body: [
          NoteBlock.headingBlock('h1', level: 1, text: 'Title'),
          NoteBlock.textBlock('t1', text: 'First paragraph'),
          NoteBlock.textBlock('t2', text: 'Second paragraph'),
        ],
      );

      await tester.pumpWidget(MaterialApp(home: DocEditor(document: doc)));
      await tester.pumpAndSettle();

      expect(find.text('My Notes'), findsOneWidget);
      // 3 个文本块 + 1 个标题栏 = 4 个 TextField
      expect(find.byType(TextField), findsNWidgets(4));
    });

    testWidgets('新建文档（无 document 参数）创建空段落', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: DocEditor()));
      await tester.pumpAndSettle();

      // 标题栏 + 空段落 = 2 个 TextField
      expect(find.byType(TextField), findsNWidgets(2));
    });

    testWidgets('内嵌类型（canvas）渲染为占位', (tester) async {
      final doc = makeDoc(
        id: 'test-embedded',
        title: 'Embedded',
        body: [
          NoteBlock(
            id: 'c1',
            type: NoteBlockType.canvas,
            props: {'width': 300, 'height': 200},
          ),
        ],
      );

      await tester.pumpWidget(MaterialApp(home: DocEditor(document: doc)));
      await tester.pumpAndSettle();

      // 标题栏 TextField 仍在，但 canvas 块本身不产生 TextField
      expect(find.byType(TextField), findsOneWidget);
      // 应显示内嵌视图占位卡片
      expect(find.byType(Container), findsWidgets);
      expect(find.text('由宿主提供 builder 以渲染完整内容'), findsWidgets);
    });

    testWidgets('onSave 回调在 dispose 时传出更新后的文档', (tester) async {
      NoteBlockDoc? savedDoc;
      final doc = makeDoc(
        id: 'doc-callback',
        title: 'Callback Test',
        body: [NoteBlock.textBlock('t1', text: 'Original')],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: DocEditor(document: doc, onSave: (d) => savedDoc = d),
        ),
      );
      await tester.pumpAndSettle();

      // 编辑文本
      final textField = find.widgetWithText(TextField, 'Original');
      expect(textField, findsOneWidget);
      await tester.enterText(textField, 'Modified');
      await tester.pumpAndSettle();

      // 触发 dispose
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();

      // 验证 onSave 收到更新后的文档
      expect(savedDoc, isNotNull);
      expect(savedDoc!.id, 'doc-callback');
      expect(savedDoc!.body.first.text, 'Modified');
    });
  });

  group('M4 NoteBlockDocStore IO 集成', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('blockdoc_io_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('saveDocument → loadDocument → 内容一致', () async {
      final store = NoteBlockDocStore(directoryProvider: () async => tempDir);

      final doc = makeDoc(
        id: 'io-doc',
        title: 'IO Test',
        body: [NoteBlock.textBlock('t1', text: 'Hello World')],
      );
      await store.saveDocument(doc);

      final loaded = await store.loadDocument('io-doc');
      expect(loaded, isNotNull);
      expect(loaded!.id, 'io-doc');
      expect(loaded.title, 'IO Test');
      expect(loaded.body.first.text, 'Hello World');
    });

    test('loadDocument 不存在返回 null', () async {
      final store = NoteBlockDocStore(directoryProvider: () async => tempDir);

      final loaded = await store.loadDocument('nonexistent');
      expect(loaded, isNull);
    });

    test('deleteDocument 删除后加载返回 null', () async {
      final store = NoteBlockDocStore(directoryProvider: () async => tempDir);

      final doc = makeDoc(
        id: 'delete-me',
        title: 'To Delete',
        body: [NoteBlock.textBlock('t1', text: 'Delete me')],
      );
      await store.saveDocument(doc);

      final loaded = await store.loadDocument('delete-me');
      expect(loaded, isNotNull);

      final deleted = await store.deleteDocument('delete-me');
      expect(deleted, isTrue);

      final loadedAfter = await store.loadDocument('delete-me');
      expect(loadedAfter, isNull);
    });

    test('完整流程：保存 → 重开 → 见变更', () async {
      final store = NoteBlockDocStore(directoryProvider: () async => tempDir);

      // 1. 创建并保存
      final initialDoc = makeDoc(
        id: 'flow-doc',
        title: 'Flow Test',
        body: [NoteBlock.textBlock('t1', text: 'Before edit')],
      );
      await store.saveDocument(initialDoc);

      // 2. 加载并验证
      final loaded1 = await store.loadDocument('flow-doc');
      expect(loaded1, isNotNull);
      expect(loaded1!.body.first.text, 'Before edit');

      // 3. 修改并保存
      final updatedDoc = loaded1.copyWith(
        body: [NoteBlock.textBlock('t1', text: 'After edit')],
        updatedAt: DateTime(2026, 8, 28, 1),
      );
      await store.saveDocument(updatedDoc);

      // 4. 重新加载并验证
      final loaded2 = await store.loadDocument('flow-doc');
      expect(loaded2, isNotNull);
      expect(loaded2!.body.first.text, 'After edit');
    });
  });
}
