// M12.6 回归：回收站 / 标签 / Toggle 块 / HTML 导出 / 模板库。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/features/all_docs/infrastructure/tag_store.dart';
import 'package:drawing_notes_app/features/doc/application/doc_html_export.dart';
import 'package:drawing_notes_app/features/doc/application/doc_templates.dart';
import 'package:drawing_notes_app/features/notes/domain/note_block.dart';
import 'package:drawing_notes_app/features/notes/domain/note_block_doc.dart';
import 'package:drawing_notes_app/features/notes/domain/note_block_doc_markdown.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/note_block_doc_store.dart';

Future<Directory> _tempDir() async =>
    Directory.systemTemp.createTemp('m126_test');

void main() {
  group('回收站（软删除）', () {
    late NoteBlockDocStore store;

    setUp(() async {
      store = NoteBlockDocStore(directoryProvider: _tempDir);
    });

    test('delete → listTrash → restore 全链路', () async {
      final doc = NoteBlockDoc(
        id: 'trash1',
        title: '被删的笔记',
        createdAt: DateTime(2026, 8, 31),
        updatedAt: DateTime(2026, 8, 31),
      );
      await store.saveDocument(doc);

      // 软删除：激活区消失、回收站出现
      expect(await store.deleteDocument('trash1'), isTrue);
      expect(await store.loadDocument('trash1'), isNull);
      expect(await store.listIds(), isNot(contains('trash1')));

      final trash = await store.listTrash();
      expect(trash, hasLength(1));
      expect(trash.single.doc.id, 'trash1');
      expect(trash.single.doc.title, '被删的笔记');

      // 恢复：回到激活区、回收站清空
      expect(await store.restoreDocument('trash1'), isTrue);
      expect((await store.loadDocument('trash1'))!.title, '被删的笔记');
      expect(await store.listTrash(), isEmpty);
    });

    test('purgeDocument 彻底删除（不进回收站）', () async {
      final doc = NoteBlockDoc(
        id: 'gone1',
        title: '彻底删除',
        createdAt: DateTime(2026, 8, 31),
        updatedAt: DateTime(2026, 8, 31),
      );
      await store.saveDocument(doc);
      expect(await store.purgeDocument('gone1'), isTrue);
      expect(await store.loadDocument('gone1'), isNull);
      expect(await store.listTrash(), isEmpty);
    });

    test('写尾队列：save 与 delete 交错时按提交顺序执行（P0-H3）', () async {
      // 不 await save：模拟自动保存 Future 在飞行中发起删除。
      final doc1 = NoteBlockDoc(
        id: 'race1',
        title: '第一版',
        createdAt: DateTime(2026, 8, 31),
        updatedAt: DateTime(2026, 8, 31),
      );
      await store.saveDocument(doc1);
      final saveFuture = store.saveDocument(
        doc1.copyWith(title: '第二版', updatedAt: DateTime(2026, 8, 31, 1)),
      );
      final deleteFuture = store.deleteDocument('race1');
      await Future.wait([saveFuture, deleteFuture]);

      // 串行化保证：save 先入队先执行，delete 后入队后执行 →
      // 激活区为空（删除生效）、回收站内容是删除前最后一版「第二版」。
      expect(await store.loadDocument('race1'), isNull);
      final trash = await store.listTrash();
      expect(trash, hasLength(1));
      expect(trash.single.doc.title, '第二版');

      // 反向交错：delete 先入队、save 后入队 → 文档复活（保存语义优先）。
      await store.restoreDocument('race1');
      final deleteFuture2 = store.deleteDocument('race1');
      final saveFuture2 = store.saveDocument(
        doc1.copyWith(title: '复活版', updatedAt: DateTime(2026, 8, 31, 2)),
      );
      await Future.wait([deleteFuture2, saveFuture2]);
      final restored = await store.loadDocument('race1');
      expect(restored, isNotNull);
      expect(restored!.title, '复活版');
    });

    test('purgeExpiredTrash 清理过期条目', () async {
      final doc = NoteBlockDoc(
        id: 'old1',
        title: '过期条目',
        createdAt: DateTime(2026, 8, 31),
        updatedAt: DateTime(2026, 8, 31),
      );
      await store.saveDocument(doc);
      await store.deleteDocument('old1');
      // 31 天前删除 → 超过 30 天保留期
      final purged = await store.purgeExpiredTrash(retainDays: -1);
      expect(purged, greaterThanOrEqualTo(1));
      expect(await store.listTrash(), isEmpty);
    });
  });

  group('标签（TagStore + 文档 tags）', () {
    test('TagStore 增删改查 + 同名去重', () async {
      final store = TagStore(directoryProvider: _tempDir);
      final a = await store.addTag('工作');
      expect(a, isNotNull);
      expect((await store.addTag('工作'))!.id, a!.id); // 同名去重
      await store.addTag('生活');
      expect((await store.listTags()).length, 2);

      await store.renameTag(a.id, '工作事务');
      expect(
        (await store.listTags()).where((t) => t.id == a.id).single.name,
        '工作事务',
      );

      await store.deleteTag(a.id);
      expect((await store.listTags()).where((t) => t.id == a.id), isEmpty);
    });

    test('NoteBlockDoc.tags 序列化往返 + 旧数据兼容', () {
      final doc = NoteBlockDoc(
        id: 'd1',
        title: 't',
        tags: ['tag_1', 'tag_2'],
        createdAt: DateTime(2026, 8, 31),
        updatedAt: DateTime(2026, 8, 31),
      );
      final back = NoteBlockDoc.fromJson(doc.toJson());
      expect(back.tags, ['tag_1', 'tag_2']);
      // 旧数据无 tags 字段 → 空列表
      final legacy = NoteBlockDoc.fromJson({
        'id': 'd2',
        'title': 't',
        'body': <Object>[],
        'createdAt': '2026-08-31T00:00:00.000',
        'updatedAt': '2026-08-31T00:00:00.000',
      });
      expect(legacy.tags, isEmpty);
    });
  });

  group('Toggle 块', () {
    test('序列化往返 + Markdown 导出', () {
      final block = NoteBlock.toggleBlock('tg1', text: '展开标题', expanded: false);
      final back = NoteBlock.fromJson(block.toJson());
      expect(back.type, NoteBlockType.toggle);
      expect(back.props['expanded'], false);
      expect(back.text, '展开标题');

      final doc = NoteBlockDoc(
        id: 'd',
        title: 't',
        body: [block],
        createdAt: DateTime(2026, 8, 31),
        updatedAt: DateTime(2026, 8, 31),
      );
      expect(noteBlockDocToMarkdown(doc), contains('- ▸ 展开标题'));
    });
  });

  group('HTML 导出', () {
    test('标题/待办/代码/转义', () {
      final doc = NoteBlockDoc(
        id: 'd',
        title: 'HTML <测试>',
        body: [
          NoteBlock.headingBlock('h', level: 2, text: '标题与 <标签>'),
          NoteBlock.todoBlock('t', text: '完成', checked: true),
          NoteBlock.codeBlock('c', text: 'a < b && c > d'),
        ],
        createdAt: DateTime(2026, 8, 31),
        updatedAt: DateTime(2026, 8, 31),
      );
      final html = noteBlockDocToHtml(doc);
      expect(html, contains('<h2>标题与 &lt;标签&gt;</h2>'));
      expect(html, contains('checked'));
      expect(html, contains('a &lt; b &amp;&amp; c &gt; d'));
    });
  });

  group('模板库', () {
    test('会议纪要模板生成标题+待办块', () {
      var n = 0;
      final body = buildTemplateBody(DocTemplate.meeting, () => 'b${n++}');
      expect(body, isNotEmpty);
      expect(body.first.type, NoteBlockType.heading);
      expect(body.where((b) => b.type == NoteBlockType.todo), isNotEmpty);
      // id 唯一
      expect(body.map((b) => b.id).toSet().length, body.length);
    });

    test('空白模板单个空段', () {
      final body = buildTemplateBody(DocTemplate.blank, () => 'b0');
      expect(body, hasLength(1));
      expect(body.single.type, NoteBlockType.text);
      expect(body.single.text, '');
    });
  });
}
