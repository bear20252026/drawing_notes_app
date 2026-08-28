/// 日程条目 —— 把「某个时间点做过的事」归一成一条记录。
///
/// 它是时间线 / 日历看板共用的最小数据单位：一条可以是「一张画板」
/// 也可以是「一页笔记」，统一按发生时间（最近修改）归入某个日期。
///
/// 该模型是纯数据，不依赖任何 feature 外层，供 schedule 的展示层使用，
/// 由 app 组合层从 notebook/drawing 数据装配出来。
enum ScheduleEntryKind { drawing, note }

class ScheduleEntry {
  const ScheduleEntry({
    required this.id,
    required this.title,
    required this.kind,
    required this.at,
    this.notebookId,
    this.pageId,
  });

  /// 条目唯一 id（画板为 DocumentMeta.id，笔记页为 NotebookPage.id）。
  final String id;

  /// 标题（画板或笔记页标题）。
  final String title;

  /// 类型：画板 或 笔记页。
  final ScheduleEntryKind kind;

  /// 发生时间（最近一次修改时间），用于归入日历中的某一天。
  final DateTime at;

  /// 若为笔记页，所属笔记本 id。
  final String? notebookId;

  /// 若为笔记页，页面 id。
  final String? pageId;
}
