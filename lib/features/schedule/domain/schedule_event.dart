// M11 日历真实化：日程/待办事件领域模型。
// 纯 Dart，无 flutter/io 依赖，可单测锁定。

/// 日历上的一条「待办/日程」事件。
///
/// 与 [ScheduleEntry]（文档活动派生条目）不同：这是用户亲手创建的
/// 真实数据，持久化于本地，可勾选完成、可删除。
class ScheduleEvent {
  const ScheduleEvent({
    required this.id,
    required this.title,
    required this.dayKey,
    this.isDone = false,
    this.minuteOfDay,
    required this.createdAt,
  });

  /// 唯一标识（ULID 风格字符串，由存储层生成）。
  final String id;

  /// 事件标题（待办内容）。
  final String title;

  /// 所属日期键：`yyyy-MM-dd`（本地日期）。
  final String dayKey;

  /// 是否已完成（待办语义）。
  final bool isDone;

  /// 当天内的时刻（分钟数 0..1439，即几点几分）；null = 全天待办。
  /// M11：待办升级为可定位到小时/分钟的真日程。
  final int? minuteOfDay;

  /// 创建时间。
  final DateTime createdAt;

  /// JSON 序列化。
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'dayKey': dayKey,
    'isDone': isDone,
    if (minuteOfDay != null) 'minuteOfDay': minuteOfDay,
    'createdAt': createdAt.toIso8601String(),
  };

  /// 日期键格式（P1 修复：`_parseDayKey` 在 build 内同步 `int.parse`，
  /// 一条毒 dayKey 即红屏崩溃循环——此处格式+长度双拦截，坏行隔离丢弃）。
  static final RegExp _dayKeyFormat = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  /// JSON 反序列化；字段缺失/类型不符时返回 null（fail-open）。
  static ScheduleEvent? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final title = json['title'];
    final dayKey = json['dayKey'];
    final createdAt = json['createdAt'];
    if (id is! String ||
        title is! String ||
        dayKey is! String ||
        createdAt is! String) {
      return null;
    }
    if (id.isEmpty ||
        id.length > 128 ||
        title.length > 500 ||
        !_dayKeyFormat.hasMatch(dayKey) ||
        tryParseDayKey(dayKey) == null) {
      return null;
    }
    final parsed = DateTime.tryParse(createdAt);
    if (parsed == null) return null;
    final minuteRaw = json['minuteOfDay'];
    final minuteOfDay = minuteRaw is int ? minuteRaw : null;
    if (minuteOfDay != null && (minuteOfDay < 0 || minuteOfDay > 1439)) {
      return null;
    }
    return ScheduleEvent(
      id: id,
      title: title,
      dayKey: dayKey,
      isDone: json['isDone'] == true,
      minuteOfDay: minuteOfDay,
      createdAt: parsed,
    );
  }

  /// 复制并修改。
  ScheduleEvent copyWith({
    String? id,
    String? title,
    String? dayKey,
    bool? isDone,
    int? minuteOfDay,
    DateTime? createdAt,
  }) {
    return ScheduleEvent(
      id: id ?? this.id,
      title: title ?? this.title,
      dayKey: dayKey ?? this.dayKey,
      isDone: isDone ?? this.isDone,
      minuteOfDay: minuteOfDay ?? this.minuteOfDay,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScheduleEvent &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          title == other.title &&
          dayKey == other.dayKey &&
          isDone == other.isDone &&
          minuteOfDay == other.minuteOfDay &&
          createdAt == other.createdAt;

  @override
  int get hashCode =>
      Object.hash(id, title, dayKey, isDone, minuteOfDay, createdAt);

  @override
  String toString() =>
      'ScheduleEvent($id, $dayKey, $title, done=$isDone, minute=$minuteOfDay)';
}

/// 生成本地日期键：`yyyy-MM-dd`。
String scheduleDayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// 安全解析日期键：合法返回 DateTime，非法返回 null（永不抛异常——
/// 供 UI 层在 build 内调用，坏行隔离而非崩溃）。
DateTime? tryParseDayKey(String key) {
  final parts = key.split('-');
  if (parts.length != 3) return null;
  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final d = int.tryParse(parts[2]);
  if (y == null || m == null || d == null) return null;
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  try {
    final dt = DateTime(y, m, d);
    // DateTime 溢出归一（如 2 月 30 日变 3 月）——回校验拦截。
    if (dt.year != y || dt.month != m || dt.day != d) return null;
    return dt;
  } catch (_) {
    return null;
  }
}
