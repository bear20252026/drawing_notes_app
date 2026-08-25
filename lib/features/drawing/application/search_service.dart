import '../../../core/notes_accessor.dart';
import '../../notes/domain/notebook.dart' show Notebook, NotebookPage;
import '../../../core/storage/repository.dart';
import '../../../core/storage/storage_service.dart';

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
  SearchService({INotebookAccessor? notebookAccessor, StorageService? docStorage})
    : _notebookAccessor = notebookAccessor ?? _DefaultNotebookAccessor(),
      _docStorage = docStorage ?? StorageService();

  final INotebookAccessor _notebookAccessor;
  final StorageService _docStorage;

  /// 搜索 [query]，忽略大小写；命中文字块内容或标题。
  Future<List<SearchResult>> search(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];

    final results = <SearchResult>[];
    // 1) 笔记本：搜索页面标题与文字块内容。
    final notebooks = await _notebookAccessor.listNotebooks();
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
      // 搜索增强（2026-08-16）：脱敏摘要匹配——加密笔记本可搜摘要
      // （标题 + 文本前 200 字符——明文脱敏——未解锁也可搜，安全；
      // 51CTO titlePreview/掘金"核心正文加密+必要摘要脱敏"权威模式）。
      else if (nb.searchSummary.toLowerCase().contains(q)) {
        final idx = nb.searchSummary.toLowerCase().indexOf(q);
        results.add(
          SearchResult(
            kind: 'notebook',
            notebookId: nb.id,
            pageId: null,
            title: nb.title,
            snippet: _snippet(nb.searchSummary, idx, q.length),
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

/// 无注入时的默认实现（空访问器）：不依赖 notes 具体类，保持 drawing
/// 完全隔离（S4b）。正式装配由 app 层注入真实实现（NotebookAccessorImpl）。
class _DefaultNotebookAccessor implements INotebookAccessor {
  @override
  bool get isStorageAvailable => false;

  @override
  Future<List<Notebook>> listNotebooks() async => const [];

  @override
  NotebookPage? pageById(String notebookId, String pageId) => null;

  @override
  Future<String> storeImage(String sourcePath, String pageId) async =>
      throw UnimplementedError('未注入笔记存储，图片保存不可用');
}
