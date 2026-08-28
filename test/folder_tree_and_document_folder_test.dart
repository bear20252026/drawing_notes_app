import 'package:drawing_notes_app/core/storage/repository.dart';
import 'package:drawing_notes_app/features/drawing/domain/document.dart';
import 'package:drawing_notes_app/features/home/presentation/folder_tree_builder.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DocumentMeta meta({
    required String id,
    required String title,
    String folder = '',
    DateTime? at,
  }) =>
      DocumentMeta(
        id: id,
        title: title,
        width: 2048,
        height: 1536,
        createdAt: at ?? DateTime.utc(2026, 8, 1),
        updatedAt: at ?? DateTime.utc(2026, 8, 1),
        layerCount: 0,
        strokeCount: 0,
        folder: folder,
      );

  Notebook note({
    required String id,
    required String folder,
    String pageTitle = '页面',
  }) =>
      Notebook(
        id: id,
        title: '笔记本$id',
        pages: [
          NotebookPage(
            id: '$id-page',
            title: pageTitle,
            document: DrawingDocument(id: '$id-page', title: pageTitle),
            folder: folder,
          ),
        ],
      );

  test('同一文件夹下画板与笔记页都能出现（不割裂）', () {
    final tree = FolderTree.build(
      docs: [
        meta(id: 'canvas-1', title: '设计草图', folder: '工作/项目A'),
        meta(id: 'canvas-2', title: '随手涂鸦'), // 根目录
      ],
      notebooks: [
        note(id: 'nb-1', folder: '工作/项目A', pageTitle: '会议纪要'),
        note(id: 'nb-2', folder: '生活'),
      ],
    );

    final work = tree.root.children.singleWhere((c) => c.name == '工作');
    final projectA = work.children.singleWhere((c) => c.name == '项目A');

    // 同一个文件夹里既有画板又有笔记
    expect(
      projectA.items.where((i) => i.kind == FolderItemKind.canvas),
      hasLength(1),
    );
    expect(
      projectA.items.where((i) => i.kind == FolderItemKind.note),
      hasLength(1),
    );

    // 根目录有画板，生活目录有笔记
    expect(tree.root.items.map((i) => i.title), contains('随手涂鸦'));
    final life = tree.root.children.singleWhere((c) => c.name == '生活');
    expect(life.items.single.kind, FolderItemKind.note);
  });

  test('多级路径正确切分并归入对应文件夹', () {
    final tree = FolderTree.build(
      docs: [meta(id: 'c', title: '深度文档', folder: 'A/B/C')],
      notebooks: [],
    );
    expect(tree.root.children.single.name, 'A');
    expect(tree.root.children.single.children.single.name, 'B');
    final c = tree.root.children.single.children.single.children.single;
    expect(c.name, 'C');
    expect(c.items.single.title, '深度文档');
  });

  test('DrawingDocument 文件夹字段序列化往返保留，且旧数据默认为空', () {
    final doc = DrawingDocument(id: 'd', title: '画');
    doc.folder = '工作/项目A';
    final json = doc.toJson();
    expect(json['folder'], '工作/项目A');

    final restored = DrawingDocument.fromJson(json);
    expect(restored.folder, '工作/项目A');

    // 缺少 folder 的旧文档 -> 默认根目录
    final legacy = DrawingDocument.fromJson({'id': 'x', 'title': '旧'});
    expect(legacy.folder, '');
  });

  test('DocumentMeta 文件夹字段默认根目录，可指定', () {
    expect(meta(id: 'a', title: 't').folder, '');
    expect(meta(id: 'b', title: 't', folder: '嵌套/目录').folder, '嵌套/目录');
  });
}
