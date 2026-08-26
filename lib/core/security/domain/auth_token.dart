/// 认证令牌领域模型 — 零外部依赖。
///
/// 代表认证会话的核心状态信息。
library;

/// 认证令牌。
class AuthToken {
  const AuthToken({
    required this.createdAt,
    this.expiresAt,
    this.sessionId,
  });

  /// 令牌创建时间（毫秒时间戳）。
  final int createdAt;

  /// 令牌过期时间（毫秒时间戳，可选）。
  final int? expiresAt;

  /// 会话 ID（可选，用于跨设备识别）。
  final String? sessionId;

  /// 令牌是否已过期。
  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().millisecondsSinceEpoch > expiresAt!;
  }

  /// 令牌是否有效（未过期）。
  bool get isValid => !isExpired;

  /// 创建一个新的令牌（刷新）。
  AuthToken refresh({int? ttlMs}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return AuthToken(
      createdAt: now,
      expiresAt: ttlMs != null ? now + ttlMs : expiresAt,
      sessionId: sessionId,
    );
  }

  @override
  String toString() =>
      'AuthToken(created: $createdAt, expires: $expiresAt, session: $sessionId)';
}
