import 'package:drawing_notes_app/core/notes_accessor.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/notebook_storage.dart';

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
  Future<List<NotebookSearchDocument>> listSearchDocuments() =>
      _storage.listSearchDocuments();

  @override
  Future<String> storeImage(String sourcePath, String pageId) =>
      _storage.storeImage(sourcePath, pageId);
}
