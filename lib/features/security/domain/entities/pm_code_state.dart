/// PM码领域实体 — 零外部依赖。
///
/// 代表 PM码 在领域层的核心状态。
library;

/// PM码配置状态。
class PmCodeState {
  const PmCodeState({
    required this.isConfigured,
    required this.isSlotADestroyed,
    this.createdAt,
  });

  /// PM码是否已配置。
  final bool isConfigured;

  /// Slot A（真实密钥槽）是否已被销毁。
  final bool isSlotADestroyed;

  /// PM码创建时间（毫秒时间戳）。
  final int? createdAt;

  /// 未配置状态的工厂构造函数。
  factory PmCodeState.unconfigured() => const PmCodeState(
        isConfigured: false,
        isSlotADestroyed: false,
      );

  /// 复制并修改状态。
  PmCodeState copyWith({
    bool? isConfigured,
    bool? isSlotADestroyed,
    int? createdAt,
  }) {
    return PmCodeState(
      isConfigured: isConfigured ?? this.isConfigured,
      isSlotADestroyed: isSlotADestroyed ?? this.isSlotADestroyed,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PmCodeState &&
          runtimeType == other.runtimeType &&
          isConfigured == other.isConfigured &&
          isSlotADestroyed == other.isSlotADestroyed &&
          createdAt == other.createdAt;

  @override
  int get hashCode =>
      isConfigured.hashCode ^
      isSlotADestroyed.hashCode ^
      createdAt.hashCode;

  @override
  String toString() =>
      'PmCodeState(configured: $isConfigured, destroyed: $isSlotADestroyed, '
      'createdAt: $createdAt)';
}

/// PM码操作结果。
class PmCodeOperationResult {
  const PmCodeOperationResult({
    required this.success,
    this.error,
  });

  /// 操作是否成功。
  final bool success;

  /// 错误信息（如果失败）。
  final String? error;

  /// 成功结果。
  factory PmCodeOperationResult.ok() =>
      const PmCodeOperationResult(success: true);

  /// 失败结果。
  factory PmCodeOperationResult.fail(String error) =>
      PmCodeOperationResult(success: false, error: error);
}
