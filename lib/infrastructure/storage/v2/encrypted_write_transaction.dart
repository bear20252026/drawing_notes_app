// encrypted_write_transaction.dart — V2 原子写入事务（带加密 + AAD + 备份）。
//
// 保证：
// 1. 写入前自动创建 .bak 备份（已存在时）。
// 2. 使用 AES-256-GCM 加密，AAD = aadContext + 文件路径。
// 3. 原子替换（先写临时文件再重命名）。
// 4. V1 明文目标拒绝写入（抛出 MigrationRequiredException）。

import 'dart:io';
import 'dart:typed_data';

import 'package:editor_core/editor_core.dart';

/// V1 明文目标拒绝写入异常。
class MigrationRequiredException implements Exception {
  const MigrationRequiredException(this.message);
  final String message;

  @override
  String toString() => 'MigrationRequiredException: $message';
}

/// 备份失败异常。
class BackupFailedException implements Exception {
  const BackupFailedException(this.message);
  final String message;

  @override
  String toString() => 'BackupFailedException: $message';
}

/// V2 密文目标状态——有效 V2 密文。
class ValidV2Ciphertext {
  const ValidV2Ciphertext();
}

/// V2 原子写入事务。
class EncryptedWriteTransaction {
  EncryptedWriteTransaction({
    required List<int> key,
    this.aadContext = '',
  }) : key = Uint8List.fromList(key);

  /// 256 位加密密钥。
  final Uint8List key;

  /// 附加认证数据上下文（前缀）。
  final String aadContext;

  /// 目标状态检查。
  Future<ValidV2Ciphertext?> destinationState(File file) async {
    if (!file.existsSync()) {
      return null;
    }

    final bytes = await file.readAsBytes();
    if (bytes.length < 2) {
      return null;
    }

    // V2 魔数：0xF2 0x56 ('F' 'V')。
    if (bytes[0] == 0xF2 && bytes[1] == 0x56) {
      return const ValidV2Ciphertext();
    }

    return null;
  }

  /// 提交加密写入。
  ///
  /// - [destination] 目标文件。
  /// - [plain] 明文数据。
  ///
  /// 抛出：
  /// - [MigrationRequiredException] 目标是 V1 明文。
  /// - [BackupFailedException] 备份创建失败。
  /// - [ArgumentError] 密钥长度无效。
  Future<void> commit({
    required File destination,
    required List<int> plain,
  }) async {
    // 密钥长度校验（在 commit 时抛出，便于测试）。
    if (key.length != 32) {
      throw ArgumentError('AES-256 密钥必须 32 字节，实际 ${key.length} 字节');
    }

    // V1 明文拒绝写入（文件存在但不是 V2 格式）。
    if (destination.existsSync()) {
      final bytes = await destination.readAsBytes();
      if (bytes.length < 2 || bytes[0] != 0xF2 || bytes[1] != 0x56) {
        throw MigrationRequiredException(
          '目标 ${destination.path} 是 V1 明文格式，需要先迁移到 V2',
        );
      }
    }

    // 创建 .bak 备份（V2 重写时）。
    if (destination.existsSync()) {
      final backup = File('${destination.path}.bak');
      try {
        destination.copySync(backup.path);
      } catch (e) {
        throw BackupFailedException('无法创建备份 ${backup.path}: $e');
      }
    }

    // 加密：AAD = aadContext + 文件路径。
    final aad = Uint8List.fromList([
      ...aadContext.codeUnits,
      ...destination.path.codeUnits,
    ]);

    final nonce = secureRandomBytes(12);
    final encrypted = aes256GcmEncrypt(
      plaintext: plain,
      key: key,
      nonce: nonce,
      aad: aad,
    );

    // 格式：魔数(2) || nonce(12) || ciphertext+tag(N)。
    final output = Uint8List(2 + 12 + encrypted.length);
    output[0] = 0xF2;
    output[1] = 0x56;
    output.setRange(2, 14, nonce);
    output.setRange(14, output.length, encrypted);

    // 原子写入：先写临时文件再重命名。
    final tmp = File('${destination.path}.tmp');
    await tmp.writeAsBytes(output, flush: true);
    await tmp.rename(destination.path);
  }
}
