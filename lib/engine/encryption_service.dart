import 'dart:convert';
import 'dart:math';

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
  static const int _pbkdf2Iterations = 100000;

  /// 派生 32 字节密钥：PBKDF2-HMAC-SHA256(密码, 随机盐, 10 万次)。
  Future<SecretKey> _deriveKey(String password, List<int> salt) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _pbkdf2Iterations,
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
      'v': 2, // 格式版本（KDF=PBKDF2 10 万次）
    });
  }

  /// 解密 [encryptedJson]；密码错误或数据损坏时抛出 [FormatException]。
  Future<String> decrypt(String encryptedJson, String password) async {
    final map = jsonDecode(encryptedJson) as Map<String, dynamic>;
    final salt = base64Decode(_requireString(map, 's'));
    final key = await _deriveKey(password, salt);
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
    });
  }

  /// 解恢复密钥信封：恢复密钥错误或信封损坏抛 [FormatException]。
  Future<List<int>> unwrapMasterKey(String envelope, String recoveryKey) async {
    final map = jsonDecode(envelope) as Map<String, dynamic>;
    final salt = base64Decode(_requireString(map, 'salt'));
    final kek = await _deriveKey(recoveryKey, salt);
    final aes = AesGcm.with256bits();
    final clear = await aes.decrypt(
      SecretBox(
        base64Decode(_requireString(map, 'ek')),
        nonce: base64Decode(_requireString(map, 'n2')),
        mac: Mac(base64Decode(_requireString(map, 'm2'))),
      ),
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

  /// 生成 [n] 字节随机数（盐/nonce）。
  static List<int> _randomBytes(int n) {
    final rng = Random.secure();
    return List<int>.generate(n, (_) => rng.nextInt(256));
  }
}
