// notes — Domain 层：笔记本仓储接口（零外部依赖）
// 遵循 Clean Architecture：Domain 层定义抽象契约，实现由 Infrastructure 层提供
//
// 此接口继承 core/storage 的共享 NotebookRepository，
// 添加笔记模块特有的页面级操作

import '../../../../core/storage/repository.dart';
import '../notebook.dart';

/// 笔记仓储接口（页面级操作）—— notes 模块特有
///
/// 继承 core/storage 的 NotebookRepository（基础 CRUD）
/// 添加页面级操作（用于导出、搜索等场景）
abstract class NoteRepository extends NotebookRepository {
  /// 读取指定笔记本的指定页面（不存在返回 null）
  Future<NotebookPage?> getPage(String notebookId, String pageId);

  /// 列出指定笔记本的所有页面
  Future<List<NotebookPage>> listPages(String notebookId);

  /// 保存指定笔记本的指定页面
  Future<String> savePage(String notebookId, NotebookPage page);
}
