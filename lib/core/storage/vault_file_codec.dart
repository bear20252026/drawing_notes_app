import 'dart:io';
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

/// 文件受独立密码保护但会话中尚无该密码（批次②：单文件密码——
/// UI 捕获后弹出密码输入；不暴露任何内容，fail-closed）。
class VaultFilePasswordLockException implements Exception {
  const VaultFilePasswordLockException();

  @override
  String toString() => 'VaultFilePasswordLockException(文件受独立密码保护)';
}

/// 文档文件信封编解码（加密底座批次①b，2026-09-01）。
///
/// 落盘格式借鉴 Joplin E2EE 信封规范（魔数 + 版本 + 密文块）：
/// ```
/// v1（开屏密码/主密钥信封）：
///   "DNV"(3B 魔数) | 0x01 | AES-256-GCM 载荷 [nonce(12) | cipherText | tag(16)]
/// v2（批次② 单文件密码信封）：
///   "DNV"(3B 魔数) | 0x02 | salt(16) | iterations(u32 BE)
///                  | AES-256-GCM 载荷 [nonce(12) | cipherText | tag(16)]
/// ```
/// 设计要点：
/// - 明文 JSON 以 `{` 开头、PNG 以魔数开头，攻击者一眼可辨；`DNV` 头让
///   加密文件同样可辨识——被辨识≠被读取，GCM tag 保证一个字节都改不动；
/// - AAD 绑定文件用途与 ID（`drawing-notes|file|v1|doc:<id>`），
///   防止密文在不同文件间移植（swap 攻击）；
/// - v1 密钥 = 保险库主密钥（与开屏密码同源）；v2 密钥 = PBKDF2(文件密码,
///   salt) 现场派生——主密钥泄露不等于单文件密码文件可读（层级独立）；
/// - 加解密统一走 [VaultKeyService] statics（单一事实来源，
///   与保险库/媒体层共用同一套 AEAD/PBKDF2 实现）。
abstract final class VaultFileCodec {
  /// 魔数 "DNV"（Drawing Notes Vault）。
  static const int _m0 = 0x44, _m1 = 0x4E, _m2 = 0x56;

  static const int _version = 1;
  static const int _passwordVersion = 2;
  static const int _headerBytes = 4;

  /// v2 头部长度：魔数(3)+版本(1)+salt(16)+iterations(4)。
  static const int _passwordHeaderBytes = 4 + 16 + 4;

  /// 单文件密码 PBKDF2 迭代次数（与保险库 600k 对齐——OWASP M10）。
  static const int filePasswordIterations = 600000;

  /// 嗅探字节是否为本加密信封（读路径自动分流：密文解密 / 明文兼容）。
  static bool isEncrypted(Uint8List bytes) =>
      bytes.length > _headerBytes &&
      bytes[0] == _m0 &&
      bytes[1] == _m1 &&
      bytes[2] == _m2;

  /// 嗅探是否为 v2 单文件密码信封（批次②）。
  static bool isPasswordEnvelope(Uint8List bytes) =>
      isEncrypted(bytes) && bytes[3] == _passwordVersion;

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
  ///
  /// v2 单文件密码信封不走本方法（需要密码派生密钥）——抛出明确指引。
  static Future<Uint8List> decrypt(
    Uint8List blob,
    Uint8List key, {
    required String aadContext,
  }) async {
    if (!isEncrypted(blob)) {
      throw const VaultFileException('不是 DNV 加密信封');
    }
    final version = blob[3];
    if (version == _passwordVersion) {
      throw const VaultFileException(
        '该文件受独立密码保护，请使用 decryptWithPassword',
      );
    }
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

  /// 单文件密码信封加密（批次② v2）：随机盐 + PBKDF2 派生密钥 +
  /// AES-256-GCM；盐与迭代次数内嵌头部（明文无密——盐无需保密）。
  static Future<Uint8List> encryptWithPassword(
    Uint8List plain,
    String password, {
    required String aadContext,
    int iterations = filePasswordIterations,
  }) async {
    final salt = VaultKeyService.randomBytes(16);
    final key = await VaultKeyService.deriveKek(password, salt, iterations);
    final payload = await VaultKeyService.aeadEncrypt(
      Uint8List.fromList(key),
      plain,
      _aadFor(aadContext),
    );
    final iter = ByteData(4)..setUint32(0, iterations);
    return Uint8List.fromList([
      _m0,
      _m1,
      _m2,
      _passwordVersion,
      ...salt,
      ...iter.buffer.asUint8List(),
      ...payload,
    ]);
  }

  /// 单文件密码信封解密（批次② v2）。密码错误 / 载荷被篡改 →
  /// 抛 [VaultFileException]（GCM tag 校验，与「密码错误」不可区分——
  /// 同一报错防侧信道枚举）。
  static Future<Uint8List> decryptWithPassword(
    Uint8List blob,
    String password, {
    required String aadContext,
  }) async {
    if (!isPasswordEnvelope(blob)) {
      throw const VaultFileException('不是单文件密码信封');
    }
    if (blob.length <= _passwordHeaderBytes) {
      throw const VaultFileException('信封长度不合法');
    }
    final salt = blob.sublist(4, 20);
    final iter = ByteData.sublistView(blob, 20, 24).getUint32(0);
    final key = await VaultKeyService.deriveKek(password, salt, iter);
    try {
      final plain = await VaultKeyService.aeadDecrypt(
        Uint8List.fromList(key),
        blob.sublist(_passwordHeaderBytes),
        _aadFor(aadContext),
      );
      return Uint8List.fromList(plain);
    } on SecretBoxAuthenticationError {
      throw const VaultFileException('密码错误或密文被篡改');
    }
  }

  static List<int> _aadFor(String context) =>
      'drawing-notes|file|v1|$context'.codeUnits;

  /// 从文件路径派生 AAD 上下文（媒体/缩略图：AAD 绑定文件名——
  /// 文件名在写入时已含 docId/pageId 分组信息且不可被攻击者预测利用）。
  static String contextForPath(String path) {
    final name = path.replaceAll('\\', '/').split('/').last;
    return 'file:$name';
  }

  /// 读取图片字节（批次①c 媒体统一入口）：DNV 信封 → 共享保险库密钥
  /// 解密；否则原样返回（明文 / DAN 旧媒体兼容由调用方按需叠加）。
  ///
  /// 锁定 / 未注册共享实例 → 抛 [VaultFileLockException]（fail-closed）；
  /// 密钥不匹配 / 载荷被篡改 → 抛 [VaultFileException]。
  static Future<Uint8List> readImageBytes(File file) async {
    final raw = await file.readAsBytes();
    if (!isEncrypted(raw)) return raw;
    final key = VaultKeyService.sharedMasterKeyOrNull;
    if (key == null) throw const VaultFileLockException();
    return decrypt(raw, key, aadContext: contextForPath(file.path));
  }
}
