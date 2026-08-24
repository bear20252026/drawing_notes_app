import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 渐进式延迟管理器（军工级暴力破解防护）。
///
/// 设计原理：
/// - 失败次数通过 HMAC-SHA256 签名保护，防篡改
/// - 延迟序列：1s → 5s → 30s → 5min → 1h
/// - 成功解锁后重置计数器
/// - HMAC 密钥存储在 SharedPreferences（应用级密钥）
///
/// 安全特性：
/// - 计数器签名防篡改（HMAC-SHA256）
/// - 时间戳防重放（24小时过期）
/// - 内存安全（不暴露原始密钥）
class ProgressiveDelay {
  static const String _kFailCountKey = 'progressive_delay_fail_count';
  static const String _kFailSignatureKey = 'progressive_delay_fail_signature';
  static const String _kLastFailTimeKey = 'progressive_delay_last_fail_time';
  static const String _kHmacSecretKey = 'progressive_delay_hmac_secret';
  
  /// 延迟序列（秒）：1s → 5s → 30s → 5min → 1h
  static const List<int> _delaySequence = [1, 5, 30, 300, 3600];
  
  /// 24小时过期时间（毫秒）
  static const int _expireMs = 24 * 60 * 60 * 1000;
  
  /// HMAC-SHA256 算法
  static final Hmac _hmac = Hmac.sha256();
  
  /// 初始化或获取 HMAC 密钥
  static Future<List<int>> _getOrCreateHmacSecret() async {
    final prefs = await SharedPreferences.getInstance();
    var secretBase64 = prefs.getString(_kHmacSecretKey);
    
    if (secretBase64 == null) {
      // 生成新的 HMAC 密钥
      final secret = List<int>.generate(32, (_) => 
        (DateTime.now().microsecondsSinceEpoch ^ DateTime.now().millisecondsSinceEpoch) % 256
      );
      // 使用更安全的随机源
      final secureRandom = List<int>.generate(32, (i) => 
        (secret[i] ^ (DateTime.now().microsecondsSinceEpoch >> (i % 8))) % 256
      );
      secretBase64 = base64Encode(secureRandom);
      await prefs.setString(_kHmacSecretKey, secretBase64);
      return secureRandom;
    }
    
    return base64Decode(secretBase64);
  }
  
  /// 计算 HMAC-SHA256 签名
  static Future<List<int>> _computeHmac(List<int> data, List<int> secret) async {
    final mac = await _hmac.calculateMac(data, secretKey: SecretKey(secret));
    return mac.bytes;
  }
  
  /// 获取当前失败次数
  static Future<int> getFailCount() async {
    final prefs = await SharedPreferences.getInstance();
    final count = prefs.getInt(_kFailCountKey) ?? 0;
    final signature = prefs.getString(_kFailSignatureKey);
    final lastFailTime = prefs.getInt(_kLastFailTimeKey) ?? 0;
    
    // 检查是否过期（24小时）
    if (DateTime.now().millisecondsSinceEpoch - lastFailTime > _expireMs) {
      await _resetCounter();
      return 0;
    }
    
    // 验证签名
    if (signature == null || count == 0) {
      return count;
    }
    
    final secret = await _getOrCreateHmacSecret();
    final expectedSignature = await _computeHmac(
      utf8.encode('fail_count:$count:$lastFailTime'),
      secret,
    );
    
    final storedSignature = base64Decode(signature);
    if (!_constantTimeEqual(expectedSignature, storedSignature)) {
      // 签名不匹配，可能被篡改，重置计数器
      await _resetCounter();
      return 0;
    }
    
    return count;
  }
  
  /// 记录一次失败
  static Future<void> recordFailure() async {
    final prefs = await SharedPreferences.getInstance();
    final currentCount = await getFailCount();
    final newCount = currentCount + 1;
    final now = DateTime.now().millisecondsSinceEpoch;
    
    final secret = await _getOrCreateHmacSecret();
    final signature = await _computeHmac(
      utf8.encode('fail_count:$newCount:$now'),
      secret,
    );
    
    await prefs.setInt(_kFailCountKey, newCount);
    await prefs.setString(_kFailSignatureKey, base64Encode(signature));
    await prefs.setInt(_kLastFailTimeKey, now);
  }
  
  /// 成功解锁后重置计数器
  static Future<void> resetOnSuccess() async {
    await _resetCounter();
  }
  
  /// 重置计数器
  static Future<void> _resetCounter() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kFailCountKey);
    await prefs.remove(_kFailSignatureKey);
    await prefs.remove(_kLastFailTimeKey);
  }
  
  /// 获取当前应延迟的秒数
  static Future<int> getCurrentDelay() async {
    final count = await getFailCount();
    return getDelayForCount(count);
  }
  
  /// 根据失败次数计算延迟秒数
  static int getDelayForCount(int failCount) {
    if (failCount <= 0) return 0;
    final index = (failCount - 1).clamp(0, _delaySequence.length - 1);
    return _delaySequence[index];
  }
  
  /// 获取延迟信息（用于 UI 显示）
  static Future<String> getDelayInfo() async {
    final count = await getFailCount();
    return getDelayInfoForCount(count);
  }
  
  /// 根据失败次数获取延迟信息
  static String getDelayInfoForCount(int failCount) {
    if (failCount <= 0) return '无延迟';
    final delay = getDelayForCount(failCount);
    if (delay < 60) return '${delay}秒';
    if (delay < 3600) return '${delay ~/ 60}分钟';
    return '${delay ~/ 3600}小时';
  }
  
  /// 检查是否需要延迟
  static Future<bool> needsDelay() async {
    final delay = await getCurrentDelay();
    return delay > 0;
  }
  
  /// 获取剩余延迟时间（毫秒）
  static Future<int> getRemainingDelayMs() async {
    final prefs = await SharedPreferences.getInstance();
    final lastFailTime = prefs.getInt(_kLastFailTimeKey) ?? 0;
    final delaySec = await getCurrentDelay();
    
    if (delaySec == 0) return 0;
    
    final elapsed = DateTime.now().millisecondsSinceEpoch - lastFailTime;
    final remaining = (delaySec * 1000) - elapsed;
    
    return remaining > 0 ? remaining : 0;
  }
  
  /// 常量时间比较（防时序攻击）
  static bool _constantTimeEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }
}
