// honeypot.dart — 蜜罐密钥部署：生成假密钥诱饵 + 入侵检测 + 审计日志。
//
// 设计：
// - 在 Vault 存储中植入假密钥文件（honeypot.dek.0 / honeypot.signing.sk 等）
// - 假密钥用与真密钥相同的格式和加密方式存储
// - 当攻击者尝试使用假密钥时，触发入侵警报
// - 所有触发事件记录到 AuditLogger（哈希链防篡改）
//
// 蜜罐触发条件：
// 1. 假密钥被读取
// 2. 假密钥被用于解密操作
// 3. 假密钥被用于签名操作

import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'audit_logger.dart';
import 'vault_key_service.dart';

/// 蜜罐配置。
class HoneypotConfig {
  const HoneypotConfig({
    this.decoyKeyCount = 3,
    this.prefix = 'honeypot.',
  });

  /// 生成假 DEK 数量。
  final int decoyKeyCount;

  /// 蜜罐密钥 ID 前缀。
  final String prefix;
}

/// 蜜罐密钥部署服务。
class HoneypotService {
  HoneypotService({
    required this.vaultStore,
    this.config = const HoneypotConfig(),
  });

  final VaultKeyStore vaultStore;
  final HoneypotConfig config;

  /// 已部署的假密钥 ID 列表。
  final List<String> _deployedIds = [];

  /// 触发次数计数。
  int _triggerCount = 0;

  /// 获取触发次数。
  int get triggerCount => _triggerCount;

  /// 获取已部署的假密钥 ID。
  List<String> get deployedIds => List.unmodifiable(_deployedIds);

  /// 部署蜜罐假密钥。
  ///
  /// 生成 [config.decoyKeyCount] 个假 DEK 和假签名密钥对，
  /// 格式与真密钥完全一致（不加密——蜜罐不需要真正的加密保护）。
  Future<void> deploy() async {
    developer.log(
      '部署蜜罐: ${config.decoyKeyCount} 个假密钥',
      name: 'HoneypotService',
    );

    final random = math.Random.secure();

    for (var i = 0; i < config.decoyKeyCount; i++) {
      // 生成假 DEK（32 字节随机）。
      final fakeDek = Uint8List.fromList(
        List.generate(32, (_) => random.nextInt(256)),
      );
      final fakeDekId = '${config.prefix}dek.$i';
      await vaultStore.storeKey(fakeDekId, fakeDek);
      _deployedIds.add(fakeDekId);

      // 生成假签名密钥对。
      final fakeKeyPair = await Ed25519().newKeyPair();
      final fakeSk = await fakeKeyPair.extractPrivateKeyBytes();
      final fakePk = await fakeKeyPair.extractPublicKey();

      final fakeSkId = '${config.prefix}signing.$i.sk';
      final fakePkId = '${config.prefix}signing.$i.pk';
      await vaultStore.storeKey(fakeSkId, fakeSk);
      await vaultStore.storeKey(fakePkId, fakePk.bytes);
      _deployedIds.add(fakeSkId);
      _deployedIds.add(fakePkId);
    }

    AuditLogger.log(
      'honeypot.deploy',
      detail: '${_deployedIds.length} 个假密钥已部署',
    );
  }

  /// 检测是否为蜜罐密钥。
  bool isHoneypotKey(String keyId) {
    return keyId.startsWith(config.prefix);
  }

  /// 蜜罐触发回调。
  ///
  /// 当检测到假密钥被访问时调用此方法。
  void onTrigger({
    required String keyId,
    required String operation,
    String? source,
  }) {
    _triggerCount++;

    final detail = StringBuffer()
      ..write('key=$keyId')
      ..write(' op=$operation')
      ..write(' trigger_count=$_triggerCount');
    if (source != null) {
      detail.write(' source=$source');
    }

    // 记录到审计日志（哈希链防篡改）。
    AuditLogger.log(
      'honeypot.trigger',
      success: false,
      detail: detail.toString(),
    );

    // 控制台警告。
    developer.log(
      '⚠️ 蜜罐触发！key=$keyId op=$operation count=$_triggerCount',
      name: 'HoneypotService',
    );
  }

  /// 包装 VaultKeyStore 读取——自动检测蜜罐触发。
  Future<Uint8List?> readKey(String keyId) async {
    if (isHoneypotKey(keyId)) {
      onTrigger(
        keyId: keyId,
        operation: 'read',
      );
    }
    return vaultStore.readKey(keyId);
  }

  /// 验证蜜罐完整性。
  ///
  /// 检查所有假密钥是否仍存在于存储中。
  Future<HoneypotIntegrityResult> verifyIntegrity() async {
    final issues = <String>[];

    for (final id in _deployedIds) {
      try {
        final data = await vaultStore.readKey(id);
        if (data == null || data.isEmpty) {
          issues.add('$id: 数据为空或缺失');
        }
      } catch (e) {
        issues.add('$id: 读取失败 - $e');
      }
    }

    return HoneypotIntegrityResult(
      intact: issues.isEmpty,
      checkedKeys: _deployedIds.length,
      issues: issues,
    );
  }
}

/// 蜜罐完整性检查结果。
class HoneypotIntegrityResult {
  const HoneypotIntegrityResult({
    required this.intact,
    required this.checkedKeys,
    required this.issues,
  });

  final bool intact;
  final int checkedKeys;
  final List<String> issues;

  @override
  String toString() {
    if (intact) {
      return 'HoneypotIntegrityResult(intact, $checkedKeys keys OK)';
    }
    return 'HoneypotIntegrityResult(broken, ${issues.length} issues)';
  }
}
