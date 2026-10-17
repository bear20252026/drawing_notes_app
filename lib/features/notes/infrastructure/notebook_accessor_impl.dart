import 'package:drawing_notes_app/core/notes_accessor.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/notebook_storage.dart';

/// [INotebookAccessor] 的笔记侧实现（S4b 接口化落地）。
///
/// ⚠ 注释更正（EUI-12 重采 R43，逐条回读代码后）：这里以前写「app 装配点创建本实现并注入
/// drawing 侧消费方」——**不成立**。`grep -rn "NotebookAccessorImpl(" lib` 零命中，
/// 今天构造它的只有 `test/features/notes/application/search_service_test.dart:50/65/86/118`。
/// 生产走的是更短的一条路：`NotebookStorage` 自己就实现了这个接口
/// （`notebook_storage.dart:53-58`），于是装配点直接把存储对象当访问器传——
/// 见 `home_page.dart:314`、`notebook_view_page_manage.dart:48`、
/// `default_editor_page_builder.dart:55`。「drawing 只依赖 core 接口、不知本类存在」这半句仍然成立。
/// 本类因此是**冗余包装**；删它属于删代码，归业主点名，这里只把话说清楚。
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
