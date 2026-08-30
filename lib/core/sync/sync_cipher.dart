// 由 Claude 团队生成 | Drawing Notes App
// WebDAV 同步端到端加密（P4-A1）：纯逻辑密码模块。
// 复用 cryptography（AES-256-GCM）+ crypto（HMAC-SHA256），无新依赖。
// 纯 Dart，无 flutter/io/controller/storage/drawing 依赖。

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';

/// 同步加密器抽象：远端路径映射 + 文档字节加解密 + manifest 密封。
///
/// AAD 绑定 docId / manifest 上下文，使密文不可跨文档/跨用途交换。
abstract class SyncCipher {
  /// 远端对象路径。Noop 返回 docId；AES 返回 HMAC(hex)。
  String remotePath(String docId);

  /// 加密文档字节（AAD 绑定 docId）。
  Future<Uint8List> encryptDocumentBytes(Uint8List plain, String docId);

  /// 解密文档字节（AAD 校验 docId）。
  Future<Uint8List> decryptDocumentBytes(Uint8List cipher, String docId);

  /// 密封 manifest JSON（AAD 绑定 manifest 上下文）。
  Future<String> sealManifestJson(String manifestJson);

  /// 打开密封的 manifest JSON（AAD 校验上下文）。
  Future<String> openManifestJson(String sealedJson);
}

/// 恒等加密器（默认）：全部透传，保现有行为与测试不变。
class NoopSyncCipher implements SyncCipher {
  const NoopSyncCipher();

  @override
  String remotePath(String docId) => docId;

  @override
  Future<Uint8List> encryptDocumentBytes(Uint8List plain, String docId) async =>
      Uint8List.fromList(plain);

  @override
  Future<Uint8List> decryptDocumentBytes(
    Uint8List cipher,
    String docId,
  ) async => Uint8List.fromList(cipher);

  @override
  Future<String> sealManifestJson(String manifestJson) async => manifestJson;

  @override
  Future<String> openManifestJson(String sealedJson) async => sealedJson;
}

/// AES-256-GCM 同步加密器。
///
/// 构造注入 32 字节主密钥；加密载荷格式：
/// `{"mode":"sync-doc"|"sync-manifest","v":1,"n":base64(nonce),"c":base64(cipherText),"m":base64(mac)}`
class AesSyncCipher implements SyncCipher {
  AesSyncCipher({required this.key}) : assert(key.length == 32, '主密钥必须 32 字节');

  /// 32 字节主密钥。
  final List<int> key;

  static const int _nonceLength = 12;
  static const int _macLength = 16;

  // AAD 上下文常量。
  static const _docAadPrefix = 'drawing-notes|sync|doc|';
  static const _docAadSuffix = '|v1';
  static const _manifestAad = 'drawing-notes|sync|manifest|v1';
  static const _nameHmacContext = 'drawing-notes|sync|name|';

  /// 文档 AAD：绑定 docId。
  Uint8List _docAad(String docId) =>
      Uint8List.fromList(utf8.encode('$_docAadPrefix$docId$_docAadSuffix'));

  @override
  String remotePath(String docId) {
    // HMAC-SHA256(key, context|docId) → 小写 hex（64 字符）。确定性、不可逆。
    final hmac = crypto.Hmac(crypto.sha256, key);
    final digest = hmac.convert(utf8.encode('$_nameHmacContext$docId'));
    return digest.toString(); // 小写 hex
  }

  @override
  Future<Uint8List> encryptDocumentBytes(Uint8List plain, String docId) async {
    return _encrypt(plain, _docAad(docId), 'sync-doc');
  }

  @override
  Future<Uint8List> decryptDocumentBytes(Uint8List cipher, String docId) async {
    return _decrypt(cipher, _docAad(docId), 'sync-doc');
  }

  @override
  Future<String> sealManifestJson(String manifestJson) async {
    final bytes = utf8.encode(manifestJson);
    final cipher = _encrypt(
      Uint8List.fromList(bytes),
      _manifestAadBytes,
      'sync-manifest',
    );
    return cipher.then((c) => utf8.decode(c));
  }

  @override
  Future<String> openManifestJson(String sealedJson) async {
    final bytes = utf8.encode(sealedJson);
    final plain = _decrypt(
      Uint8List.fromList(bytes),
      _manifestAadBytes,
      'sync-manifest',
    );
    return plain.then((p) => utf8.decode(p));
  }

  static final Uint8List _manifestAadBytes = Uint8List.fromList(
    utf8.encode(_manifestAad),
  );

  /// 加密并编码为 JSON 字符串（UTF-8 字节承载）。
  Future<Uint8List> _encrypt(
    Uint8List plain,
    Uint8List aad,
    String mode,
  ) async {
    final nonce = _randomBytes(_nonceLength);
    final box = await AesGcm.with256bits().encrypt(
      plain,
      secretKey: SecretKey(key),
      nonce: nonce,
      aad: aad,
    );
    final payload = jsonEncode({
      'mode': mode,
      'v': 1,
      'n': base64Encode(nonce),
      'c': base64Encode(box.cipherText),
      'm': base64Encode(box.mac.bytes),
    });
    return Uint8List.fromList(utf8.encode(payload));
  }

  /// 解码 JSON 字符串并解密（mode 不匹配 / AAD 不符 → 抛异常）。
  Future<Uint8List> _decrypt(
    Uint8List cipher,
    Uint8List aad,
    String expectedMode,
  ) async {
    final map = jsonDecode(utf8.decode(cipher)) as Map<String, dynamic>;
    final mode = map['mode'];
    if (mode != expectedMode) {
      throw FormatException('加密数据 mode 不匹配（期望 $expectedMode，实际 $mode）');
    }
    final nonce = base64Decode(_requireString(map, 'n'));
    final cipherText = base64Decode(_requireString(map, 'c'));
    final macBytes = base64Decode(_requireString(map, 'm'));
    _requireFixedLength('nonce', nonce, _nonceLength);
    _requireFixedLength('MAC', macBytes, _macLength);
    try {
      final plain = await AesGcm.with256bits().decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes)),
        secretKey: SecretKey(key),
        aad: aad,
      );
      return Uint8List.fromList(plain);
    } on SecretBoxAuthenticationError {
      // AAD 不符（docId 被替换）或密钥错误 → 认证失败。
      throw FormatException('同步数据认证失败：AAD 不符或密钥错误');
    }
  }

  static String _requireString(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is! String) {
      throw FormatException('加密数据缺少字段：$key');
    }
    return value;
  }

  static void _requireFixedLength(String name, List<int> bytes, int expected) {
    if (bytes.length != expected) {
      throw FormatException('$name 长度不合法（应为 $expected 字节）');
    }
  }

  static List<int> _randomBytes(int n) {
    final rng = Random.secure();
    return List<int>.generate(n, (_) => rng.nextInt(256));
  }
}

// ── 密钥派生工具（供上层使用）─────────────────────────────────

/// 生成 [length] 字节随机盐（默认 16）。
List<int> generateSalt({int length = 16}) {
  final rng = Random.secure();
  return List<int>.generate(length, (_) => rng.nextInt(256));
}

/// 从密码派生 32 字节主密钥：PBKDF2-HMAC-SHA256。
///
/// 默认 60 万次迭代（OWASP 2026 推荐）。密码/盐相同 → 同 key。
Future<List<int>> deriveMasterKey(
  String password,
  List<int> salt, {
  int iterations = 600000,
}) async {
  final pbkdf2 = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: iterations,
    bits: 256,
  );
  final key = await pbkdf2.deriveKey(
    secretKey: SecretKey(utf8.encode(password)),
    nonce: salt,
  );
  return key.extractBytes();
}
