/// 笔记本仓库抽象接口 — 零外部依赖。
///
/// 定义笔记本存储的契约，由 infrastructure/storage/ 实现。
library;

/// 笔记本仓库抽象接口。
abstract class NotebookRepository {
  Future<String> save(dynamic notebook);
  Future<dynamic?> load(String id);
  Future<List<dynamic>> listAll();
  Future<bool> delete(String id);
}
