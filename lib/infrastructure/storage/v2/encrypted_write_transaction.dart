import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// V2 密文文件 magic 头（4 字节——识别 V2 密文——防把 V1 明文/未知文件
/// 误判为可备份对象——S-001/S-002——专家更正方案）。
const String kV2Magic = 'DNN2';

/// 迁移要求异常（S-001：V1 明文/未知 destination——拒绝自动覆盖——
/// 仅显式迁移（复制-认证-校验-切换）——绝不原地覆盖 V1）。
class MigrationRequiredException implements Exception {
  const MigrationRequiredException(this.destination);

  final String destination;

  @override
  String toString() =>
      'MigrationRequiredException: $destination 为 V1 明文/未知格式'
      '——拒绝自动覆盖——需显式迁移（复制-认证-校验-切换）';
}

/// 备份失败异常（S-003：.bak 复制失败不得静默忽略——明确返回——
/// 原主文件保持可恢复状态）。
class BackupFailedException implements Exception {
  const BackupFailedException(this.destination, this.cause);

  final String destination;
  final Object cause;

  @override
  String toString() => 'BackupFailedException: 备份 $destination 失败——$cause';
}

/// destination 状态（专家更正方案：Missing / ValidV2Ciphertext /
/// LegacyOrUnknown——写入流程判定依据）。
sealed class DestinationState {
  const DestinationState();
}

final class MissingDestination extends DestinationState {
  const MissingDestination();
}

final class ValidV2Ciphertext extends DestinationState {
  const ValidV2Ciphertext();
}

final class LegacyOrUnknownDestination extends DestinationState {
  const LegacyOrUnknownDestination();
}

/// 加密写入事务（专家 I-004 更正——2026-08-16——S-001~S-004）。
///
/// 认证后原子提交：仅产生密文主/备/临时文件（AES-256-GCM + AAD 上下文
/// 绑定 + V2 magic 头——**无明文中间态**）；V1 明文/未知 destination 拒绝
/// 自动覆盖（MigrationRequired——不生成 .bak）；备份失败明确返回
/// （BackupFailed——不静默）；中断可恢复（临时清理——旧文件保留）。
class EncryptedWriteTransaction {
  EncryptedWriteTransaction({required this.key, required this.aadContext});

  /// 内容密钥（32 字节——调用方从会话/密钥管理层注入）。
  final List<int> key;

  /// AAD 上下文（'notebook｜笔记标识｜payload｜v2'——NIST SP 800-38D 绑定——
  /// 防跨文件/版本密文交换）。
  final String aadContext;

  final AesGcm _aes = AesGcm.with256bits();

  /// 判定 destination 状态（读取 header——Missing / ValidV2 / LegacyOrUnknown）。
  Future<DestinationState> destinationState(File destination) async {
    if (!await destination.exists()) return const MissingDestination();
    try {
      final bytes = await destination.readAsBytes();
      if (bytes.length >= 4 &&
          String.fromCharCodes(bytes.take(4)) == kV2Magic) {
        return const ValidV2Ciphertext();
      }
    } catch (_) {
      /* 读取失败按未知处理 */
    }
    return const LegacyOrUnknownDestination();
  }

  /// 认证后原子提交（专家更正流程）：
  /// 1. 生成并认证新 V2 密文（magic + nonce + cipher + mac）。
  /// 2. 创建同目录唯一临时密文文件。
  /// 3. 读取 destination header（Missing/ValidV2/LegacyOrUnknown）。
  /// 4. Missing：不创建 .bak，提交新密文。
  /// 5. ValidV2Ciphertext：复制旧密文为 .bak（失败返回 BackupFailedException）。
  /// 6. LegacyOrUnknown：拒绝自动覆盖，返回 MigrationRequiredException。
  /// 7. 原子替换 destination；8. 重新读取验证；9. 仅验证成功后 committed。
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
    final cipher = Uint8List.fromList([
      ...kV2Magic.codeUnits,
      ...nonce,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);

    final tmp = File(
      '${destination.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      await tmp.writeAsBytes(cipher, flush: true);
      final state = await destinationState(destination);
      switch (state) {
        case MissingDestination():
          // 不创建 .bak——提交新密文。
          break;
        case ValidV2Ciphertext():
          // 复制旧密文为 .bak——失败必须明确（S-003——不静默忽略）。
          try {
            await destination.copy('${destination.path}.bak');
          } catch (e) {
            try {
              await tmp.delete();
            } catch (_) {
              /* 忽略清理失败 */
            }
            throw BackupFailedException(destination.path, e);
          }
        case LegacyOrUnknownDestination():
          // 拒绝自动覆盖（S-001）——不 .bak——不覆盖——返回迁移要求。
          try {
            await tmp.delete();
          } catch (_) {
            /* 忽略清理失败 */
          }
          throw MigrationRequiredException(destination.path);
      }
      await tmp.rename(destination.path);
      // 提交后验证（V2 header——仅验证成功后 committed）。
      final verify = await destinationState(destination);
      if (verify is! ValidV2Ciphertext) {
        throw StateError('提交后验证失败：${destination.path} 非 V2 密文');
      }
    } catch (_) {
      // 中断可恢复：清理临时文件——旧主/备文件保留。
      if (await tmp.exists()) {
        try {
          await tmp.delete();
        } catch (_) {
          /* 忽略清理失败 */
        }
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
