/// PM码应用层用例 — 只依赖 Domain 层。
///
/// 实现 PM码 的业务逻辑，协调 Domain 实体和仓储接口。
///
/// 版权声明：本实现借鉴了以下开源项目的设计理念：
/// - kurpod (github.com/srv1n/kurpod) — AGPL-3.0
/// - Sanctum (github.com/Teycir/Sanctum) — 项目自定义许可
library;

import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import '../../../core/storage/encryption_service.dart';
import '../../../core/security/interfaces/pm_code_service.dart';
import '../domain/repositories/pm_code_repository.dart';

/// PM码用例 — 实现 PmCodeService 接口。
///
/// 核心机制：
/// - Slot A（真实密钥）：正常密码派生 → 解锁真实数据
/// - Slot B（胁迫密钥）：PM码派生 → 解锁伪装数据
/// - 两者独立存储、独立派生、不可相互推导
class PmCodeUseCases implements PmCodeService {
  PmCodeUseCases({
    required this.repository,
    EncryptionService? encryptionService,
  }) : _encryptionService = encryptionService ?? const EncryptionService();

  /// 仓储接口。
  final PmCodeRepository repository;

  /// 加密服务（Argon2id + HKDF-SHA256）。
  final EncryptionService _encryptionService;

  /// 格式版本。
  static const int _formatVersion = 1;

  @override
  Future<bool> isConfigured() async {
    final state = await repository.getState();
    return state.isConfigured;
  }

  @override
  Future<bool> isSlotADestroyed() async {
    final state = await repository.getState();
    return state.isSlotADestroyed;
  }

  @override
  Future<PmCodeSetupResult> setupPmCode({
    required String currentPassword,
    required String pmCode,
  }) async {
    // 长度校验
    if (pmCode.length < PmCodeService.kPmCodeMinLength) {
      return PmCodeSetupResult.tooShort;
    }

    // PM码不能与正常密码相同
    if (pmCode == currentPassword) {
      return PmCodeSetupResult.sameAsPassword;
    }

    try {
      // 为 Slot B 生成独立随机盐
      final saltB = _randomBytes(32);

      // 用 PM码 + Argon2id → HKDF 派生 Slot B 密钥链
      final (_, k2AuthB, _) = await _encryptionService.deriveKeyChain(
        password: pmCode,
        salt: saltB,
      );

      // 生成 Slot B 指纹（用于后续检测 PM码 是否正确）
      final fingerprintBytes = await k2AuthB.extractBytes();
      final fingerprint = base64Encode(fingerprintBytes);

      // 封装 Slot B 元数据
      final slotBMeta = jsonEncode({
        'v': _formatVersion,
        'salt': base64Encode(saltB),
        'fingerprint': fingerprint,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });

      // 持久化
      await repository.saveSlotB(slotBMeta);

      return PmCodeSetupResult.success;
    } on Exception catch (e) {
      debugPrint('PM码设置失败: $e');
      return PmCodeSetupResult.invalidParameters;
    }
  }

  @override
  Future<PmCodeSetupResult> changePmCode({
    required String oldPmCode,
    required String newPmCode,
  }) async {
    // 长度校验
    if (newPmCode.length < PmCodeService.kPmCodeMinLength) {
      return PmCodeSetupResult.tooShort;
    }

    // 验证旧 PM码
    final (verifyResult, _) = await verifyPmCode(pmCode: oldPmCode);
    if (verifyResult != PmCodeVerifyResult.success) {
      return PmCodeSetupResult.invalidParameters;
    }

    try {
      // 为 Slot B 生成新的独立随机盐
      final saltB = _randomBytes(32);

      // 用新 PM码 派生密钥链
      final (_, k2AuthB, _) = await _encryptionService.deriveKeyChain(
        password: newPmCode,
        salt: saltB,
      );

      // 生成新指纹
      final fingerprintBytes = await k2AuthB.extractBytes();
      final fingerprint = base64Encode(fingerprintBytes);

      // 封装新的 Slot B 元数据
      final slotBMeta = jsonEncode({
        'v': _formatVersion,
        'salt': base64Encode(saltB),
        'fingerprint': fingerprint,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });

      // 持久化（覆盖旧的 Slot B）
      await repository.saveSlotB(slotBMeta);

      return PmCodeSetupResult.success;
    } on Exception catch (e) {
      debugPrint('PM码修改失败: $e');
      return PmCodeSetupResult.invalidParameters;
    }
  }

  @override
  Future<bool> disablePmCode({required String pmCode}) async {
    // 验证 PM码
    final (verifyResult, _) = await verifyPmCode(pmCode: pmCode);
    if (verifyResult != PmCodeVerifyResult.success) {
      return false;
    }

    // 删除 Slot B
    await repository.deleteSlotB();
    return true;
  }

  @override
  Future<(PmCodeVerifyResult, (SecretKey, SecretKey, SecretKey)?)> verifyPmCode({
    required String pmCode,
  }) async {
    final slotBMetaStr = await repository.getSlotB();
    if (slotBMetaStr == null) {
      return (PmCodeVerifyResult.notConfigured, null);
    }

    try {
      final meta = jsonDecode(slotBMetaStr) as Map<String, dynamic>;
      final saltB = base64Decode(meta['salt'] as String);
      final storedFingerprint = meta['fingerprint'] as String;

      // 用 PM码 + Argon2id → HKDF 派生密钥链
      final keyChain = await _encryptionService.deriveKeyChain(
        password: pmCode,
        salt: saltB,
      );

      // 验证指纹（K2(auth) 派生）
      final fingerprintBytes = await keyChain.$2.extractBytes();
      final computedFingerprint = base64Encode(fingerprintBytes);

      if (computedFingerprint != storedFingerprint) {
        return (PmCodeVerifyResult.wrongPassword, null);
      }

      return (PmCodeVerifyResult.success, keyChain);
    } on Exception catch (e) {
      debugPrint('PM码验证失败: $e');
      return (PmCodeVerifyResult.corrupted, null);
    }
  }

  @override
  Future<bool> destroyRealKey({required String pmCode}) async {
    // 验证 PM码
    final (verifyResult, _) = await verifyPmCode(pmCode: pmCode);
    if (verifyResult != PmCodeVerifyResult.success) {
      return false;
    }

    try {
      // 1. 生成 32 字节密码学安全随机覆盖数据
      final random = Random.secure();
      final overwriteBytes = List<int>.generate(32, (_) => random.nextInt(256));
      final overwriteData = base64Encode(overwriteBytes);

      // 2. 覆盖 Slot A（写入随机数据 + 版本标记）
      final destroyPayload = jsonEncode({
        'v': -1, // 特殊版本号 = 已销毁
        'destroyed': true,
        'overwrite': overwriteData,
        'destroyedAt': DateTime.now().millisecondsSinceEpoch,
      });

      await repository.overwriteSlotA(destroyPayload);

      // 3. 强制刷盘（fsync）
      await repository.fsync();

      debugPrint('Slot A 已安全销毁（覆盖 + fsync）');
      return true;
    } on Exception catch (e) {
      debugPrint('销毁 Slot A 失败: $e');
      return false;
    }
  }

  /// 生成密码学安全随机字节。
  static List<int> _randomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }
}
