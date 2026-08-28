import 'package:drawing_notes_app/core/storage/repository.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';

/// 「文件夹 + 文件」树 —— 让画板和笔记在同一个文件夹里混排。
///
/// 目录由条目的 `folder` 路径（如 `工作/项目A`）推导而来：路径按 `/` 切分出
/// 层级，每个层级是一个可展开的文件夹节点，其下既有画板条目也有笔记页条目。
/// 空路径（''）表示根目录。
///
/// 纯数据模型 + 构建器，不依赖外层 feature，供 home 展示层渲染。
enum FolderItemKind { canvas, note }

class FolderItem {
  const FolderItem({
    required this.title,
    required this.kind,
    required this.updatedAt,
    this.drawingId,
    this.notebookId,
    this.pageId,
  });

  final String title;
  final FolderItemKind kind;
  final DateTime updatedAt;

  /// 画板条目 -> 文档 id。
  final String? drawingId;

  /// 笔记页条目 -> 所属笔记本 id。
  final String? notebookId;

  /// 笔记页条目 -> 页面 id。
  final String? pageId;
}

class FolderNode {
  FolderNode({required this.name, required this.path});

  /// 当前目录名（最后一个路径段；根目录为 ''）。
  final String name;

  /// 完整路径（如 `工作/项目A`；根目录为 ''）。
  final String path;

  final List<FolderNode> children = <FolderNode>[];
  final List<FolderItem> items = <FolderItem>[];

  bool get isRoot => path.isEmpty;
}

class FolderTree {
  FolderTree(this.root);

  final FolderNode root;

  /// 从文档列表 + 笔记本列表构建一棵统一目录。
  static FolderTree build({
    required List<DocumentMeta> docs,
    required List<Notebook> notebooks,
  }) {
    final root = FolderNode(name: '', path: '');
    final tree = FolderTree(root);

    for (final d in docs) {
      tree._insert(
        _segments(d.folder),
        FolderItem(
          title: d.title,
          kind: FolderItemKind.canvas,
          drawingId: d.id,
          updatedAt: d.updatedAt,
        ),
      );
    }
    for (final nb in notebooks) {
      for (final p in nb.pages) {
        tree._insert(
          _segments(p.folder),
          FolderItem(
            title: p.title,
            kind: FolderItemKind.note,
            notebookId: nb.id,
            pageId: p.id,
            updatedAt: p.updatedAt,
          ),
        );
      }
    }
    tree._sort(root);
    return tree;
  }

  void _sort(FolderNode node) {
    node.children.sort((a, b) => a.name.compareTo(b.name));
    node.items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    for (final c in node.children) {
      _sort(c);
    }
  }

  void _insert(List<String> segments, FolderItem item) {
    var node = root;
    var cur = '';
    for (final seg in segments) {
      cur = cur.isEmpty ? seg : '$cur/$seg';
      var child = _findChild(node, seg);
      if (child == null) {
        child = FolderNode(name: seg, path: cur);
        node.children.add(child);
      }
      node = child;
    }
    node.items.add(item);
  }

  FolderNode? _findChild(FolderNode node, String name) {
    for (final c in node.children) {
      if (c.name == name) return c;
    }
    return null;
  }

  static List<String> _segments(String path) => path.isEmpty
      ? const <String>[]
      : path.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty).toList();
}
