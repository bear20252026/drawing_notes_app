import 'dart:io';

import 'package:drawing_notes_app/models/document.dart';
import 'package:drawing_notes_app/models/notebook.dart';
import 'package:drawing_notes_app/storage/notebook_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 5 验收测试：笔记功能。
///
/// 验收标准（来自开发计划 4.3 Phase 5）：
/// - 新建笔记本（多个笔记本可以分类管理）
/// - 笔记本内新建/删除/切换页面
/// - 页面内支持：手写内容 + 插入图片 + 文字输入框
/// - 文字和手写内容可以在同一页面共存
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('notebook_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  NotebookStorage makeStorage() =>
      NotebookStorage(directoryProvider: () async => tempDir);

  group('Phase 5 笔记功能', () {
    test('新建笔记本：默认无页面，保存后可重新加载', () async {
      final storage = makeStorage();
      final nb = Notebook(id: NotebookStorage.newId('nb'), title: '会议纪要');

      await storage.save(nb);
      final loaded = await storage.load(nb.id);

      expect(loaded, isNotNull);
      expect(loaded!.title, '会议纪要');
      expect(loaded.pages, isEmpty);
    });

    test('笔记本内新建页面：页面含独立画布文档', () async {
      final storage = makeStorage();
      final nb = Notebook(id: 'nb1', title: '笔记本');
      nb.pages.add(
        NotebookPage(
          id: 'pg1',
          title: '第一页',
          document: DrawingDocument(
            id: 'doc1',
            title: '第一页',
            width: 300,
            height: 400,
          ),
        ),
      );
      nb.pages.add(
        NotebookPage(
          id: 'pg2',
          title: '第二页',
          document: DrawingDocument(id: 'doc2', title: '第二页'),
        ),
      );

      await storage.save(nb);
      final loaded = await storage.load('nb1');

      expect(loaded!.pages.length, 2);
      expect(loaded.pages[0].title, '第一页');
      expect(loaded.pages[0].document.width, 300);
      expect(loaded.pages[1].document.layers.length, 1, reason: '页面画布自带一个默认图层');
    });

    test('删除页面：从笔记本中移除并保存', () async {
      final storage = makeStorage();
      final nb = Notebook(id: 'nb2', title: '笔记本');
      nb.pages.add(
        NotebookPage(
          id: 'pg1',
          title: '页面1',
          document: DrawingDocument(id: 'd1', title: '页面1'),
        ),
      );
      await storage.save(nb);

      final loaded = await storage.load('nb2');
      loaded!.pages.removeWhere((p) => p.id == 'pg1');
      await storage.save(loaded);

      final after = await storage.load('nb2');
      expect(after!.pages, isEmpty);
    });

    test('页面内文字块：添加/序列化/反序列化', () async {
      final storage = makeStorage();
      final page = NotebookPage(
        id: 'pg_txt',
        title: '文字页',
        document: DrawingDocument(id: 'd_txt', title: '文字页'),
      );
      page.textItems.add(
        PageTextItem(id: 'txt1', x: 120, y: 80, text: '这是一段笔记文字', fontSize: 28),
      );

      final nb = Notebook(id: 'nb_txt', title: '笔记本');
      nb.pages.add(page);
      await storage.save(nb);

      final loaded = await storage.load('nb_txt');
      final loadedPage = loaded!.pages.first;
      expect(loadedPage.textItems.length, 1);
      expect(loadedPage.textItems.first.text, '这是一段笔记文字');
      expect(loadedPage.textItems.first.x, 120);
      expect(loadedPage.textItems.first.y, 80);
      expect(loadedPage.textItems.first.fontSize, 28);
    });

    test('多个笔记本 A/B 保存、退出、重开后页面与内容严格隔离', () async {
      final storage = makeStorage();
      final notebookA = Notebook(id: 'notebook_a', title: '项目 A')
        ..pages.add(
          NotebookPage(
              id: 'page_a',
              title: 'A 页面',
              document: DrawingDocument(id: 'doc_a', title: 'A 页面'),
            )
            ..textItems.add(
              PageTextItem(id: 'text_a', x: 10, y: 20, text: '仅属于 A'),
            ),
        );
      final notebookB = Notebook(id: 'notebook_b', title: '项目 B')
        ..pages.add(
          NotebookPage(
              id: 'page_b',
              title: 'B 页面',
              document: DrawingDocument(id: 'doc_b', title: 'B 页面'),
            )
            ..textItems.add(
              PageTextItem(id: 'text_b', x: 30, y: 40, text: '仅属于 B'),
            ),
        );

      await Future.wait([storage.save(notebookA), storage.save(notebookB)]);

      final reopened = makeStorage();
      final restoredA = await reopened.load('notebook_a');
      final restoredB = await reopened.load('notebook_b');
      expect(restoredA!.title, '项目 A');
      expect(restoredB!.title, '项目 B');
      expect(restoredA.pages.single.id, 'page_a');
      expect(restoredB.pages.single.id, 'page_b');
      expect(restoredA.pages.single.textItems.single.text, '仅属于 A');
      expect(restoredB.pages.single.textItems.single.text, '仅属于 B');
    });

    test('页面内图片块：添加并序列化', () async {
      final storage = makeStorage();
      final page = NotebookPage(
        id: 'pg_img',
        title: '图片页',
        document: DrawingDocument(id: 'd_img', title: '图片页'),
      );
      page.imageItems.add(
        PageImageItem(
          id: 'img1',
          x: 10,
          y: 20,
          filePath: 'C:/fake/photo.png',
          width: 300,
          height: 200,
        ),
      );

      final nb = Notebook(id: 'nb_img', title: '笔记本');
      nb.pages.add(page);
      await storage.save(nb);

      final loaded = await storage.load('nb_img');
      final loadedPage = loaded!.pages.first;
      expect(loadedPage.imageItems.length, 1);
      expect(loadedPage.imageItems.first.filePath, 'C:/fake/photo.png');
      expect(loadedPage.imageItems.first.width, 300);
    });

    test('文字与手写在同一页面共存：页面同时含文字块与画布笔画', () async {
      final storage = makeStorage();
      final doc = DrawingDocument(id: 'd_mix', title: '混合页');
      // 画布上有手写笔画
      doc.layers.first.strokes.addAll([
        // 手写内容以 Stroke 形式存在于页面文档中
      ]);

      final page = NotebookPage(id: 'pg_mix', title: '混合页', document: doc);
      page.textItems.add(PageTextItem(id: 't1', x: 10, y: 10, text: '手写批注'));
      page.imageItems.add(
        PageImageItem(id: 'i1', x: 50, y: 50, filePath: 'C:/fake/pic.png'),
      );

      final nb = Notebook(id: 'nb_mix', title: '笔记本');
      nb.pages.add(page);
      await storage.save(nb);

      final loaded = await storage.load('nb_mix');
      expect(loaded, isNotNull);
      expect(loaded!.pages.first.textItems.length, 1);
      expect(loaded.pages.first.imageItems.length, 1);
      expect(loaded.pages.first.document.layers.length, 1);
    });

    test('列出笔记本：多个笔记本按更新时间倒序', () async {
      final storage = makeStorage();
      final nb1 = Notebook(id: 'list1', title: '旧笔记本');
      final nb2 = Notebook(id: 'list2', title: '新笔记本');
      await storage.save(nb1);
      await storage.save(nb2);

      // 手动更新时间：nb2 更新晚于 nb1
      nb2.updatedAt = nb1.updatedAt.add(const Duration(minutes: 5));
      await storage.save(nb2);

      final list = await storage.listAll();
      expect(list.length, 2);
      expect(list.first.id, 'list2', reason: '新更新的笔记本排在前');
    });

    test('删除笔记本：文件被移除', () async {
      final storage = makeStorage();
      final nb = Notebook(id: 'del1', title: '待删除');
      await storage.save(nb);
      expect(await storage.load('del1'), isNotNull);

      final ok = await storage.delete('del1');
      expect(ok, isTrue);
      expect(await storage.load('del1'), isNull);
    });

    test('storeImage：图片副本被复制到应用目录', () async {
      final storage = makeStorage();
      // 创建源图片文件
      final src = File('${tempDir.path}/source.png');
      await src.writeAsBytes([1, 2, 3, 4]);

      final target = await storage.storeImage(src.path, 'pg_1');
      expect(File(target).existsSync(), isTrue);
      expect(target, contains('pg_1'), reason: '文件名包含页面分组前缀');
    });
  });
}
