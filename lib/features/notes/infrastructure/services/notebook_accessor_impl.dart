import '../../../core/notes_accessor.dart';
import '../../domain/notebook.dart';
import 'notebook_storage.dart';

/// [INotebookAccessor] 的笔记侧实现（S4b 接口化落地）。
///
/// 依赖注入组装：app 装配点创建本实现并注入 drawing 侧消费方
/// （SearchService 等），drawing 只依赖 core 接口，不知本类存在。
class NotebookAccessorImpl implements INotebookAccessor {
  NotebookAccessorImpl({NotebookStorage? storage})
      : _storage = storage ?? NotebookStorage();

  final NotebookStorage _storage;

  @override
  bool get isStorageAvailable => true;

  @override
  Future<List<Notebook>> listNotebooks() => _storage.listAll();

  @override
  NotebookPage? pageById(String notebookId, String pageId) {
    // 页面级读取当前由 editor_exporter 的 pageProvider 函数注入承担；
    // 此处按 id 返回占位（跨笔记搜索不需要页面级，见 IMPROVEMENT_PLAN）。
    return null;
  }

  @override
  Future<String> storeImage(String sourcePath, String pageId) =>
      _storage.storeImage(sourcePath, pageId);
}
