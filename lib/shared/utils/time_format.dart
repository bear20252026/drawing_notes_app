// ============================================================================
// time_format.dart —— 展示层时间格式化（去重收敛 2026-09-07）
// ============================================================================
//
// 此前「HH:mm / yyyy-MM-dd」的手写拼接（padLeft 逐段拼）散落在首页、
// 笔记本、文档页、编辑器、日程等多个展示位，其中两份私有 _formatTime
// 逐字节相同。收敛为唯一实现，展示位一律 import 调用。
//
// 边界：仅服务**展示层**。存储侧的 dayKey（如 schedule_page 的
// _dayKey、同步元数据的日期键）有各自稳定的编码契约，不在此列，
// 保持各自实现，避免存储格式隐式耦合 UI 工具。

/// 本地时钟 `HH:mm`（时/分两位补零）。
///
/// 用于「今天」语境下的紧凑时间读数（保存状态栏、更新时间等）。
String formatClock(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// 短日期 `yyyy-MM-dd`（月/日两位补零）。
String formatShortDate(DateTime t) =>
    '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

/// 智能时间：与当前时刻同年同月同日显示 `HH:mm`，否则 `yyyy-MM-dd`。
///
/// 对应原首页 Tab 与笔记本版本历史的 _formatTime 语义（列表里今天
/// 的条目给钟点，更早的给日期）。
String formatSmartTime(DateTime t) {
  final now = DateTime.now();
  if (t.year == now.year && t.month == now.month && t.day == now.day) {
    return formatClock(t);
  }
  return formatShortDate(t);
}
