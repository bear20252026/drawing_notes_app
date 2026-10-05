// M12.6 回归：回收站 / 标签 / Toggle 块 / HTML 导出 / 模板库。

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/core/storage/tag_store.dart';
import 'package:drawing_notes_app/features/doc/application/doc_html_export.dart';
import 'package:drawing_notes_app/features/doc/application/doc_templates.dart';
import 'package:drawing_notes_app/core/documents/note_block.dart';
import 'package:drawing_notes_app/core/documents/note_block_doc.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block_doc_markdown.dart';
import 'package:drawing_notes_app/core/documents/note_block_doc_store.dart';

import '../../helpers/temp_dir_cleanup.dart';

final _tempDirs = <Directory>[];

Future<Directory> _tempDir() async {
  final dir = await Directory.systemTemp.createTemp('m126_test');
  _tempDirs.add(dir);
  return dir;
}

/// 回收站里某个 id 的**一对**盘上文件：正文 `<id>.json` 与配套 sidecar
/// `<id>.json.meta.json`（路径口径同 `note_block_doc_store_trash.dart`
/// 的 `_trashPathFor`：`<base>/blockdocs_trash/<id>.json`，sidecar 追加
/// `.meta.json`）。T-01 残留断言用它把「正文删了、元数据还在」钉死。
({File doc, File meta}) _trashFilesOf(Directory base, String id) {
  final doc = File(
    '${base.path}${Platform.pathSeparator}blockdocs_trash'
    '${Platform.pathSeparator}$id.json',
  );
  return (doc: doc, meta: File('${doc.path}.meta.json'));
}

void main() {
  tearDownAll(() async {
    for (final d in _tempDirs) {
      await deleteTempDirWithRetry(d);
    }
  });
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
      expect(trash.single.id, 'trash1');
      expect(trash.single.title, '被删的笔记');

      // 恢复：回到激活区、回收站清空
      expect(await store.restoreDocument('trash1'), isTrue);
      expect((await store.loadDocument('trash1'))!.title, '被删的笔记');
      expect(await store.listTrash(), isEmpty);
    });

    test('purgeFromTrash 彻底删除回收站条目（T-01 审计 2026-09-27）', () async {
      // 本用例还要断**盘上**文件，故自建捕获目录版 store：组 setUp 的 store
      // 用 `_tempDir`（每次调用新建目录），测试拿不到它缓存的 base。
      Directory? captured;
      final localStore = NoteBlockDocStore(
        directoryProvider: () async => captured ??= await _tempDir(),
      );
      final doc = NoteBlockDoc(
        id: 'purge1',
        title: '回收站里的笔记',
        createdAt: DateTime(2026, 8, 31),
        updatedAt: DateTime(2026, 8, 31),
      );
      await localStore.saveDocument(doc);
      expect(await localStore.deleteDocument('purge1'), isTrue);
      expect(await localStore.listTrash(), hasLength(1));

      // T-01 残留断言（2026-10-04）：`_purgeFromTrashLocked` 删正文后再尽力删
      // sidecar（note_block_doc_store_trash.dart:336-343，catch 吞错的幂等清理）。
      // 只断 listTrash/load 时「正文删了、`.meta.json` 残留」完全看不出来，
      // 故 purge 前先把两份文件的存在性钉住，purge 后断双双消失。
      final purged = _trashFilesOf(captured!, 'purge1');
      expect(purged.doc.existsSync(), isTrue, reason: '回收站正文应已落盘');
      expect(
        purged.meta.existsSync(),
        isTrue,
        reason: 'deleteDocument 应已写 sidecar',
      );

      // 彻底删除：回收站清空、激活区不可见——不可逆销毁路径必须有回归锁。
      expect(await localStore.purgeFromTrash('purge1'), isTrue);
      expect(await localStore.listTrash(), isEmpty);
      expect(await localStore.loadDocument('purge1'), isNull);
      expect(
        purged.doc.existsSync(),
        isFalse,
        reason: '正文须已从盘上删除（与 listTrash 计数互证）',
      );
      expect(
        purged.meta.existsSync(),
        isFalse,
        reason:
            'sidecar 不得残留：删除上下文（deletedAt 等）留在盘上等于'
            '「彻底删除」只删了一半',
      );

      // 幂等：对不存在的条目再删返回 false。
      expect(await localStore.purgeFromTrash('purge1'), isFalse);
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
      expect(trash.single.title, '第二版');

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
      // 加固（2026-10-04）：原断言 `purged >= 1` 而场景里只有 1 条过期——
      // 清扫器把未过期条目一并烧掉（过度清扫，真实用户症状是「回收站被清空」）
      // 照样能过。现改为精确 equals(1) + 「未过期兄弟项必须存活」双锁。
      //
      // provider 每次调用都会新建临时目录（`_dir`/`_trashDir` 各自首次调用时
      // 缓存），这里缓存同一个 base，保证文档区与回收站在同一棵目录树下。
      Directory? base;
      final store = NoteBlockDocStore(
        directoryProvider: () async {
          return base ??= await _tempDir();
        },
      );
      final expiredDoc = NoteBlockDoc(
        id: 'old1',
        title: '过期条目',
        createdAt: DateTime(2026, 8, 31),
        updatedAt: DateTime(2026, 8, 31),
      );
      final freshDoc = NoteBlockDoc(
        id: 'fresh1',
        title: '未过期条目',
        createdAt: DateTime(2026, 8, 31),
        updatedAt: DateTime(2026, 8, 31),
      );
      await store.saveDocument(expiredDoc);
      await store.saveDocument(freshDoc);
      expect(await store.deleteDocument('old1'), isTrue);
      expect(await store.deleteDocument('fresh1'), isTrue);
      expect(await store.listTrash(), hasLength(2));

      // 删除时间读取源是 sidecar JSON 的 deletedAt（C14）——只把 old1 推到
      // 31 天前，fresh1 保持「刚刚删除」，于是**过期项恰好 1 条**。
      final expired = _trashFilesOf(base!, 'old1');
      final survivor = _trashFilesOf(base!, 'fresh1');
      expect(
        expired.meta.existsSync(),
        isTrue,
        reason: 'deleteDocument 应已写 sidecar',
      );
      await expired.meta.writeAsString(
        jsonEncode({
          'deletedAt': DateTime.now()
              .subtract(const Duration(days: 31))
              .toIso8601String(),
        }),
      );

      final purged = await store.purgeExpiredTrash(retainDays: 30);
      expect(
        purged,
        equals(1),
        reason:
            '场景里恰好 1 条过期（old1）——purged > 1 说明连未过期条目一起'
            '烧掉了，正是本用例要抓的过度清扫',
      );

      final trash = await store.listTrash();
      expect(trash, hasLength(1), reason: '未过期的兄弟项必须存活在回收站里');
      expect(trash.single.id, 'fresh1');
      expect(
        await store.loadDocument('fresh1'),
        isNull,
        reason: '存活项仍是软删除状态，不得被复活到激活区',
      );
      expect(
        await store.loadDocument('old1'),
        isNull,
        reason: '过期项已从激活区消失（本用例只依赖回收站侧计数）',
      );

      // T-01 残留断言（2026-10-04 测试侧加固）：以上全是**API 视图**的计数
      // （listTrash / loadDocument），清扫器只删正文、把配套 `.meta.json`
      // sidecar 留在盘上时照样能过——而 sidecar 存的是 deletedAt 等删除上下文，
      // 残留意味着「已彻底删除的笔记」其删除时间线仍可从目录里枚举出来。
      // 故过期项的**两份**文件都必须真从盘上消失。
      expect(
        expired.doc.existsSync(),
        isFalse,
        reason: '过期项正文 old1.json 应已从盘上删除',
      );
      expect(
        expired.meta.existsSync(),
        isFalse,
        reason:
            '过期项 sidecar old1.json.meta.json 不得残留（防正文删了、'
            '元数据还在）',
      );
      // 反向锁：存活项（未过期）的两份文件都必须在位——只该删过期项的配对，
      // 既不能只删一半，也不能顺手把兄弟项的元数据一起清掉。
      expect(survivor.doc.existsSync(), isTrue, reason: '未过期项正文必须仍在盘上');
      expect(
        survivor.meta.existsSync(),
        isTrue,
        reason: '未过期项 sidecar 必须仍在盘上（deletedAt 是过期判定的读取源）',
      );
    });

    test('T-01 残留收口：孤儿 sidecar 由过期清扫回扫删除（AR 批 2026-10-05）', () async {
      // 上一轮的 T-01 断言只覆盖 happy path（正文与 meta 都在/都不在）。
      // 产码窗口是「正文删成功、meta 删失败」——盘上留下 `<id>.json.meta.json`
      // 孤儿，删除时间线仍可被枚举。现在 purgeExpiredTrash 末尾回扫孤儿。
      Directory? base;
      final store = NoteBlockDocStore(
        directoryProvider: () async => base ??= await _tempDir(),
      );
      await store.saveDocument(
        NoteBlockDoc(
          id: 'orphan1',
          title: '孤儿对照',
          createdAt: DateTime(2026, 8, 31),
          updatedAt: DateTime(2026, 8, 31),
        ),
      );
      expect(await store.deleteDocument('orphan1'), isTrue);
      final orphan = _trashFilesOf(base!, 'orphan1');
      expect(orphan.meta.existsSync(), isTrue, reason: 'deleteDocument 应已写 sidecar');
      // 制造删除失败后的盘上状态：只剩 sidecar。
      orphan.doc.deleteSync();

      // retainDays 给很大值 ⇒ 本轮「没有任何条目过期」，但孤儿回扫仍应执行。
      await store.purgeExpiredTrash(retainDays: 3650);
      expect(
        orphan.meta.existsSync(),
        isFalse,
        reason: '正文已不存在的孤儿 sidecar 应被回扫删除',
      );

      // 反向锁：配对完整（正文仍在）的 sidecar 不得被回扫误删——
      // 否则过期判定源 deletedAt 就没了，回收站会显示成错误时间。
      await store.saveDocument(
        NoteBlockDoc(
          id: 'keep1',
          title: '配对完整项',
          createdAt: DateTime(2026, 8, 31),
          updatedAt: DateTime(2026, 8, 31),
        ),
      );
      expect(await store.deleteDocument('keep1'), isTrue);
      final kept = _trashFilesOf(base!, 'keep1');
      expect(kept.doc.existsSync(), isTrue);
      await store.purgeExpiredTrash(retainDays: 3650);
      expect(
        kept.meta.existsSync(),
        isTrue,
        reason: '正文仍在的 sidecar 不得被孤儿回扫误删（它是 deletedAt 的读取源）',
      );
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
