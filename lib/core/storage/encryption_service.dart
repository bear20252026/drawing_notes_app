import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// 密码保护加密服务（C3/C5，借鉴 Joplin 端到端加密理念）。
///
/// 使用 AES-GCM 256 对称加密；密钥由 PBKDF2（加盐、10 万次迭代）从密码
/// 派生（评审发现 P2：单次 SHA-256 可被离线暴力破解，必须使用慢 KDF），
/// 每次加密生成随机盐（16B）与随机 nonce（12B），一并存入密文 JSON。
/// 纯 Dart 实现，离线可用，无平台依赖。
class EncryptionService {
  const EncryptionService();

  /// PBKDF2 迭代次数（慢 KDF，抵御离线暴力破解）。
  ///
  /// 审计修复（2026-08-15）：OWASP 2026 对 PBKDF2-HMAC-SHA256 推荐
  /// 60 万次，原 10 万次（v=2）低于推荐。新数据用 60 万次（v=3），
  /// 解密按 v 字段分派迭代次数，旧数据（v≤2）继续用 10 万次可解。
  static const int _pbkdf2IterationsLegacy = 100000; // 旧数据（v ≤ 2）
  static const int _pbkdf2IterationsCurrent = 600000; // 新数据（v ≥ 3）

  // H-07 修复（专家审计 2026-08-15）：封装输入严格校验——固定字段长度
  // （GCM nonce 12 / MAC 16 / PBKDF2 盐 16 / 主密钥 32）+ 输入大小上限。
  static const int _saltLength = 16;
  static const int _nonceLength = 12;
  static const int _macLength = 16;
  static const int _masterKeyLength = 32;
  static const int _maxEncryptedInputBytes = 10 * 1024 * 1024; // 10MB

  /// 按格式版本选择 PBKDF2 迭代次数（无 v 字段视为旧格式 v=2）。
  static int _iterationsFor(int version) =>
      version >= 3 ? _pbkdf2IterationsCurrent : _pbkdf2IterationsLegacy;

  /// 派生 32 字节密钥：PBKDF2-HMAC-SHA256(密码, 随机盐, [iterations])。
  Future<SecretKey> _deriveKey(
    String password,
    List<int> salt, {
    int iterations = _pbkdf2IterationsCurrent,
  }) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );
    return pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
  }

  /// 加密 [plainText]，返回 JSON 串（含盐、nonce 与密文，base64）。
  Future<String> encrypt(String plainText, String password) async {
    final salt = _randomBytes(16);
    final key = await _deriveKey(password, salt);
    final aes = AesGcm.with256bits();
    final nonce = _randomBytes(12);
    final box = await aes.encrypt(
      utf8.encode(plainText),
      secretKey: key,
      nonce: nonce,
    );
    return jsonEncode({
      's': base64Encode(salt),
      'n': base64Encode(nonce),
      'c': base64Encode(box.cipherText),
      'm': box.mac.bytes.isNotEmpty ? base64Encode(box.mac.bytes) : '',
      'v': 3, // 格式版本（KDF=PBKDF2 60 万次，审计修复 2026-08-15）
    });
  }

  /// 解密 [encryptedJson]；密码错误或数据损坏时抛出 [FormatException]。
  Future<String> decrypt(String encryptedJson, String password) async {
    // H-07 修复：输入大小预检（防恶意超长输入资源消耗）。
    _requireInputSize(encryptedJson);
    final map = jsonDecode(encryptedJson) as Map<String, dynamic>;
    final salt = base64Decode(_requireString(map, 's'));
    _requireFixedLength('盐', salt, _saltLength);
    // 按 v 字段分派迭代次数：v≥3 用 60 万次（新数据），v≤2/无 v 用 10 万次（旧数据兼容）。
    final v = map['v'] is int ? map['v'] as int : 2;
    _requireKnownVersion(v);
    final key = await _deriveKey(
      password,
      salt,
      iterations: _iterationsFor(v),
    );
    return _gcmDecrypt(map, key);
  }

  /// ---- 密码盘（U盘即钥匙）keyfile 模式 ----
  ///
  /// 设计见 docs/PASSWORD_DISK_DESIGN.md：
  /// - 主密钥（32 字节）只存在 U 盘 key.frogkey，软件不持久化；
  /// - 页面内容用主密钥 AES-256-GCM 加密；
  /// - 恢复密钥（24 位纸备份）经 PBKDF2 派生 KEK，包裹主密钥成信封 ek，
  ///   U 盘丢失时可解信封找回主密钥。

  /// 用主密钥加密 [plainText]，返回 JSON 串（mode=keyfile）。
  Future<String> encryptWithKey(String plainText, List<int> masterKey) async {
    final aes = AesGcm.with256bits();
    final nonce = _randomBytes(12);
    final box = await aes.encrypt(
      utf8.encode(plainText),
      secretKey: SecretKey(masterKey),
      nonce: nonce,
    );
    return jsonEncode({
      'mode': 'keyfile',
      'n': base64Encode(nonce),
      'c': base64Encode(box.cipherText),
      'm': box.mac.bytes.isNotEmpty ? base64Encode(box.mac.bytes) : '',
    });
  }

  /// 用主密钥解密（mode=keyfile）；密钥错误抛 [FormatException]。
  Future<String> decryptWithKey(
    String encryptedJson,
    List<int> masterKey,
  ) async {
    // H-07 修复：主密钥长度 + 输入大小预检。
    _requireFixedLength('主密钥', masterKey, _masterKeyLength);
    _requireInputSize(encryptedJson);
    final map = jsonDecode(encryptedJson) as Map<String, dynamic>;
    if (map['mode'] != 'keyfile') {
      throw FormatException('不是密码盘加密数据');
    }
    return _gcmDecrypt(map, SecretKey(masterKey));
  }

  /// 生成恢复密钥信封：恢复密钥 + 随机盐 -> PBKDF2 派生 KEK -> 加密主密钥。
  ///
  /// 返回 (salt, nonce2, ek) 的 JSON 串，供数据头保存。
  Future<String> wrapMasterKey(List<int> masterKey, String recoveryKey) async {
    final salt = _randomBytes(16);
    final kek = await _deriveKey(recoveryKey, salt);
    final aes = AesGcm.with256bits();
    final nonce2 = _randomBytes(12);
    final box = await aes.encrypt(masterKey, secretKey: kek, nonce: nonce2);
    return jsonEncode({
      'salt': base64Encode(salt),
      'n2': base64Encode(nonce2),
      'ek': base64Encode(box.cipherText),
      'm2': box.mac.bytes.isNotEmpty ? base64Encode(box.mac.bytes) : '',
      'v': 3, // 审计修复（2026-08-15）：PBKDF2 60 万次
    });
  }

  /// 解恢复密钥信封：恢复密钥错误或信封损坏抛 [FormatException]。
  Future<List<int>> unwrapMasterKey(String envelope, String recoveryKey) async {
    // H-07 修复：输入大小预检 + 盐长度校验。
    _requireInputSize(envelope);
    final map = jsonDecode(envelope) as Map<String, dynamic>;
    final salt = base64Decode(_requireString(map, 'salt'));
    _requireFixedLength('盐', salt, _saltLength);
    // 按 v 字段分派迭代次数：v≥3 用 60 万次，v≤2/无 v 用 10 万次（旧信封兼容）。
    final v = map['v'] is int ? map['v'] as int : 2;
    _requireKnownVersion(v);
    final kek = await _deriveKey(
      recoveryKey,
      salt,
      iterations: _iterationsFor(v),
    );
    final aes = AesGcm.with256bits();
    final ek = base64Decode(_requireString(map, 'ek'));
    final n2 = base64Decode(_requireString(map, 'n2'));
    final m2 = base64Decode(_requireString(map, 'm2'));
    // H-07 修复：信封固定字段长度校验（nonce 12 / MAC 16 / 主密钥 32）。
    _requireFixedLength('nonce2', n2, _nonceLength);
    _requireFixedLength('MAC2', m2, _macLength);
    _requireFixedLength('主密钥', ek, _masterKeyLength);
    final clear = await aes.decrypt(
      SecretBox(ek, nonce: n2, mac: Mac(m2)),
      secretKey: kek,
    );
    return clear;
  }

  /// AES-GCM 解密封装（共用逻辑）。
  ///
  /// 所有字段缺失或类型错误统一转为 [FormatException]（与文档契约一致），
  /// 避免被篡改的数据抛 [TypeError] 破坏上层调用方的异常处理。
  Future<String> _gcmDecrypt(Map<String, dynamic> map, SecretKey key) async {
    final nonce = base64Decode(_requireString(map, 'n'));
    final cipher = base64Decode(_requireString(map, 'c'));
    final macBytes = base64Decode(_requireString(map, 'm'));
    // H-07 修复：固定字段长度校验（GCM nonce 12 / MAC 16——防畸形封装）。
    _requireFixedLength('nonce', nonce, _nonceLength);
    _requireFixedLength('MAC', macBytes, _macLength);
    final aes = AesGcm.with256bits();
    final clear = await aes.decrypt(
      SecretBox(cipher, nonce: nonce, mac: Mac(macBytes)),
      secretKey: key,
    );
    return utf8.decode(clear);
  }

  /// 读取 [key] 字段并保证其为字符串；缺失/类型错误抛 [FormatException]。
  static String _requireString(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is! String) {
      throw FormatException('加密数据缺少字段：$key');
    }
    return value;
  }

  /// H-07 修复：封装输入大小预检（防恶意超长输入资源消耗）。
  static void _requireInputSize(String input) {
    if (input.length > _maxEncryptedInputBytes) {
      throw FormatException('加密数据过大（超过 10MB 限制）');
    }
  }

  /// H-07 修复：固定字段长度校验（防畸形/截断封装）。
  static void _requireFixedLength(String name, List<int> bytes, int expected) {
    if (bytes.length != expected) {
      throw FormatException('$name 长度不合法（应为 $expected 字节）');
    }
  }

  /// H-07 修复：格式版本白名单（防未知 v 字段分派意外路径）。
  static void _requireKnownVersion(int version) {
    if (version != 2 && version != 3) {
      throw FormatException('未知加密格式版本：v$version');
    }
  }

  /// ---- H-06 修复（专家审计 2026-08-15）：AAD v4 上下文绑定 ----
  ///
  /// NIST SP 800-38D：AAD 绑定协议上下文（版本/用途/ID——"指示明文如何
  /// 处理的字段"）——使"把 A 笔记的密文替换到 B 笔记"在认证时失败。
  /// v4 格式：{mode:'payload', v:4, n, c, m}——AAD 不落盘（解密时按
  /// notebookId 重构），密文无法跨笔记/跨用途交换。现有 v2/v3 流程保持
  /// 只读兼容；迁移（保存流程切换 v4 + 全量重加密）需向量/迁移测试后实施。
  Future<String> encryptNotebookPayload({
    required String notebookId,
    required String plaintext,
    required List<int> key,
  }) async {
    final aes = AesGcm.with256bits();
    final nonce = _randomBytes(12);
    final aad = _payloadAad(notebookId);
    final box = await aes.encrypt(
      utf8.encode(plaintext),
      secretKey: SecretKey(key),
      nonce: nonce,
      aad: aad,
    );
    return jsonEncode({
      'mode': 'payload',
      'v': 4,
      'n': base64Encode(nonce),
      'c': base64Encode(box.cipherText),
      'm': box.mac.bytes.isNotEmpty ? base64Encode(box.mac.bytes) : '',
    });
  }

  /// 解密 v4 载荷（AAD 校验：notebookId 不符即认证失败）。
  Future<String> decryptNotebookPayload({
    required String notebookId,
    required String encryptedJson,
    required List<int> key,
  }) async {
    _requireInputSize(encryptedJson);
    final map = jsonDecode(encryptedJson) as Map<String, dynamic>;
    if (map['mode'] != 'payload' || map['v'] != 4) {
      throw FormatException('不是 v4 载荷数据');
    }
    final nonce = base64Decode(_requireString(map, 'n'));
    final cipher = base64Decode(_requireString(map, 'c'));
    final macBytes = base64Decode(_requireString(map, 'm'));
    _requireFixedLength('nonce', nonce, _nonceLength);
    _requireFixedLength('MAC', macBytes, _macLength);
    final clear = await AesGcm.with256bits().decrypt(
      SecretBox(cipher, nonce: nonce, mac: Mac(macBytes)),
      secretKey: SecretKey(key),
      aad: _payloadAad(notebookId),
    );
    return utf8.decode(clear);
  }

  /// v4 AAD：绑定应用/笔记 ID/用途/版本（NIST SP 800-38D 上下文绑定）。
  static Uint8List _payloadAad(String notebookId) => Uint8List.fromList(
    utf8.encode('drawing-notes|notebook|$notebookId|payload|v4'),
  );

  /// 生成 [n] 字节随机数（盐/nonce）。
  static List<int> _randomBytes(int n) {
    final rng = Random.secure();
    return List<int>.generate(n, (_) => rng.nextInt(256));
  }

  /// 读取加密数据格式版本（红蓝攻防 D-1 修复 2026-08-15）：
  /// 用于判断旧格式（v≤2 = PBKDF2 10 万次迭代）提示用户重新保存升级；
  /// 无 v 字段的旧数据视为 v=2，解析失败保守视为旧格式。
  static int formatVersionOf(String encryptedJson) {
    try {
      final map = jsonDecode(encryptedJson) as Map<String, dynamic>;
      return map['v'] is int ? map['v'] as int : 2;
    } catch (_) {
      return 2;
    }
  }
}
