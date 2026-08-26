// notes — Application 层：笔记页面用例
// 遵循 Clean Architecture：Application 层只依赖 Domain 层

import '../../../core/abstractions/storage/notebook_repository.dart';
import '../domain/entities/notebook.dart';
import '../domain/value_objects/note_content.dart';
import '../domain/value_objects/notebook_id.dart';

/// 笔记页面用例（Application 层）
///
/// 封装笔记页面相关业务逻辑
/// 通过 [NotebookRepository] 接口存取数据
class NoteUseCases {
  const NoteUseCases(this._repository);

  final NotebookRepository _repository;

  /// 添加页面到笔记本
  Future<Notebook?> addPage(String notebookId, NotebookPage page) async {
    final validId = NotebookId.tryCreate(notebookId);
    if (validId == null) return null;
    final notebook = await _repository.load(validId.value);
    if (notebook == null) return null;
    notebook.pages.add(page);
    await _repository.save(notebook);
    return notebook;
  }

  /// 删除笔记本中的页面
  Future<Notebook?> removePage(String notebookId, String pageId) async {
    final validId = NotebookId.tryCreate(notebookId);
    if (validId == null) return null;
    final notebook = await _repository.load(validId.value);
    if (notebook == null) return null;
    notebook.pages.removeWhere((p) => p.id == pageId);
    await _repository.save(notebook);
    return notebook;
  }

  /// 获取笔记本的所有页面
  Future<List<NotebookPage>> getPages(String notebookId) async {
    final notebook = await findNotebook(notebookId);
    return notebook?.pages ?? [];
  }

  /// 根据 ID 查找笔记本（内部辅助）
  Future<Notebook?> findNotebook(String id) {
    final validId = NotebookId.tryCreate(id);
    if (validId == null) return Future.value(null);
    return _repository.load(validId.value);
  }

  /// 提取笔记纯文本内容（用于搜索/摘要）
  NoteContent extractContent(NotebookPage page) {
    return NoteContent(
      plainText: page.paragraphs.map((p) => p.text).join('\n'),
      attachments: page.imageItems.map((i) => i.filePath).toList(),
    );
  }
}
