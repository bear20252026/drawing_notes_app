/// 相对时间描述工具。
///
/// 用于「全部文档」工作台的次级信息列（如"刚刚 / N 小时前 / 上周"）。
///
/// 纯函数：输出仅依赖 [time] 与 [now]，无副作用、无平台调用，可直接单测。
library;

/// 返回 [time] 相对于 [now] 的简短中文相对时间描述。
///
/// 区间映射：
/// - < 1 分钟 → "刚刚"
/// - < 1 小时 → "N 分钟前"
/// - < 1 天 → "N 小时前"
/// - < 2 天 → "昨天"
/// - < 7 天 → "N 天前"
/// - < 14 天 → "上周"
/// - < 30 天 → "N 周前"
/// - < 365 天 → "N 月前"
/// - ≥ 365 天 → "N 年前"
String timeAgo(DateTime time, {DateTime? now}) {
  final DateTime now0 = now ?? DateTime.now();
  final Duration diff = now0.difference(time);

  if (diff.isNegative) {
    // 将来时间：与 now 相同处理为「刚刚」。
    return '刚刚';
  }

  final int minutes = diff.inMinutes;
  final int hours = diff.inHours;
  final int days = diff.inDays;

  if (minutes < 1) return '刚刚';
  if (hours < 1) return '$minutes 分钟前';
  if (days < 1) return '$hours 小时前';
  if (days < 2) return '昨天';
  if (days < 7) return '$days 天前';
  if (days < 14) return '上周';
  if (days < 30) {
    final weeks = (days / 7).floor();
    return '$weeks 周前';
  }
  if (days < 365) {
    final months = (days / 30).floor();
    return '$months 月前';
  }
  final years = (days / 365).floor();
  return '$years 年前';
}
