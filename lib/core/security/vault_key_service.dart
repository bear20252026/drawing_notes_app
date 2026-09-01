import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';

/// 解锁失败（PIN 错误 / 载荷被篡改 / 数据损坏）。
///
/// fail-closed 原则：任何一种失败都不暴露主密钥，调用方按"密码错误"
/// 处理（防爆破计数归口批次③）。
class VaultUnlockException implements Exception {
  const VaultUnlockException(this.reason);

  final String reason;

  @override
  String toString() => 'VaultUnlockException($reason)';
}

/// 主密钥保险库（加密底座批次① 2026-09-01——密钥链根）。
///
/// 密钥链（OWASP M10 信封模式，复用 MediaCryptoService 既有层）：
/// ```
/// PIN --PBKDF2(60万次)--> KEK --AES-256-GCM包裹--> 主密钥 MK
///                                                        │
///                              ├─ 媒体：每笔记 DEK（既有 K_note 层）
///                              └─ 文档/索引：全盘密文化（接入批次①b/c）
/// ```
/// - MK 32 字节 CSPRNG 生成，**永不明文落盘**——磁盘上只有被 KEK 包住
///   的密文副本；重装/拷走文件无 PIN 解不开（GCM tag 即校验器）。
/// - U 盘第二副本（批次④）：MK 用外部密钥文件（U 盘）再包一层导出，
///   仅用于重置——插入 U 盘不是解锁。
/// - 单一事实来源：AEAD 加解密/随机数/KDF 全部收敛到本类 static，
///   文档编解码层（①b/c）与 U 盘副本共用同一实现。
class VaultKeyService {
  VaultKeyService({
    Future<File> Function()? vaultFileResolver,
    this.iterations = 600000,
  }) : _vaultFileResolver = vaultFileResolver ?? _defaultVaultFile;

  /// 保险库文件（应用支持目录，与 app.lock 同目录约定）。
  static Future<File> _defaultVaultFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}vault.key.json');
  }

  final Future<File> Function() _vaultFileResolver;

  Future<File> _vaultFile() => _vaultFileResolver();

  /// PBKDF2 迭代次数（与 MediaCryptoService 600k 对齐——OWASP M10）。
  /// 测试可注入小值提速。
  final int iterations;

  static const String _aad = 'drawing-notes|vault|v1';
  static const String _aadSecondCopy = 'drawing-notes|vault-copy|v1';
  static const int _mkBytes = 32;
  static const int _saltBytes = 16;

  /// 解锁后的主密钥（内存持有；锁定时 fillRange 擦除——D-2 模式）。
  List<int>? _masterKey;

  bool get isUnlocked => _masterKey != null;

  /// 主密钥副本（注入给文档/媒体解密层用；每次返回独立拷贝，
  /// 调用方用完自行清零或交由本类 lock() 统一擦除）。未解锁抛错。
  Uint8List get masterKey {
    final key = _masterKey;
    if (key == null) {
      throw StateError('主密钥未解锁（请先 VaultKeyService.unlock）');
    }
    return Uint8List.fromList(key);
  }

  /// 保险库是否已建立（存在保险库文件）。
  Future<bool> isConfigured() async => (await _vaultFile()).existsSync();

  /// 首次建立：生成主密钥并用 PIN 包裹后落盘（原子写：tmp + rename）。
  Future<void> initialize(String pin) async {
    if (pin.isEmpty) throw ArgumentError('PIN 不能为空');
    final salt = randomBytes(_saltBytes);
    final mk = randomBytes(_mkBytes);
    final wrapped = await _wrap(pin, salt, mk);
    await _persist(salt, wrapped);
    _masterKey = mk;
  }

  /// 解锁：PIN 派生 KEK → 解包 MK。错误 PIN / 载荷篡改 → 抛
  /// [VaultUnlockException]（GCM tag 校验，fail-closed）。
  Future<void> unlock(String pin) async {
    final file = await _vaultFile();
    if (!file.existsSync()) {
      throw const VaultUnlockException('保险库不存在（尚未设置密码）');
    }
    final Map<String, dynamic> doc;
    try {
      doc = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    } on FormatException {
      throw const VaultUnlockException('保险库数据损坏');
    }
    final salt = base64Decode(doc['salt'] as String);
    final wrapped = base64Decode(doc['wrapped'] as String);
    final kek = await deriveKek(pin, salt, iterations);
    try {
      final mk = await aeadDecrypt(kek, wrapped, _aad.codeUnits);
      _masterKey = mk;
    } on SecretBoxAuthenticationError {
      throw const VaultUnlockException('PIN 错误或密钥载荷被篡改');
    }
  }

  /// 修改 PIN：旧 PIN 验证通过后换盐重包裹（主密钥不变——旧密文无需迁移）。
  Future<void> changePin({
    required String oldPin,
    required String newPin,
  }) async {
    final file = await _vaultFile();
    if (!file.existsSync()) {
      throw const VaultUnlockException('保险库不存在（尚未设置密码）');
    }
    final doc = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final oldSalt = base64Decode(doc['salt'] as String);
    final oldWrapped = base64Decode(doc['wrapped'] as String);
    final List<int> mk;
    try {
      mk = await aeadDecrypt(
        await deriveKek(oldPin, oldSalt, iterations),
        oldWrapped,
        _aad.codeUnits,
      );
    } on SecretBoxAuthenticationError {
      throw const VaultUnlockException('旧 PIN 错误或密钥载荷被篡改');
    }
    final newSalt = randomBytes(_saltBytes);
    final newWrapped = await _wrap(newPin, newSalt, mk);
    await _persist(newSalt, newWrapped);
    _masterKey = mk;
  }

  /// 锁定：内存主密钥主动擦除（fillRange 清零——D-2 模式）。
  void lock() {
    final key = _masterKey;
    if (key != null) key.fillRange(0, key.length, 0);
    _masterKey = null;
  }

  /// 销毁保险库（U 盘重置后重设密码前的清理态——文件删除 + 内存清零）。
  Future<void> wipe() async {
    lock();
    final file = await _vaultFile();
    if (file.existsSync()) {
      try {
        await file.delete();
      } catch (_) {
        // 删除失败忽略（下次 initialize 覆盖写入）。
      }
    }
  }

  // ---------- U 盘第二副本（批次④接线用，此处实现核心加解密） ----------

  /// 用外部密钥（U 盘密钥文件内容派生）包裹主密钥导出第二副本。
  /// 仅用于重置通道——拿到副本 ≠ 拿到解锁态。
  static Future<Uint8List> exportSecondCopy({
    required List<int> masterKey,
    required List<int> externalKey,
  }) {
    return aeadEncrypt(externalKey, masterKey, _aadSecondCopy.codeUnits);
  }

  /// 用外部密钥解包第二副本，恢复主密钥（U 盘重置通道）。
  static Future<List<int>> importSecondCopy({
    required List<int> secondCopy,
    required List<int> externalKey,
  }) {
    return aeadDecrypt(externalKey, secondCopy, _aadSecondCopy.codeUnits);
  }

  // ---------- AEAD / KDF 单一来源（文档编解码层共用） ----------

  /// AES-256-GCM 加密。载荷布局 = [nonce(12), cipherText, tag(16)]。
  static Future<Uint8List> aeadEncrypt(
    List<int> key,
    List<int> plain,
    List<int> aad,
  ) async {
    final aes = AesGcm.with256bits();
    final nonce = randomBytes(12);
    final box = await aes.encrypt(
      plain,
      secretKey: SecretKey(key),
      nonce: nonce,
      aad: aad,
    );
    return Uint8List.fromList([...nonce, ...box.cipherText, ...box.mac.bytes]);
  }

  /// AES-256-GCM 解密。tag 校验失败抛 [SecretBoxAuthenticationError]。
  static Future<List<int>> aeadDecrypt(
    List<int> key,
    List<int> payload,
    List<int> aad,
  ) async {
    if (payload.length <= 28) throw const VaultUnlockException('密文长度不合法');
    final aes = AesGcm.with256bits();
    final clear = await aes.decrypt(
      SecretBox(
        payload.sublist(12, payload.length - 16),
        nonce: payload.sublist(0, 12),
        mac: Mac(payload.sublist(payload.length - 16)),
      ),
      secretKey: SecretKey(key),
      aad: aad,
    );
    return clear;
  }

  /// PBKDF2-HMAC-SHA256 密钥派生（与 MediaCryptoService 参数对齐）。
  static Future<List<int>> deriveKek(
    String pin,
    List<int> salt,
    int iterations,
  ) async {
    final key = await Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    ).deriveKeyFromPassword(password: pin, nonce: salt);
    return key.extractBytes();
  }

  /// CSPRNG 随机字节（盐 / 主密钥 / nonce 统一入口）。
  static Uint8List randomBytes(int length) {
    final rng = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => rng.nextInt(256)),
    );
  }

  // ---------- 内部 ----------

  Future<List<int>> _wrap(String pin, List<int> salt, List<int> mk) async {
    final kek = await deriveKek(pin, salt, iterations);
    return aeadEncrypt(kek, mk, _aad.codeUnits);
  }

  /// 原子落盘：写 tmp 后 rename（与存储层写成功回调约定一致——
  /// rename 原子语义保证断电不留半截保险库）。
  Future<void> _persist(List<int> salt, List<int> wrapped) async {
    final file = await _vaultFile();
    final doc = jsonEncode({
      'v': 1,
      'kdf': 'PBKDF2-HMAC-SHA256',
      'iter': iterations,
      'salt': base64Encode(salt),
      'wrapped': base64Encode(wrapped),
    });
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(doc, flush: true);
    await tmp.rename(file.path);
  }
}
