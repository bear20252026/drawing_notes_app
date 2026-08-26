/// PM码（Panic Mode / 胁迫密码）抽象接口。
///
/// 定义 PM码 核心操作的契约，由 features/security/ 实现。
///
/// 设计参考（GitHub 开源项目）：
/// - kurpod (github.com/srv1n/kurpod) — plausible deniability 双密钥槽 — AGPL-3.0
/// - Sanctum (github.com/Teycir/Sanctum) — duress-proof 零信任金库
/// - pam_duress (github.com/rafket/pam_duress) — 胁迫码触发替代认证路径 — GPL-2.0
/// - CipherVault (github.com/vipecoder228/CipherVault) — duress code + stealth mode — MIT
/// - lenticrypt (github.com/ESultanik/lenticrypt) — 可证明的合理否认加密 — GPL-2.0
///
/// 版权声明：本接口设计借鉴了上述开源项目的设计理念，遵循各自许可证要求。
library;

import 'package:cryptography/cryptography.dart';

/// PM码验证结果。
enum PmCodeVerifyResult {
  /// PM码正确，进入伪装模式。
  success,

  /// PM码错误。
  wrongPassword,

  /// PM码未设置。
  notConfigured,

  /// 数据损坏。
  corrupted,

  /// 渐进式延迟中。
  rateLimited,
}

/// PM码设置结果。
enum PmCodeSetupResult {
  /// 设置成功。
  success,

  /// PM码与当前密码相同（不允许）。
  sameAsPassword,

  /// PM码太短。
  tooShort,

  /// 参数错误。
  invalidParameters,
}

/// PM码服务抽象接口。
///
/// 实现类必须保证：
/// - Slot A（真实密钥）与 Slot B（胁迫密钥）独立存储、独立派生
/// - 两者使用不同的随机盐，无法相互推导
/// - 销毁操作不可逆（覆盖 → fsync → 清零）
abstract class PmCodeService {
  /// PM码最小长度（与正常密码一致：6 位）。
  static const int kPmCodeMinLength = 6;

  /// 检查 PM 码是否已配置。
  Future<bool> isConfigured();

  /// 设置 PM 码。
  ///
  /// [currentPassword] — 当前正常密码（用于验证身份）。
  /// [pmCode] — 新的胁迫密码。
  ///
  /// 安全约束：
  /// - PM码 ≠ 当前密码（否则失去区分能力）
  /// - PM码 ≥ 6 位
  Future<PmCodeSetupResult> setupPmCode({
    required String currentPassword,
    required String pmCode,
  });

  /// 修改 PM 码。
  ///
  /// [oldPmCode] — 当前 PM码（验证身份）。
  /// [newPmCode] — 新的 PM码。
  Future<PmCodeSetupResult> changePmCode({
    required String oldPmCode,
    required String newPmCode,
  });

  /// 关闭 PM 码。
  ///
  /// [pmCode] — 当前 PM码（验证身份后删除）。
  ///
  /// 返回是否成功关闭。
  Future<bool> disablePmCode({required String pmCode});

  /// 验证 PM 码。
  ///
  /// [pmCode] — 用户输入的胁迫密码。
  ///
  /// 返回验证结果 + Slot B 的密钥链（如果成功）。
  Future<(PmCodeVerifyResult, (SecretKey, SecretKey, SecretKey)?)> verifyPmCode({
    required String pmCode,
  });

  /// 销毁真实密钥槽（Slot A）。
  ///
  /// 安全流程：
  /// 1. 生成 256 位（32 字节）密码学安全随机数据
  /// 2. 用该随机数据覆盖 Slot A 存储区域
  /// 3. 调用 fsync 确保数据刷入物理存储
  /// 4. 内存清零
  ///
  /// ⚠️ 警告：此操作不可逆！Slot A 的真实数据将永久丢失。
  ///
  /// [pmCode] — PM码（验证身份后执行销毁）。
  Future<bool> destroyRealKey({required String pmCode});

  /// 检查 Slot A 是否已被销毁。
  Future<bool> isSlotADestroyed();
}
