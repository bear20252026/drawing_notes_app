// editor_core——GcmSivSelector（SAFE 2026 草案借鉴——2026-08-22）。
//
// AES-256-GCM-SIV（RFC 8452——NMR 抗 nonce 误用）选择器本地化。
// 纯 Dart 不可变模型——可独立测试——不搞崩。
//
// SAFE 2026 草案：AES-256-GCM-SIV 是 NMR（nonce-misuse resistant）AEAD——
// nonce 复用不泄露明文（降级为确定性加密）——比 GCM 更稳。
library;

/// GCM-SIV 配置（SAFE 2026 本地化——不可变）。
class GcmSivConfig {
  const GcmSivConfig({
    this.preferSiv = true,
    this.nonceReuseDetection = true,
    this.fallbackToGcm = false,
    this.maxNonceUses = 1000000, // 每密钥 nonce 使用上限（GCM 安全边界）。
  });

  /// 是否优先使用 GCM-SIV（NMR——抗 nonce 误用）。
  final bool preferSiv;

  /// 是否检测 nonce 复用（计数器跟踪）。
  final bool nonceReuseDetection;

  /// nonce 耗尽后是否回退 GCM（不安全——建议轮换密钥而非回退）。
  final bool fallbackToGcm;

  /// 每密钥 nonce 使用上限（GCM 在 2^32 次后不安全——保守用 100 万）。
  final int maxNonceUses;

  GcmSivConfig copyWith({
    bool? preferSiv,
    bool? nonceReuseDetection,
    bool? fallbackToGcm,
    int? maxNonceUses,
  }) {
    return GcmSivConfig(
      preferSiv: preferSiv ?? this.preferSiv,
      nonceReuseDetection: nonceReuseDetection ?? this.nonceReuseDetection,
      fallbackToGcm: fallbackToGcm ?? this.fallbackToGcm,
      maxNonceUses: maxNonceUses ?? this.maxNonceUses,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GcmSivConfig && preferSiv == other.preferSiv && maxNonceUses == other.maxNonceUses;

  @override
  int get hashCode => Object.hash(preferSiv, maxNonceUses);
}

/// 算法选择结果（不可变）。
class AlgorithmSelection {
  const AlgorithmSelection({
    required this.algorithm,
    required this.reason,
    this.warning = '',
  });

  final String algorithm; // 'aes-256-gcm-siv' / 'aes-256-gcm'
  final String reason;
  final String warning;

  bool get usesSiv => algorithm == 'aes-256-gcm-siv';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AlgorithmSelection && algorithm == other.algorithm;

  @override
  int get hashCode => algorithm.hashCode;
}

/// GCM-SIV 选择器（SAFE 2026 本地化——积木式纯 Dart）。
///
/// 根据配置 + nonce 状态选择加密算法：
/// - 优先 GCM-SIV（NMR——抗 nonce 误用）
/// - 检测 nonce 复用（计数器——接近上限建议轮换密钥）
/// - nonce 耗尽——建议轮换密钥（不推荐回退 GCM）
class GcmSivSelector {
  const GcmSivSelector();

  /// 选择算法（根据配置 + nonce 状态——SAFE 2026 NMR 优先）。
  AlgorithmSelection select(
    GcmSivConfig config, {
    bool nonceReused = false,
    int nonceUses = 0,
  }) {
    // nonce 已复用——GCM-SIV 降级为确定性加密（安全）——
    // GCM 会泄露明文（不安全）。
    if (nonceReused && config.preferSiv) {
      return const AlgorithmSelection(
        algorithm: 'aes-256-gcm-siv',
        reason: 'Nonce reused — GCM-SIV degrades safely (deterministic)',
        warning: 'Nonce reuse detected — GCM would leak plaintext',
      );
    }

    // nonce 接近上限——建议轮换密钥。
    if (config.nonceReuseDetection && nonceUses >= config.maxNonceUses) {
      if (config.preferSiv) {
        return const AlgorithmSelection(
          algorithm: 'aes-256-gcm-siv',
          reason: 'Nonce budget exhausted — GCM-SIV (NMR) safe',
          warning: 'Rotate key — nonce budget exhausted',
        );
      }
      if (config.fallbackToGcm) {
        return const AlgorithmSelection(
          algorithm: 'aes-256-gcm',
          reason: 'Nonce budget exhausted — falling back to GCM',
          warning: 'DANGER: GCM unsafe after 2^32 nonce uses',
        );
      }
      return const AlgorithmSelection(
        algorithm: 'aes-256-gcm-siv',
        reason: 'Nonce budget exhausted — GCM-SIV (NMR) safe',
        warning: 'Rotate key recommended',
      );
    }

    // 正常情况——优先 GCM-SIV（NMR）。
    if (config.preferSiv) {
      return const AlgorithmSelection(
        algorithm: 'aes-256-gcm-siv',
        reason: 'NMR preferred (SAFE 2026)',
      );
    }

    return const AlgorithmSelection(
      algorithm: 'aes-256-gcm',
      reason: 'Legacy GCM (non-NMR)',
      warning: 'Prefer GCM-SIV (NMR) for new data',
    );
  }

  /// 是否应轮换密钥（nonce 使用接近上限）。
  bool shouldRotateKey(GcmSivConfig config, int nonceUses) {
    return config.nonceReuseDetection && nonceUses >= config.maxNonceUses;
  }

  /// 计算 nonce 使用预算剩余（百分比）。
  double nonceBudgetRemaining(GcmSivConfig config, int nonceUses) {
    if (config.maxNonceUses <= 0) return 0;
    return (1 - nonceUses / config.maxNonceUses).clamp(0.0, 1.0);
  }
}
