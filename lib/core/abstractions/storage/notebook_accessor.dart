/// 跨功能笔记访问接口 — 零外部依赖。
///
/// 背景：drawing 模块的 editor_exporter/search_service 需要笔记能力（导出
/// 混合 PDF、跨笔记搜索）。直接 import notes 具体类破坏"完全隔离"。
///
/// 本接口作为**跨功能契约**：
/// - 定义 drawing 侧所需的笔记能力（访问页面/存储）；
/// - notes 侧实现本接口并注入（构造注入，官方推荐）；
/// - drawing 侧只依赖本接口（core 允许依赖 domain 实体，依赖向内）。
library;

/// 跨功能笔记访问接口。
abstract interface class INotebookAccessor {
  /// 读取指定笔记本页面（导出混合 PDF 时使用）。
  dynamic pageById(String notebookId, String pageId);

  /// 列出全部笔记本（跨笔记搜索时使用）。
  Future<List<dynamic>> listNotebooks();

  /// 当前笔记存储是否可用（搜索/编辑器集成时使用）。
  bool get isStorageAvailable;

  /// 将图片复制进笔记页存储（编辑器插入笔记页图片时使用），
  /// 返回笔记侧存储后的文件路径。
  Future<String> storeImage(String sourcePath, String pageId);
}
