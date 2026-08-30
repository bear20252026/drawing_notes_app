// 由 Claude 团队生成 | Drawing Notes App
// AllDocQuery 三源统一查询测试。

import 'package:drawing_notes_app/core/storage/repository.dart';
import 'package:drawing_notes_app/features/all_docs/application/all_doc_query.dart';
import 'package:drawing_notes_app/features/all_docs/domain/all_doc.dart';
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook_entity.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook_page.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook_page_content.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 固定 "now"：2026-08-28 12:00（周四）
  final now = DateTime(2026, 8, 28, 12, 0);

  DocumentMeta mkCanvas(String id, DateTime updated, String folder) => DocumentMeta(
        id: id,
        title: 'Canvas $id',
        folder: folder,
        width: 2048,
        height: 1536,
        layerCount: 1,
        strokeCount: 0,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: updated,
      );

  Notebook mkNotebook(String id, String pageId, DateTime updated, String folder,
      {bool favorite = false}) {
    final doc = DrawingDocument(id: 'draw_$pageId', title: 'draw');
    final content = NotebookPageContent(document: doc);
    final page = NotebookPage(
      id: pageId,
      title: 'Page $pageId',
      content: content,
      folder: folder,
      favorite: favorite,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: updated,
    );
    return Notebook(id: id, title: 'NB $id', pages: [page]);
  }

  BlockDocMeta mkBlock(String id, DateTime updated, String folder,
          {DateTime? createdAt}) =>
      BlockDocMeta(
        id: id,
        title: 'Block $id',
        folder: folder,
        createdAt: createdAt ?? DateTime(2026, 1, 1),
        updatedAt: updated,
      );

  group('buildAllDocs', () {
    test('三源混合 → 统一 AllDoc 数与 kind 映射', () {
      final result = buildAllDocs(
        docs: [mkCanvas('c1', DateTime(2026, 8, 28, 9, 0), '')],
        notebooks: [mkNotebook('nb1', 'p1', DateTime(2026, 8, 27), '工作')],
        blockDocs: [mkBlock('b1', DateTime(2026, 8, 25), '笔记')],
        now: now,
      );

      expect(result.docs.length, 3);
      expect(result.docs.where((d) => d.kind == AllDocKind.canvas).length, 1);
      expect(result.docs.where((d) => d.kind == AllDocKind.note).length, 1);
      expect(result.docs.where((d) => d.kind == AllDocKind.blockdoc).length, 1);

      // folder 映射
      expect(result.docs.firstWhere((d) => d.kind == AllDocKind.note).folder, '工作');
      expect(result.docs.firstWhere((d) => d.kind == AllDocKind.blockdoc).folder, '笔记');

      // note 的 notebookId / pageId
      final note = result.docs.firstWhere((d) => d.kind == AllDocKind.note);
      expect(note.notebookId, 'nb1');
      expect(note.pageId, 'p1');

      // canvas 的 drawingId
      final canvas = result.docs.firstWhere((d) => d.kind == AllDocKind.canvas);
      expect(canvas.drawingId, 'c1');
    });

    test('按 updatedAt desc 排序', () {
      final result = buildAllDocs(
        docs: [mkCanvas('c1', DateTime(2026, 8, 20), '')],
        notebooks: [mkNotebook('nb1', 'p1', DateTime(2026, 8, 27), '')],
        blockDocs: [mkBlock('b1', DateTime(2026, 8, 25), '')],
        now: now,
      );

      expect(result.docs.length, 3);
      expect(result.docs[0].id, 'p1'); // 8-27
      expect(result.docs[1].id, 'b1'); // 8-25
      expect(result.docs[2].id, 'c1'); // 8-20

      // 严格 desc
      for (var i = 1; i < result.docs.length; i++) {
        expect(result.docs[i - 1].updatedAt.isAfter(result.docs[i].updatedAt) ||
            result.docs[i - 1].updatedAt.isAtSameMomentAs(result.docs[i].updatedAt),
            isTrue);
      }
    });

    test('去重：kind 内按 dedupKey 先入优先；跨 kind 同 id 保留 blockdoc（M12.5）', () {
      // 同 id 的 canvas + note + blockdoc：note 与 blockdoc 为同一逻辑笔记的
      // 双标签分叉（迁移副本同 id），保留 blockdoc 行；canvas id 不同，保留。
      final result = buildAllDocs(
        docs: [mkCanvas('x1', DateTime(2026, 8, 28, 9, 0), '')],
        notebooks: [mkNotebook('nb1', 'x1', DateTime(2026, 8, 27), '')], // page id = x1
        blockDocs: [mkBlock('x1', DateTime(2026, 8, 25), '')],
        now: now,
      );

      expect(result.docs.length, 2); // canvas + blockdoc（note 行被合并）
      expect(
        result.docs.where((d) => d.kind == AllDocKind.blockdoc).single.id,
        'x1',
      );
      expect(result.docs.where((d) => d.kind == AllDocKind.note), isEmpty);

      // 同 kind 同 id 重复 → 去重
      final result2 = buildAllDocs(
        docs: [
          mkCanvas('c1', DateTime(2026, 8, 28, 9, 0), ''),
          mkCanvas('c1', DateTime(2026, 8, 28, 10, 0), '其他'),
        ],
        notebooks: [],
        blockDocs: [],
        now: now,
      );
      expect(result2.docs.length, 1);
      // 先入优先：保留第一个（folder=''）
      expect(result2.docs.first.folder, '');
    });

    test('分组 sections 顺序 today→thisWeek→earlier→neverUpdated', () {
      final result = buildAllDocs(
        docs: [
          mkCanvas('c_today', DateTime(2026, 8, 28, 9, 0), ''),
          mkCanvas('c_earlier', DateTime(2026, 6, 1), ''),
        ],
        notebooks: [
          mkNotebook('nb1', 'p_week', DateTime(2026, 8, 25), ''),
        ],
        blockDocs: [
          mkBlock('b_never', DateTime(2026, 3, 3, 10, 0), '',
              createdAt: DateTime(2026, 3, 3, 10, 0)),
        ],
        now: now,
      );

      // 所有分组都有文档 → 4 个 section
      expect(result.sections.length, 4);
      expect(result.sections[0].group, AllDocGroup.today);
      expect(result.sections[1].group, AllDocGroup.thisWeek);
      expect(result.sections[2].group, AllDocGroup.earlier);
      expect(result.sections[3].group, AllDocGroup.neverUpdated);

      expect(result.sections[0].docs.first.id, 'c_today');
      expect(result.sections[1].docs.first.id, 'p_week');
      expect(result.sections[2].docs.first.id, 'c_earlier');
      expect(result.sections[3].docs.first.id, 'b_never');
    });

    test('空分组不出现在 sections 中', () {
      final result = buildAllDocs(
        docs: [mkCanvas('c1', DateTime(2026, 8, 28, 9, 0), '')],
        notebooks: [],
        blockDocs: [],
        now: now,
      );

      expect(result.sections.length, 1);
      expect(result.sections.first.group, AllDocGroup.today);
    });

    test('favoriteOnly 过滤：只保留 isFavorite==true', () {
      final result = buildAllDocs(
        docs: [mkCanvas('c1', DateTime(2026, 8, 28, 9, 0), '')],
        notebooks: [
          mkNotebook('nb1', 'p_fav', DateTime(2026, 8, 27), '', favorite: true),
          mkNotebook('nb2', 'p_nofav', DateTime(2026, 8, 26), '', favorite: false),
        ],
        blockDocs: [mkBlock('b1', DateTime(2026, 8, 25), '')],
        now: now,
        favoriteOnly: true,
      );

      expect(result.docs.length, 1);
      expect(result.docs.first.id, 'p_fav');
    });

    test('favoriteOnly 时仍按 updatedAt desc 排序', () {
      final result = buildAllDocs(
        docs: [],
        notebooks: [
          mkNotebook('nb1', 'p_old', DateTime(2026, 8, 25), '', favorite: true),
          mkNotebook('nb2', 'p_new', DateTime(2026, 8, 27), '', favorite: true),
        ],
        blockDocs: [],
        now: now,
        favoriteOnly: true,
      );

      expect(result.docs.length, 2);
      expect(result.docs[0].id, 'p_new');
      expect(result.docs[1].id, 'p_old');
    });

    test('空源 → 空 sections', () {
      final result = buildAllDocs(
        docs: [],
        notebooks: [],
        blockDocs: [],
        now: now,
      );

      expect(result.docs, isEmpty);
      expect(result.sections, isEmpty);
    });

    test('多 notebook 多 page 聚合正确', () {
      final doc = DrawingDocument(id: 'd', title: 'd');
      final content = NotebookPageContent(document: doc);
      final nb = Notebook(id: 'nb', title: 'NB', pages: [
        NotebookPage(
            id: 'p1', title: 'P1', content: content, createdAt: DateTime(2026, 1, 1), updatedAt: DateTime(2026, 8, 27)),
        NotebookPage(
            id: 'p2', title: 'P2', content: content, createdAt: DateTime(2026, 1, 1), updatedAt: DateTime(2026, 8, 26)),
        NotebookPage(
            id: 'p3', title: 'P3', content: content, createdAt: DateTime(2026, 1, 1), updatedAt: DateTime(2026, 8, 25)),
      ]);

      final result = buildAllDocs(
        docs: [],
        notebooks: [nb],
        blockDocs: [],
        now: now,
      );

      expect(result.docs.length, 3);
      expect(result.docs.map((d) => d.id).toList(), ['p1', 'p2', 'p3']);
      for (final d in result.docs) {
        expect(d.kind, AllDocKind.note);
        expect(d.notebookId, 'nb');
      }
    });

    test('determinism: same input → same output', () {
      final args = {
        'docs': [mkCanvas('c1', DateTime(2026, 8, 28, 9, 0), '')],
        'notebooks': [mkNotebook('nb1', 'p1', DateTime(2026, 8, 27), '')],
        'blockDocs': [mkBlock('b1', DateTime(2026, 8, 25), '')],
        'now': now,
      };

      final r1 = buildAllDocs(
          docs: args['docs'] as List<DocumentMeta>,
          notebooks: args['notebooks'] as List<Notebook>,
          blockDocs: args['blockDocs'] as List<BlockDocMeta>,
          now: args['now'] as DateTime);
      final r2 = buildAllDocs(
          docs: args['docs'] as List<DocumentMeta>,
          notebooks: args['notebooks'] as List<Notebook>,
          blockDocs: args['blockDocs'] as List<BlockDocMeta>,
          now: args['now'] as DateTime);

      expect(r1.docs.length, r2.docs.length);
      expect(r1.sections.length, r2.sections.length);
      for (var i = 0; i < r1.docs.length; i++) {
        expect(r1.docs[i], r2.docs[i]);
      }
    });
  });
}
