import '../storage/notebook_storage.dart';
import '../storage/repository.dart';
import '../storage/storage_service.dart';

/// 搜索命中结果（借鉴 Joplin / nb 的全文搜索）。
class SearchResult {
  const SearchResult({
    required this.kind, // 'notebook' | 'drawing'
    required this.notebookId,
    required this.pageId,
    required this.title,
    required this.snippet,
    this.drawingMeta,
  });

  final String kind;
  final String? notebookId;
  final String? pageId;
  final String title;
  final String snippet;
  final DocumentMeta? drawingMeta;
}

/// 全文搜索服务：扫描所有笔记本的文字块内容与画作标题。
///
/// 纯本地扫描（listAll 读取全部工程文件），无需索引文件；
/// 规模增长后可换 SQLite 索引（见学习报告 C1 备注）。
class SearchService {
  SearchService({NotebookStorage? notebookStorage, StorageService? docStorage})
    : _notebookStorage = notebookStorage ?? NotebookStorage(),
      _docStorage = docStorage ?? StorageService();

  final NotebookStorage _notebookStorage;
  final StorageService _docStorage;

  /// 搜索 [query]，忽略大小写；命中文字块内容或标题。
  Future<List<SearchResult>> search(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];

    final results = <SearchResult>[];
    // 1) 笔记本：搜索页面标题与文字块内容。
    final notebooks = await _notebookStorage.listAll();
    for (final nb in notebooks) {
      if (nb.title.toLowerCase().contains(q)) {
        results.add(
          SearchResult(
            kind: 'notebook',
            notebookId: nb.id,
            pageId: null,
            title: nb.title,
            snippet: '笔记本',
          ),
        );
      }
      for (final page in nb.pages) {
        if (page.title.toLowerCase().contains(q)) {
          results.add(
            SearchResult(
              kind: 'notebook',
              notebookId: nb.id,
              pageId: page.id,
              title: '${nb.title} / ${page.title}',
              snippet: '页面标题',
            ),
          );
        }
        for (final t in page.textItems) {
          final idx = t.text.toLowerCase().indexOf(q);
          if (idx >= 0) {
            results.add(
              SearchResult(
                kind: 'notebook',
                notebookId: nb.id,
                pageId: page.id,
                title: '${nb.title} / ${page.title}',
                snippet: _snippet(t.text, idx, q.length),
              ),
            );
          }
        }
      }
    }

    // 2) 独立画作：搜索标题。
    final metas = await _docStorage.listDocuments();
    for (final m in metas) {
      if (m.title.toLowerCase().contains(q)) {
        results.add(
          SearchResult(
            kind: 'drawing',
            notebookId: null,
            pageId: null,
            title: m.title,
            snippet: '画作',
            drawingMeta: m,
          ),
        );
      }
    }
    return results;
  }

  /// 截取命中位置前后的文字片段。
  static String _snippet(String text, int start, int len) {
    final s = start > 12 ? start - 12 : 0;
    final e = start + len + 18 < text.length ? start + len + 18 : text.length;
    final prefix = s > 0 ? '…' : '';
    final suffix = e < text.length ? '…' : '';
    return '$prefix${text.substring(s, e)}$suffix';
  }
}
