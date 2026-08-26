// notes — Application 层：笔记本用例
// 遵循 Clean Architecture：Application 层只依赖 Domain 层

import '../../../core/storage/repository.dart';
import '../domain/entities/notebook.dart';
import '../domain/value_objects/notebook_id.dart';

/// 笔记本用例（Application 层）
///
/// 封装笔记本相关业务逻辑
/// 通过 [NotebookRepository] 接口存取数据（不依赖具体实现）
class NotebookUseCases {
  const NotebookUseCases(this._repository);

  final NotebookRepository _repository;

  /// 创建新笔记本
  Future<Notebook> createNotebook({
    required String title,
    String? prefix,
  }) async {
    final id = await _repository.load('') as Future<Notebook?>;
    // 由 StorageService 生成唯一 ID（实际实现由基础设施层提供）
    final notebook = Notebook(
      id: prefix ?? 'notebook',
      title: title,
      pages: [],
    );
    await _repository.save(notebook);
    return notebook;
  }

  /// 获取所有笔记本
  Future<List<Notebook>> getAllNotebooks() => _repository.listAll();

  /// 根据 ID 查找笔记本
  Future<Notebook?> findById(String id) {
    final validId = NotebookId.tryCreate(id);
    if (validId == null) return Future.value(null);
    return _repository.load(validId.value);
  }

  /// 删除笔记本
  Future<bool> deleteNotebook(String id) {
    final validId = NotebookId.tryCreate(id);
    if (validId == null) return Future.value(false);
    return _repository.delete(validId.value);
  }

  /// 更新笔记本标题
  Future<Notebook?> updateTitle(String id, String newTitle) async {
    final notebook = await findById(id);
    if (notebook == null) return null;
    notebook.title = newTitle;
    await _repository.save(notebook);
    return notebook;
  }
}
