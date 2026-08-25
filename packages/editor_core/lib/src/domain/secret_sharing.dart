// editor_core——SecretSharing 密钥分割（EPC 2026 Rec 9 借鉴——2026-08-22）。
//
// Shamir's Secret Sharing 本地化——主密钥分成 N 份——M 份可恢复。
// 纯 Dart 不可变模型——可独立测试——不搞崩。
//
// EPC 2026 指南 Rec 9：主密钥备份应分割成密钥组件——阈值恢复。
// 参考实现：shamir_secret_plg（split/combine——totalShares/threshold）。
library;

import 'dart:math' as math;

/// 秘密份额（Shamir 密钥分割本地化——不可变）。
///
/// 每个份额 = 多项式上的一个点（x 坐标 = index，y 坐标 = value）。
/// 需要 ≥threshold 个份额才能恢复原秘密（拉格朗日插值）。
class SecretShare {
  const SecretShare({required this.index, required this.value});

  /// 份额索引（x 坐标——从 1 开始——0 保留给秘密本身）。
  final int index;

  /// 份额值（y 坐标——多项式值）。
  final List<int> value;

  SecretShare copyWith({int? index, List<int>? value}) {
    return SecretShare(index: index ?? this.index, value: value ?? this.value);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is SecretShare && index == other.index;

  @override
  int get hashCode => index.hashCode;
}

/// Shamir 密钥分割服务（EPC 2026 Rec 9 本地化——积木式纯 Dart）。
///
/// Shamir's Secret Sharing（Adi Shamir 1979）：
/// - 用有限域 GF(p) 上的 k-1 次多项式（常数项 = 秘密）
/// - 多项式上取 N 个点作为份额
/// - 任意 M ≥ k 个份额通过拉格朗日插值恢复多项式 → 常数项 = 秘密
/// - M-1 个份额无法获得任何秘密信息（信息论安全）
class SecretSharingService {
  const SecretSharingService();

  /// 有限域模数（GF(p)——Shamir 算法要求 p > 秘密和份额数）。
  ///
  /// 用质数 257（> 255——秘密字节 0-255 范围）——GF(257) 内所有运算
  /// 结果 0-256——Dart int（64 位）不溢出——安全。
  static final BigInt _prime = BigInt.from(257);

  /// 验证阈值配置（totalShares ≥ threshold ≥ 2——EPC Rec 9）。
  bool validateThreshold({required int totalShares, required int threshold}) {
    if (totalShares < 2) return false;
    if (threshold < 2) return false;
    if (threshold > totalShares) return false;
    return true;
  }

  /// 分割秘密（split——secret → totalShares 份——threshold 可恢复）。
  ///
  /// [secret] 字节数组 → 每个字节作为独立秘密分割（多项式插值）。
  List<SecretShare> split(
    List<int> secret, {
    required int totalShares,
    required int threshold,
  }) {
    if (!validateThreshold(totalShares: totalShares, threshold: threshold)) {
      throw ArgumentError('Invalid threshold config: '
          '$totalShares shares, $threshold threshold');
    }

    final rng = math.Random.secure();
    final shares = List<SecretShare>.generate(
      totalShares,
      (i) => SecretShare(index: i + 1, value: List.filled(secret.length, 0)),
    );

    // 每个字节独立进行 Shamir 分割。
    for (var byteIndex = 0; byteIndex < secret.length; byteIndex++) {
      final secretByte = BigInt.from(secret[byteIndex]);

      // 生成 k-1 个随机系数（a1..a_{k-1}）——常数项 a0 = 秘密。
      final coefficients = List<BigInt>.generate(
        threshold - 1,
        (_) => _randomInField(rng),
      );

      // 计算每个份额：f(x) = a0 + a1*x + ... + a_{k-1}*x^{k-1}。
      for (var i = 0; i < totalShares; i++) {
        final x = BigInt.from(i + 1);
        var y = secretByte;
        var xPow = x;
        for (final coeff in coefficients) {
          y = (y + coeff * xPow) % _prime;
          xPow = (xPow * x) % _prime;
        }
        shares[i].value[byteIndex] = y.toInt();
      }
    }

    return shares;
  }

  /// 合并份额（combine——≥threshold 份 → 原秘密）。
  ///
  /// 拉格朗日插值：L(0) = Σ y_j * Π_{m≠j} x_m/(x_m - x_j)。
  List<int>? combine(List<SecretShare> shares, {required int threshold}) {
    if (shares.length < threshold) return null; // 份额不足——无法恢复。
    if (shares.isEmpty) return null;

    final byteLength = shares.first.value.length;
    final secret = List<int>.filled(byteLength, 0);

    // 取前 threshold 个份额（任意子集即可——拉格朗日插值）。
    final usedShares = shares.take(threshold).toList();

    for (var byteIndex = 0; byteIndex < byteLength; byteIndex++) {
      // 拉格朗日插值在 x=0 处的值（= 常数项 = 秘密）。
      BigInt result = BigInt.zero;
      for (var j = 0; j < usedShares.length; j++) {
        final xj = BigInt.from(usedShares[j].index);
        final yj = BigInt.from(usedShares[j].value[byteIndex]);
        // 拉格朗日基多项式 L_j(0)。
        BigInt numerator = BigInt.one;
        BigInt denominator = BigInt.one;
        for (var m = 0; m < usedShares.length; m++) {
          if (m == j) continue;
          final xm = BigInt.from(usedShares[m].index);
          numerator = (numerator * xm) % _prime;          // Π x_m
          denominator = (denominator * (xm - xj)) % _prime; // Π (x_m - x_j)
        }
        // L_j(0) = numerator / denominator（模逆元）。
        final lj = numerator * _modInverse(denominator) % _prime;
        result = (result + yj * lj) % _prime;
      }
      secret[byteIndex] = result.toInt();
    }

    return secret;
  }

  /// 生成有限域内的随机数（1 ~ p-1）。
  BigInt _randomInField(math.Random rng) {
    // 简化：用随机字节生成（避免完全随机导致系数为 0）。
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    var value = BigInt.zero;
    for (final b in bytes) {
      value = (value << 8) + BigInt.from(b);
    }
    return (value % (_prime - BigInt.one)) + BigInt.one;
  }

  /// 模逆元（扩展欧几里得算法——GF(p) 除法）。
  BigInt _modInverse(BigInt a) {
    var t = BigInt.zero;
    var newT = BigInt.one;
    var r = _prime;
    var newR = a % _prime;
    while (newR != BigInt.zero) {
      final quotient = r ~/ newR;
      final tmpT = t - quotient * newT;
      t = newT;
      newT = tmpT;
      final tmpR = r - quotient * newR;
      r = newR;
      newR = tmpR;
    }
    if (r > BigInt.one) throw StateError('No inverse exists');
    if (t < BigInt.zero) t += _prime;
    return t;
  }
}
