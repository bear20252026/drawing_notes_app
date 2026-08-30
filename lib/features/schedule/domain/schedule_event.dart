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
