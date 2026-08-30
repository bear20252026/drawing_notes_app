import 'notebook.dart';

/// 笔记本仓库抽象接口（B4）。
abstract class NotebookRepository {
  Future<String> save(Notebook notebook);
  Future<Notebook?> load(String id);
  Future<List<Notebook>> listAll();
  Future<bool> delete(String id);
}
