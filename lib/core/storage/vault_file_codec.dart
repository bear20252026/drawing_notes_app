import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'package:drawing_notes_app/core/security/vault_key_service.dart';

/// 文件信封加密异常：密钥不匹配 / 载荷被篡改 / 版本不识别。
class VaultFileException implements Exception {
  const VaultFileException(this.reason);

  final String reason;

  @override
  String toString() => 'VaultFileException($reason)';
}

/// 锁定状态下尝试读取加密文件（fail-closed：不回退明文、不猜测）。
class VaultFileLockException implements Exception {
  const VaultFileLockException();

  @override
  String toString() => 'VaultFileLockException(保险库已锁定，加密文件不可读)';
}

/// 文档文件信封编解码（加密底座批次①b，2026-09-01）。
///
/// 落盘格式借鉴 Joplin E2EE 信封规范（魔数 + 版本 + 密文块）：
/// ```
/// "DNV"(3B 魔数) | 版本(1B) | AES-256-GCM 载荷 [nonce(12) | cipherText | tag(16)]
/// ```
/// 设计要点：
/// - 明文 JSON 以 `{` 开头、PNG 以魔数开头，攻击者一眼可辨；`DNV` 头让
///   加密文件同样可辨识——被辨识≠被读取，GCM tag 保证一个字节都改不动；
/// - AAD 绑定文件用途与 ID（`drawing-notes|file|v1|doc:<id>`），
///   防止密文在不同文件间移植（swap 攻击）；
/// - 加解密统一走 [VaultKeyService.aeadEncrypt/aeadDecrypt]（单一事实来源，
///   与保险库/媒体层共用同一套 AEAD 实现）。
abstract final class VaultFileCodec {
  /// 魔数 "DNV"（Drawing Notes Vault）。
  static const int _m0 = 0x44, _m1 = 0x4E, _m2 = 0x56;

  static const int _version = 1;
  static const int _headerBytes = 4;

  /// 嗅探字节是否为本加密信封（读路径自动分流：密文解密 / 明文兼容）。
  static bool isEncrypted(Uint8List bytes) =>
      bytes.length > _headerBytes &&
      bytes[0] == _m0 &&
      bytes[1] == _m1 &&
      bytes[2] == _m2;

  /// 加密为信封字节。[aadContext] 绑定文件身份（如 `doc:<id>`）。
  static Future<Uint8List> encrypt(
    Uint8List plain,
    Uint8List key, {
    required String aadContext,
  }) async {
    final payload = await VaultKeyService.aeadEncrypt(
      key,
      plain,
      _aadFor(aadContext),
    );
    return Uint8List.fromList([_m0, _m1, _m2, _version, ...payload]);
  }

  /// 解密信封字节。魔数不合法 / 版本不识别 / tag 校验失败（密钥错误或
  /// 载荷被篡改）→ 抛 [VaultFileException]。
  static Future<Uint8List> decrypt(
    Uint8List blob,
    Uint8List key, {
    required String aadContext,
  }) async {
    if (!isEncrypted(blob)) {
      throw const VaultFileException('不是 DNV 加密信封');
    }
    final version = blob[3];
    if (version != _version) {
      throw VaultFileException('不支持的信封版本 $version');
    }
    try {
      final plain = await VaultKeyService.aeadDecrypt(
        key,
        blob.sublist(_headerBytes),
        _aadFor(aadContext),
      );
      return Uint8List.fromList(plain);
    } on SecretBoxAuthenticationError {
      throw const VaultFileException('密钥不匹配或密文被篡改');
    }
  }

  static List<int> _aadFor(String context) =>
      'drawing-notes|file|v1|$context'.codeUnits;
}
