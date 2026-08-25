// editor_core——KeyRotationService 密钥轮换（后量子迁移指南借鉴——2026-08-22）。
//
// 密钥轮换策略（定期轮换 KEK——限制密钥寿命——后量子 Day Zero 防护）。
// 纯 Dart 不可变模型——可独立测试——不搞崩。
//
// 参考：后量子迁移指南（2026-04）——限制 KEK 寿命 + 轮换历史；
// zeph-common ChainKeyRing——epoch 轮换 + verify_chained_prefix。
library;

/// 密钥轮换策略（不可变）。
class KeyRotationPolicy {
  const KeyRotationPolicy({
    this.rotationInterval = const Duration(days: 90),
    this.maxKeyAge = const Duration(days: 180),
    this.forceRotationOnCompromise = true,
    this.maxPreviousKeys = 2,
    this.enabled = true,
  });

  /// 轮换周期（定期轮换——默认 90 天）。
  final Duration rotationInterval;

  /// 密钥最大寿命（超过强制轮换——默认 180 天）。
  final Duration maxKeyAge;

  /// 泄露时是否强制轮换。
  final bool forceRotationOnCompromise;

  /// 保留的旧密钥数（解密历史数据——默认 2 个）。
  final int maxPreviousKeys;

  /// 是否启用轮换。
  final bool enabled;

  KeyRotationPolicy copyWith({
    Duration? rotationInterval,
    Duration? maxKeyAge,
    bool? forceRotationOnCompromise,
    int? maxPreviousKeys,
    bool? enabled,
  }) {
    return KeyRotationPolicy(
      rotationInterval: rotationInterval ?? this.rotationInterval,
      maxKeyAge: maxKeyAge ?? this.maxKeyAge,
      forceRotationOnCompromise: forceRotationOnCompromise ?? this.forceRotationOnCompromise,
      maxPreviousKeys: maxPreviousKeys ?? this.maxPreviousKeys,
      enabled: enabled ?? this.enabled,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KeyRotationPolicy && rotationInterval == other.rotationInterval && enabled == other.enabled;

  @override
  int get hashCode => Object.hash(rotationInterval, enabled);
}

/// 密钥轮换结果（不可变）。
class RotationResult {
  const RotationResult({
    required this.rotated,
    required this.reason,
    this.newKeyId = '',
  });

  final bool rotated;
  final String reason;
  final String newKeyId;

  static const RotationResult notNeeded = RotationResult(rotated: false, reason: 'Within policy');

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RotationResult && rotated == other.rotated && reason == other.reason;

  @override
  int get hashCode => Object.hash(rotated, reason);
}

/// 密钥轮换服务（后量子迁移借鉴——积木式纯 Dart）。
///
/// 功能：
/// - 判断是否需要轮换（轮换周期/最大寿命/泄露）
/// - 轮换决策（返回新密钥 ID + 原因）
/// - 保留旧密钥（解密历史数据）
class KeyRotationService {
  const KeyRotationService();

  /// 判断是否应轮换（基于密钥创建时间 + 策略——后量子迁移推荐）。
  RotationResult shouldRotate({
    required DateTime keyCreatedAt,
    required KeyRotationPolicy policy,
    DateTime? now,
    bool compromised = false,
    String currentKeyId = '',
  }) {
    if (!policy.enabled) {
      return const RotationResult(rotated: false, reason: 'Rotation disabled');
    }

    final currentTime = now ?? DateTime.now();

    // 泄露——强制轮换（最高优先级）。
    if (compromised && policy.forceRotationOnCompromise) {
      return RotationResult(
        rotated: true,
        reason: 'Key compromised — forced rotation',
        newKeyId: _nextKeyId(currentKeyId),
      );
    }

    // 超过最大寿命——强制轮换。
    if (currentTime.difference(keyCreatedAt) > policy.maxKeyAge) {
      return RotationResult(
        rotated: true,
        reason: 'Key age exceeded max (${policy.maxKeyAge.inDays} days)',
        newKeyId: _nextKeyId(currentKeyId),
      );
    }

    // 达到轮换周期——定期轮换。
    if (currentTime.difference(keyCreatedAt) > policy.rotationInterval) {
      return RotationResult(
        rotated: true,
        reason: 'Rotation interval reached (${policy.rotationInterval.inDays} days)',
        newKeyId: _nextKeyId(currentKeyId),
      );
    }

    return RotationResult.notNeeded;
  }

  /// 生成下一个密钥 ID（版本递增——key-1 → key-2）。
  String _nextKeyId(String currentKeyId) {
    if (currentKeyId.isEmpty) return 'key-1';
    final parts = currentKeyId.split('-');
    if (parts.length >= 2) {
      final version = int.tryParse(parts.last) ?? 0;
      return '${parts.sublist(0, parts.length - 1).join('-')}-${version + 1}';
    }
    return '$currentKeyId-1';
  }
}
