// 命名同源收敛回归（2026-09-07）：同一逻辑文件（分页画布页 ↔ 块文档副本
// 同 id、克隆引用页 ↔ 源页）在所有展示区必须同名且改名同步。
//
// 双向收敛以「打开时页标题快照」防回跳：
// - 本会话改过名的页 → 页面标题优先（renamed 集合返回，调用方回写副本）；
// - 未改过名但块文档标题不同 → 块文档标题优先（页卡跟随外部改名）；
// - 克隆引用页 → 恒跟随源页当前标题。
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/features/notes/application/notebook_title_sync.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';

NotebookPage _page(String id, String title, {CloneRef? cloneOf}) =>
    NotebookPage(
      id: id,
      title: title,
      document: DrawingDocument(id: 'doc-$id', title: title),
      cloneOf: cloneOf,
    );

void main() {
  group('NotebookTitleSync.convergeBeforeSave', () {
    test('块文档改名优先：未改名的页跟随块文档新标题（doc-wins）', () {
      final nb = Notebook(id: 'nb', title: '本', pages: [_page('p1', '旧页名')]);
      final renamed = NotebookTitleSync.convergeBeforeSave(
        notebook: nb,
        blockDocTitleById: {'p1': '新笔记名'},
        pageTitlesAtOpen: {'p1': '旧页名'},
        externalSourceTitles: const {},
      );
      expect(nb.pages.first.title, '新笔记名');
      expect(renamed, isEmpty);
    });

    test('页面改名优先：本会话改名的页不回跳，id 进 renamed 集合', () {
      final nb = Notebook(
        id: 'nb',
        title: '本',
        pages: [_page('p1', '画布里改的新名')],
      );
      final renamed = NotebookTitleSync.convergeBeforeSave(
        notebook: nb,
        blockDocTitleById: {'p1': '副本旧名'},
        pageTitlesAtOpen: {'p1': '打开时的旧名'},
        externalSourceTitles: const {},
      );
      expect(nb.pages.first.title, '画布里改的新名');
      expect(renamed, {'p1'});
    });

    test('克隆页跟随源页当前标题（同本源 + 外部源）', () {
      final nb = Notebook(
        id: 'nb',
        title: '本',
        pages: [
          _page('src', '源页新名'),
          _page(
            'c1',
            '↪ 源页旧名',
            cloneOf: CloneRef(notebookId: 'nb', pageId: 'src'),
          ),
          _page(
            'c2',
            '↪ 旧快照',
            cloneOf: CloneRef(notebookId: 'ext-nb', pageId: 'ext1'),
          ),
        ],
      );
      NotebookTitleSync.convergeBeforeSave(
        notebook: nb,
        blockDocTitleById: const {},
        pageTitlesAtOpen: const {},
        externalSourceTitles: {'ext1': '外部源新名'},
      );
      expect(nb.pages[1].title, '↪ 源页新名');
      expect(nb.pages[2].title, '↪ 外部源新名');
    });

    test('无变化时幂等：重复收敛不产生 renamed、不改动标题', () {
      final nb = Notebook(id: 'nb', title: '本', pages: [_page('p1', '一致名')]);
      for (var i = 0; i < 2; i++) {
        final renamed = NotebookTitleSync.convergeBeforeSave(
          notebook: nb,
          blockDocTitleById: {'p1': '一致名'},
          pageTitlesAtOpen: {'p1': '一致名'},
          externalSourceTitles: const {},
        );
        expect(renamed, isEmpty);
        expect(nb.pages.first.title, '一致名');
      }
    });
  });

  group('NotebookTitleSync.followCloneSnapshots', () {
    test('跨本克隆快照跟随源页，返回有变更', () {
      final other = Notebook(
        id: 'nb2',
        title: '别本',
        pages: [
          _page(
            'c1',
            '↪ 旧名',
            cloneOf: CloneRef(notebookId: 'nb', pageId: 'p1'),
          ),
        ],
      );
      final changed = NotebookTitleSync.followCloneSnapshots(
        notebook: other,
        sourceTitlesByPageId: {'p1': '源页新名'},
      );
      expect(changed, isTrue);
      expect(other.pages.first.title, '↪ 源页新名');
    });

    test('已一致的克隆无变更（幂等）', () {
      final other = Notebook(
        id: 'nb2',
        title: '别本',
        pages: [
          _page(
            'c1',
            '↪ 源页新名',
            cloneOf: CloneRef(notebookId: 'nb', pageId: 'p1'),
          ),
        ],
      );
      final changed = NotebookTitleSync.followCloneSnapshots(
        notebook: other,
        sourceTitlesByPageId: {'p1': '源页新名'},
      );
      expect(changed, isFalse);
    });
  });

  test('cloneTitleFor：克隆标题格式统一为 ↪ 前缀', () {
    expect(NotebookTitleSync.cloneTitleFor('源页'), '↪ 源页');
  });
}
