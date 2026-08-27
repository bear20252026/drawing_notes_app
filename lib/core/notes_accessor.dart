// 跨功能笔记访问契约。
//
// drawing 侧只需要两类能力：读取可搜索的摘要文本，以及把编辑器选取的图片
// 写入笔记页资产区。它不应持有可变的笔记聚合根；具体领域实体由 notes
// 基础设施投影为下列只读 DTO 后再跨功能传递。

/// 可搜索笔记本的只读索引条目。
class NotebookSearchDocument {
  NotebookSearchDocument({
    required this.id,
    required this.title,
    required this.searchSummary,
    required List<NotebookSearchPage> pages,
  }) : pages = List.unmodifiable(pages);

  final String id;
  final String title;

  /// 加密笔记本可安全保留的脱敏搜索摘要。
  final String searchSummary;
  final List<NotebookSearchPage> pages;
}

/// 笔记页面的只读搜索内容。
class NotebookSearchPage {
  NotebookSearchPage({
    required this.id,
    required this.title,
    required List<String> textContents,
  }) : textContents = List.unmodifiable(textContents);

  final String id;
  final String title;
  final List<String> textContents;
}

/// drawing 全文搜索所需的最小只读笔记索引。
abstract interface class INotebookSearchAccessor {
  /// 列出可被跨笔记搜索消费的只读摘要和页面文本。
  Future<List<NotebookSearchDocument>> listSearchDocuments();

  /// 当前笔记存储是否可用。
  bool get isStorageAvailable;
}

/// 编辑器向笔记页导入图片时所需的最小媒体写入能力。
abstract interface class INotebookMediaStore {
  /// 将图片复制进笔记页存储并返回笔记侧托管后的文件路径。
  Future<String> storeImage(String sourcePath, String pageId);
}

/// 保持既有装配点的组合契约。
///
/// notes 侧实现该接口；drawing 中不同的消费者应依赖各自更窄的父接口，
/// 而不是依赖完整聚合根或不需要的写入能力。
abstract interface class INotebookAccessor
    implements INotebookSearchAccessor, INotebookMediaStore {}
