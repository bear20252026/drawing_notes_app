// 笔记本/页的只读索引源契约（C-09 解环，审计 2026-09-27）。
//
// AllDoc 统一索引（core/all_doc_query.dart）聚合画布 / 笔记本 / 块文档
// 三源；为使 core 不反向依赖 notes 领域实体（core→features 禁止），
// 笔记本侧以本只读接口满足查询输入——Notebook / NotebookPage 实现本
// 接口（纯声明，零行为变化），`List<Notebook>` 因 Dart 泛型协变可直接
// 传给 `List<NotebookIndexSource>`，调用点零改动。

/// 统一索引视角下的笔记本（只读最小面）。
abstract interface class NotebookIndexSource {
  String get id;
  String get title;

  /// 锁定占位条目（保险库锁定时的 DNV 密文分页画布）。
  bool get isLockedPlaceholder;
  DateTime get createdAt;
  DateTime get updatedAt;
  List<NotebookPageIndexSource> get pages;
}

/// 统一索引视角下的笔记本页（只读最小面）。
abstract interface class NotebookPageIndexSource {
  String get id;
  String get title;
  String get folder;
  DateTime get createdAt;
  DateTime get updatedAt;
  bool get favorite;
}
