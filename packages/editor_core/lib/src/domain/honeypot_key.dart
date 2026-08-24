// editor_core——HoneypotKey 蜜罐密钥（安全最佳实践借鉴——2026-08-22）。
//
// 蜜罐密钥（诱饵密钥）——检测入侵尝试。
// 纯 Dart 不可变模型——可独立测试——不搞崩。
//
// 原理：放置一个"诱饵密钥"（外观与真实密钥相同但无法解密真实数据）。
// 攻击者若使用诱饵密钥尝试解密 → 解密失败 → 触发告警（检测入侵）。
class HoneypotKeyConfig {
  const HoneypotKeyConfig({
    this.enabled = true,
    this.maxDecryptAttempts = 3,
    this.alertOnAccess = true,
    this.alertThreshold = 2,
  });

  /// 是否启用蜜罐。
  final bool enabled;

  /// 触发强制告警前允许的解密尝试次数。
  final int maxDecryptAttempts;

  /// 访问诱饵密钥即告警。
  final bool alertOnAccess;

  /// 告警阈值（解密失败次数达到即告警）。
  final int alertThreshold;

  HoneypotKeyConfig copyWith({
    bool? enabled,
    int? maxDecryptAttempts,
    bool? alertOnAccess,
    int? alertThreshold,
  }) {
    return HoneypotKeyConfig(
      enabled: enabled ?? this.enabled,
      maxDecryptAttempts: maxDecryptAttempts ?? this.maxDecryptAttempts,
      alertOnAccess: alertOnAccess ?? this.alertOnAccess,
      alertThreshold: alertThreshold ?? this.alertThreshold,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HoneypotKeyConfig && enabled == other.enabled && maxDecryptAttempts == other.maxDecryptAttempts;

  @override
  int get hashCode => Object.hash(enabled, maxDecryptAttempts);
}

/// 蜜罐检测结果（不可变）。
class HoneypotAlert {
  const HoneypotAlert({
    required this.triggered,
    this.reason = '',
    this.attempts = 0,
  });

  final bool triggered;
  final String reason;
  final int attempts;

  static const HoneypotAlert none = HoneypotAlert(triggered: false, reason: 'No intrusion detected');

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HoneypotAlert && triggered == other.triggered && reason == other.reason;

  @override
  int get hashCode => Object.hash(triggered, reason);
}

/// 蜜罐密钥服务（安全最佳实践本地化——积木式纯 Dart）。
///
/// 功能：
/// - 记录解密尝试（用诱饵密钥尝试 = 入侵信号）
/// - 判断是否触发告警（尝试次数达到阈值）
/// - 蜜罐状态跟踪（active/triggered）
class HoneypotKeyService {
  const HoneypotKeyService();

  /// 记录解密尝试并判断是否触发告警。
  ///
  /// [decryptAttempts]：使用诱饵密钥的解密失败次数。
  HoneypotAlert recordDecryptAttempt(
    HoneypotKeyConfig config, {
    required int decryptAttempts,
    bool accessed = false,
  }) {
    if (!config.enabled) {
      return HoneypotAlert.none;
    }

    // 访问即告警。
    if (accessed && config.alertOnAccess) {
      return HoneypotAlert(
        triggered: true,
        reason: 'Honeypot key accessed',
        attempts: decryptAttempts,
      );
    }

    // 尝试次数达到阈值——告警。
    if (decryptAttempts >= config.alertThreshold) {
      return HoneypotAlert(
        triggered: true,
        reason: 'Decrypt attempts exceeded threshold ($config.alertThreshold)',
        attempts: decryptAttempts,
      );
    }

    return HoneypotAlert.none;
  }

  /// 判断尝试次数是否达到强制上限（拒绝服务——防暴力破解）。
  bool shouldLockOut(HoneypotKeyConfig config, int decryptAttempts) {
    return decryptAttempts >= config.maxDecryptAttempts;
  }

  /// 判断密钥是否为诱饵（外观相同但无法解密）。
  bool isHoneypot(String keyId, Set<String> honeypotKeyIds) {
    return honeypotKeyIds.contains(keyId);
  }
}
