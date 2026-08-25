import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

/// 密码保护加密服务（C3/C5，借鉴 Joplin 端到端加密理念）。
///
/// 使用 AES-GCM 256 对称加密；密钥由 Argon2id（t=3, m=64MiB, p=1）
/// 从密码派生（2026-08-24 军工升级：替换 PBKDF2 为 Argon2id——
/// OWASP 2026 推荐慢 KDF + 内存硬度，抗 GPU/ASIC 暴力破解），
/// 每次加密生成随机盐（32B）与随机 nonce（12B），一并存入密文 JSON。
/// 纯 Dart 实现，离线可用，无平台依赖。
///
/// 版本历史：
/// - v=2: PBKDF2 10 万次（旧数据兼容）
/// - v=3: PBKDF2 60 万次（审计修复 2026-08-15）
/// - v=4: PBKDF2 + AAD 上下文绑定（H-06 修复 2026-08-15）
/// - v=5: Argon2id + HKDF-SHA256 密钥派生链（军工升级 2026-08-24）
class EncryptionService {
  /// 生产默认参数：Argon2id t=3, m=65536KiB(64MiB), p=1。
  const EncryptionService()
      : argon2Iterations = 3,
        argon2MemoryKiB = 65536, // 64 MiB in KiB
        argon2Parallelism = 1;

  /// 测试用构造函数：可降低 Argon2id 参数（m=1024KiB→1MiB 测试加速）。
  const EncryptionService.test({
    this.argon2Iterations = 1,
    this.argon2MemoryKiB = 1024, // 1 MiB（测试加速）
    this.argon2Parallelism = 1,
  });

  /// Argon2id 迭代次数（t）。
  final int argon2Iterations;

  /// Argon2id 内存参数（KiB）。65536 = 64 MiB。
  final int argon2MemoryKiB;

  /// Argon2id 并行度（p）。
  final int argon2Parallelism;

  /// PBKDF2 迭代次数（旧数据兼容）。
  static const int _pbkdf2IterationsLegacy = 100000; // 旧数据（v ≤ 2）
  static const int _pbkdf2IterationsCurrent = 600000; // 旧数据（v = 3/4）

  // H-07 修复（专家审计 2026-08-15）：封装输入严格校验——固定字段长度
  // （GCM nonce 12 / MAC 16 / Argon2id 盐 32 / 主密钥 32）+ 输入大小上限。
  static const int _saltLength = 32;
  static const int _nonceLength = 12;
  static const int _macLength = 16;
  static const int _masterKeyLength = 32;
  static const int _maxEncryptedInputBytes = 10 * 1024 * 1024; // 10MB

  /// PIN 最小长度（军工级安全要求）。
  static const int kPinMinLength = 6;

  /// 按格式版本选择 KDF 策略。
  ///
  /// v=5: Argon2id + HKDF-SHA256 密钥派生链
  /// v=3/4: PBKDF2 60 万次
  /// v=2/无: PBKDF2 10 万次
  static bool _isArgon2id(int version) => version >= 5;

  static int _pbkdf2IterationsFor(int version) =>
      version >= 3 ? _pbkdf2IterationsCurrent : _pbkdf2IterationsLegacy;

  /// Argon2id 密钥派生（t=iterations, m=memoryKiB, p=parallelism → 32 字节）。
  Future<SecretKey> _deriveKeyArgon2id(
    String password,
    List<int> salt,
  ) async {
    final algorithm = Argon2id(
      parallelism: argon2Parallelism,
      memory: argon2MemoryKiB,
      iterations: argon2Iterations,
      hashLength: 32,
    );
    return algorithm.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
  }

  /// PBKDF2 密钥派生（旧数据兼容）。
  Future<SecretKey> _deriveKeyPbkdf2(
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

  /// 统一密钥派生入口（按版本分派 KDF）。
  Future<SecretKey> _deriveKey(
    String password,
    List<int> salt, {
    int version = 5,
    int? pbkdf2Iterations,
  }) async {
    if (_isArgon2id(version)) {
      return _deriveKeyArgon2id(password, salt);
    }
    return _deriveKeyPbkdf2(
      password,
      salt,
      iterations: pbkdf2Iterations ?? _pbkdf2IterationsFor(version),
    );
  }

  /// HKDF-SHA256 密钥派生链：masterKey → K1(enc) + K2(auth) + K3(kek)。
  ///
  /// 军工标准（2026-08-24）：Argon2id 派生主密钥后，通过 HKDF 分离不同用途子密钥，
  /// 避免密钥重用攻击（NIST SP 800-108）。
  Future<(SecretKey, SecretKey, SecretKey)> deriveKeyChain({
    required String password,
    required List<int> salt,
  }) async {
    final masterKey = await _deriveKeyArgon2id(password, salt);
    final masterBytes = await masterKey.extractBytes();
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final k1 = await hkdf.deriveKey(
      secretKey: SecretKey(masterBytes),
      info: utf8.encode('drawing-notes|enc|v5'),
      nonce: salt,
    );
    final k2 = await hkdf.deriveKey(
      secretKey: SecretKey(masterBytes),
      info: utf8.encode('drawing-notes|auth|v5'),
      nonce: salt,
    );
    final k3 = await hkdf.deriveKey(
      secretKey: SecretKey(masterBytes),
      info: utf8.encode('drawing-notes|kek|v5'),
      nonce: salt,
    );
    return (k1, k2, k3);
  }

  /// 验证 PIN 长度是否符合最小要求。
  static bool isPinLengthValid(String pin) => pin.length >= kPinMinLength;

  /// 渐进式延迟序列（秒）：1s → 5s → 30s → 5min → 1h。
  ///
  /// 每次认证失败递增延迟级别，成功后重置。用于防暴力破解。
  static const List<int> progressiveDelaySeconds = [1, 5, 30, 300, 3600];

  /// 计算渐进式延迟（失败次数 → 延迟秒数）。
  ///
  /// 返回延迟秒数（0 = 无延迟）。失败次数超过序列长度时取最大值。
  static int getProgressiveDelay(int failCount) {
    if (failCount <= 0) return 0;
    final index = (failCount - 1).clamp(0, progressiveDelaySeconds.length - 1);
    return progressiveDelaySeconds[index];
  }

  /// 获取渐进式延迟信息（用于 UI 显示）。
  static String getProgressiveDelayInfo(int failCount) {
    if (failCount <= 0) return '无延迟';
    final delay = getProgressiveDelay(failCount);
    if (delay < 60) return '${delay}秒';
    if (delay < 3600) return '${delay ~/ 60}分钟';
    return '${delay ~/ 3600}小时';
  }

  /// 加密 [plainText]，返回 JSON 串（含盐、nonce 与密文，base64）。
  ///
  /// v=5 格式（Argon2id + HKDF-SHA256 密钥派生链）。
  Future<String> encrypt(String plainText, String password) async {
    final salt = _randomBytes(_saltLength);
    // v=5: Argon2id → HKDF-SHA256 → K1(enc)
    final (k1, _, _) = await deriveKeyChain(password: password, salt: salt);
    final aes = AesGcm.with256bits();
    final nonce = _randomBytes(_nonceLength);
    final box = await aes.encrypt(
      utf8.encode(plainText),
      secretKey: k1,
      nonce: nonce,
    );
    return jsonEncode({
      's': base64Encode(salt),
      'n': base64Encode(nonce),
      'c': base64Encode(box.cipherText),
      'm': box.mac.bytes.isNotEmpty ? base64Encode(box.mac.bytes) : '',
      'v': 5, // 格式版本（KDF=Argon2id t=3 m=64MiB p=1，军工升级 2026-08-24）
    });
  }

  /// 解密 [encryptedJson]；密码错误或数据损坏时抛出 [FormatException]。
  ///
  /// 自动按 v 字段分派 KDF：v≥5 Argon2id，v≤4 PBKDF2。
  Future<String> decrypt(String encryptedJson, String password) async {
    // H-07 修复：输入大小预检（防恶意超长输入资源消耗）。
    _requireInputSize(encryptedJson);
    final map = jsonDecode(encryptedJson) as Map<String, dynamic>;
    final salt = base64Decode(_requireString(map, 's'));
    // 按 v 字段分派 KDF。
    final v = map['v'] is int ? map['v'] as int : 2;
    _requireKnownVersion(v);
    // 盐长度：v≤4 旧格式 16 字节，v≥5 新格式 32 字节。
    final expectedSaltLen = v >= 5 ? _saltLength : 16;
    _requireFixedLength('盐', salt, expectedSaltLen);

    if (_isArgon2id(v)) {
      // v=5: Argon2id → HKDF-SHA256 → K1(enc)
      final (k1, _, _) = await deriveKeyChain(password: password, salt: salt);
      return _gcmDecrypt(map, k1);
    } else {
      // v≤4: PBKDF2（旧数据兼容）
      final key = await _deriveKeyPbkdf2(
        password,
        salt,
        iterations: _pbkdf2IterationsFor(v),
      );
      return _gcmDecrypt(map, key);
    }
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

  /// 生成恢复密钥信封：恢复密钥 + 随机盐 -> Argon2id 派生 KEK -> 加密主密钥。
  ///
  /// v=5 格式（Argon2id t=3 m=64MiB p=1，军工升级 2026-08-24）。
  /// 返回 (salt, nonce2, ek) 的 JSON 串，供数据头保存。
  Future<String> wrapMasterKey(List<int> masterKey, String recoveryKey) async {
    final salt = _randomBytes(_saltLength);
    // v=5: Argon2id → HKDF-SHA256 → K1(enc)
    final (k1, _, _) = await deriveKeyChain(password: recoveryKey, salt: salt);
    final aes = AesGcm.with256bits();
    final nonce2 = _randomBytes(12);
    final box = await aes.encrypt(masterKey, secretKey: k1, nonce: nonce2);
    return jsonEncode({
      'salt': base64Encode(salt),
      'n2': base64Encode(nonce2),
      'ek': base64Encode(box.cipherText),
      'm2': box.mac.bytes.isNotEmpty ? base64Encode(box.mac.bytes) : '',
      'v': 5, // 军工升级（2026-08-24）：Argon2id t=3 m=64MiB p=1
    });
  }

  /// 解恢复密钥信封：恢复密钥错误或信封损坏抛 [FormatException]。
  ///
  /// 自动按 v 字段分派 KDF：v≥5 Argon2id + HKDF，v≤4 PBKDF2（旧信封兼容）。
  Future<List<int>> unwrapMasterKey(String envelope, String recoveryKey) async {
    // H-07 修复：输入大小预检 + 盐长度校验。
    _requireInputSize(envelope);
    final map = jsonDecode(envelope) as Map<String, dynamic>;
    final salt = base64Decode(_requireString(map, 'salt'));
    // 按 v 字段分派 KDF：v≥5 Argon2id + HKDF，v≤4 PBKDF2（旧信封兼容）。
    final v = map['v'] is int ? map['v'] as int : 2;
    _requireKnownVersion(v);
    // 盐长度：v≥5 新格式 32 字节，v≤4 旧格式 16 字节。
    final expectedSaltLen = v >= 5 ? _saltLength : 16;
    _requireFixedLength('盐', salt, expectedSaltLen);
    SecretKey kek;
    if (_isArgon2id(v)) {
      // v=5: Argon2id → HKDF-SHA256 → K1(enc)
      final (k1, _, _) = await deriveKeyChain(password: recoveryKey, salt: salt);
      kek = k1;
    } else {
      kek = await _deriveKeyPbkdf2(
        recoveryKey,
        salt,
        iterations: _pbkdf2IterationsFor(v),
      );
    }
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
    // AAD（v=4 兼容）：存在 'a' 字段时解码并传入解密。
    final aad = map['a'] is String ? base64Decode(map['a'] as String) : <int>[];
    final aes = AesGcm.with256bits();
    final clear = await aes.decrypt(
      SecretBox(cipher, nonce: nonce, mac: Mac(macBytes)),
      secretKey: key,
      aad: aad,
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
  ///
  /// v=5: Argon2id + HKDF-SHA256 密钥派生链（军工升级 2026-08-24）
  /// v=4: PBKDF2 + AAD 上下文绑定（H-06 修复 2026-08-15）
  /// v=3: PBKDF2 60 万次（审计修复 2026-08-15）
  /// v=2: PBKDF2 10 万次（旧数据兼容）
  static void _requireKnownVersion(int version) {
    if (version < 2 || version > 5) {
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

  /// 密码模式 v4（H-06 补全，专家审计 2026-08-15）：PBKDF2 派生 key +
  /// AAD 上下文绑定。载荷 v4 信封内嵌 salt（供解密派生）。
  Future<String> encryptWithPasswordAad({
    required String notebookId,
    required String plaintext,
    required String password,
  }) async {
    final salt = _randomBytes(_saltLength);
    final key = await _deriveKey(password, salt);
    final keyBytes = await key.extractBytes();
    final payload = await encryptNotebookPayload(
      notebookId: notebookId,
      plaintext: plaintext,
      key: keyBytes,
    );
    final map = jsonDecode(payload) as Map<String, dynamic>;
    map['s'] = base64Encode(salt);
    return jsonEncode(map);
  }

  /// 密码模式 v4 解密：v4 AAD 优先，v3 旧数据回退（flutter_secure_storage
  /// 两步迁移：兼容期新旧并存，旧格式仅读）。
  Future<String> decryptWithPasswordAad({
    required String notebookId,
    required String encryptedJson,
    required String password,
  }) async {
    _requireInputSize(encryptedJson);
    final map = jsonDecode(encryptedJson) as Map<String, dynamic>;
    if (map['mode'] == 'payload' && map['v'] == 4) {
      final salt = base64Decode(_requireString(map, 's'));
      _requireFixedLength('盐', salt, _saltLength);
      final key = await _deriveKey(password, salt);
      final keyBytes = await key.extractBytes();
      return decryptNotebookPayload(
        notebookId: notebookId,
        encryptedJson: encryptedJson,
        key: keyBytes,
      );
    }
    return decrypt(encryptedJson, password);
  }

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
    } catch (e) {
      debugPrint('[EncryptionService] formatVersionOf 解析失败，视为旧格式: $e');
      return 2;
    }
  }
}
