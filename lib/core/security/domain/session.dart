/// 会话领域模型 — 零外部依赖。
///
/// 代表应用会话的状态信息。
library;

/// 会话状态。
enum SessionStatus {
  /// 活跃状态。
  active,

  /// 已锁定（需要重新认证）。
  locked,

  /// 已过期（超时）。
  expired,

  /// 已终止。
  terminated,
}

/// 会话信息。
class SessionInfo {
  const SessionInfo({
    required this.status,
    required this.createdAt,
    this.lastActiveAt,
    this.lockedAt,
    this.expiresAt,
  });

  /// 当前状态。
  final SessionStatus status;

  /// 会话创建时间（毫秒时间戳）。
  final int createdAt;

  /// 最后活跃时间（毫秒时间戳）。
  final int? lastActiveAt;

  /// 锁定时间（毫秒时间戳）。
  final int? lockedAt;

  /// 过期时间（毫秒时间戳）。
  final int? expiresAt;

  /// 会话是否活跃。
  bool get isActive => status == SessionStatus.active;

  /// 会话是否已锁定。
  bool get isLocked => status == SessionStatus.locked;

  /// 会话是否已过期。
  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().millisecondsSinceEpoch > expiresAt!;
  }

  /// 空闲时长（毫秒）。
  int? get idleDurationMs {
    if (lastActiveAt == null) return null;
    return DateTime.now().millisecondsSinceEpoch - lastActiveAt!;
  }

  /// 复制并修改状态。
  SessionInfo copyWith({
    SessionStatus? status,
    int? createdAt,
    int? lastActiveAt,
    int? lockedAt,
    int? expiresAt,
  }) {
    return SessionInfo(
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
      lockedAt: lockedAt ?? this.lockedAt,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }

  @override
  String toString() =>
      'SessionInfo(status: $status, created: $createdAt, lastActive: $lastActiveAt)';
}
