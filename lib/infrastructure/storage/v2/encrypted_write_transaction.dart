import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// 加密写入事务（专家 I-004——2026-08-16——批次 A 安全护栏）。
///
/// 认证后原子提交：仅产生密文主/备/临时文件（AES-256-GCM + AAD 上下文
/// 绑定——**无明文中间态**——专家"主、副、临时文件扫描均无测试文本"）；
/// 中断（异常）时清理临时文件——旧文件（主/备）保留——可恢复。
/// 按专家"EncryptedWriteTransaction"重写单元的最小职责（认证后原子
/// 提交——故障可恢复）。
class EncryptedWriteTransaction {
  EncryptedWriteTransaction({required this.key, required this.aadContext});

  /// 内容密钥（32 字节——调用方从会话/密钥管理层注入）。
  final List<int> key;

  /// AAD 上下文（'notebook｜笔记标识｜payload｜v2'——NIST SP 800-38D 绑定——
  /// 防跨文件/版本密文交换）。
  final String aadContext;

  final AesGcm _aes = AesGcm.with256bits();

  /// 认证后原子提交：临时密文 → fsync → .bak（旧密文——备份保障）→
  /// rename 主文件。返回密文大小（字节）。中断时清理临时文件——
  /// 旧主/备文件保留（回滚安全）。
  Future<int> commit({
    required File destination,
    required Uint8List plain,
  }) async {
    final aad = aadContext.codeUnits;
    final nonce = _randomNonce();
    final box = await _aes.encrypt(
      plain,
      secretKey: SecretKey(key),
      nonce: nonce,
      aad: aad,
    );
    final cipher =
        Uint8List.fromList([...nonce, ...box.cipherText, ...box.mac.bytes]);

    final tmp = File(
      '${destination.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      await tmp.writeAsBytes(cipher, flush: true);
      if (await destination.exists()) {
        try {
          // .bak = 旧文件（已密文——若旧文件明文（V1 迁移前）则保持——
          // V2 写入始终密文主/备/临时）。
          await destination.copy('${destination.path}.bak');
        } catch (_) {
          // 备份失败不阻塞当前写入（恢复保障）。
        }
      }
      await tmp.rename(destination.path);
    } catch (_) {
      // 中断可恢复：清理临时文件——旧主/备文件保留。
      if (await tmp.exists()) {
        try {
          await tmp.delete();
        } catch (_) {/* 忽略清理失败 */}
      }
      rethrow;
    }
    return cipher.length;
  }

  static Uint8List _randomNonce() {
    final rng = Random.secure();
    return Uint8List.fromList(List<int>.generate(12, (_) => rng.nextInt(256)));
  }
}
