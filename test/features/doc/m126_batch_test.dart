// M12.6 回归：回收站 / 标签 / Toggle 块 / HTML 导出 / 模板库。

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/core/storage/tag_store.dart';
import 'package:drawing_notes_app/features/doc/application/doc_html_export.dart';
import 'package:drawing_notes_app/features/doc/application/doc_templates.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block_doc.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block_doc_markdown.dart';
import 'package:drawing_notes_app/features/doc/infrastructure/note_block_doc_store.dart';

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

    test('C14：删除时间读取 sidecar JSON 的 deletedAt 字段（非 mtime）', () async {
      // 捕获目录：directoryProvider 每次调用生成新临时目录，需拿到首个。
      late Directory captured;
      final store = NoteBlockDocStore(
        directoryProvider: () async {
          captured = await _tempDir();
          return captured;
        },
      );
      final doc = NoteBlockDoc(
        id: 'mtime1',
        title: '时间源',
        createdAt: DateTime(2026, 8, 31),
        updatedAt: DateTime(2026, 8, 31),
      );
      await store.saveDocument(doc);
      await store.deleteDocument('mtime1');
      // 写入侧 sidecar 是 jsonEncode({'deletedAt': iso})——旧读取侧对整串
      // tryParse 永远失败回退 mtime；修复后应取到 JSON 字段值（此处为
      // 2020 年，明显区别于文件 mtime）。
      final old = DateTime(2020, 1, 1);
      final meta = File(
        '${captured.path}${Platform.pathSeparator}blockdocs_trash'
        '${Platform.pathSeparator}mtime1.json.meta.json',
      );
      expect(meta.existsSync(), isTrue, reason: 'sidecar meta 应已写出');
      await meta.writeAsString(
        jsonEncode({'deletedAt': old.toIso8601String()}),
      );
      final trash = await store.listTrash();
      expect(trash, hasLength(1));
      expect(trash.single.deletedAt, old);
    });

    test('C14：meta 为裸 ISO 串（非 JSON）时整串解析兼容', () async {
      late Directory captured;
      final store = NoteBlockDocStore(
        directoryProvider: () async {
          captured = await _tempDir();
          return captured;
        },
      );
      final doc = NoteBlockDoc(
        id: 'mtime2',
        title: '裸串',
        createdAt: DateTime(2026, 8, 31),
        updatedAt: DateTime(2026, 8, 31),
      );
      await store.saveDocument(doc);
      await store.deleteDocument('mtime2');
      final old = DateTime(2019, 6, 15, 8, 30);
      final meta = File(
        '${captured.path}${Platform.pathSeparator}blockdocs_trash'
        '${Platform.pathSeparator}mtime2.json.meta.json',
      );
      await meta.writeAsString(old.toIso8601String());
      final trash = await store.listTrash();
      expect(trash, hasLength(1));
      expect(trash.single.deletedAt, old);
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

    test('D15：标签名清洗（控制字符剥离 + 128 上限截断）', () async {
      final store = TagStore(directoryProvider: _tempDir);
      // 控制字符剥离 + trim。
      final t1 = await store.addTag(' 工\u0000作\u001F\t');
      expect(t1!.name, '工作');
      // 超长截断（不拒绝）。
      final long = await store.addTag('x' * 300);
      expect(long!.name.length, 128);
      // 清洗后为空 → 返回 null 不落盘。
      expect(await store.addTag('\u0000\u0007 \t'), isNull);
      // rename 同口径清洗。
      await store.renameTag(t1.id, ' 生\u007F活 ');
      expect(
        (await store.listTags()).where((t) => t.id == t1.id).single.name,
        '生活',
      );
    });

    test('D15：renameTag 拒绝改成其他标签已占用的同名', () async {
      final store = TagStore(directoryProvider: _tempDir);
      final a = await store.addTag('甲');
      final b = await store.addTag('乙');
      expect(a!.name, '甲');
      expect(b!.name, '乙');
      // 把「乙」改成「甲」→ 目标名被 a 占用 → 保持不变更。
      await store.renameTag(b.id, '甲');
      final tags = await store.listTags();
      expect(tags.where((t) => t.id == b.id).single.name, '乙');
      expect(tags.where((t) => t.id == a.id).single.name, '甲');
      // 改回自己的名字（幂等）不受影响。
      await store.renameTag(b.id, '乙');
      expect(
        (await store.listTags()).where((t) => t.id == b.id).single.name,
        '乙',
      );
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

    test('B11：body/children 畸形元素被过滤，不整体拒载', () {
      final good = NoteBlock.textBlock('b1', text: '正常块').toJson();
      // body 混入字符串/数字等畸形元素。
      final doc = NoteBlockDoc.fromJson({
        'id': 'd3',
        'title': 't',
        'body': <Object?>['junk', 42, good, null],
        'createdAt': '2026-08-31T00:00:00.000',
        'updatedAt': '2026-08-31T00:00:00.000',
      });
      expect(doc.body, hasLength(1));
      expect(doc.body.single.id, 'b1');
      // children 同理。
      final parent = NoteBlock.fromJson({
        'id': 'p1',
        'type': 'bullet',
        'children': <Object?>[
          'junk',
          {'id': 'c1', 'type': 'text'},
        ],
      });
      expect(parent.children, hasLength(1));
      expect(parent.children.single.id, 'c1');
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
