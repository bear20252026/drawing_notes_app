import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
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
/// - U 盘钥匙槽位（批次④，LUKS/BitLocker 多保护器模式）：保险库 v2 为
///   双槽结构——槽 1 PIN 包裹、槽 2 U 盘钥匙文件（32B CSPRNG）包裹，
///   同一主密钥两把钥匙；忘 PIN 时插 U 盘免旧 PIN 重设。主密钥副本
///   不出设备，U 盘上只有随机钥匙文件（password_reset_disk.key）。
/// - 单一事实来源：AEAD 加解密/随机数/KDF 全部收敛到本类 static，
///   文档编解码层（①b/c）与 U 盘副本共用同一实现。
class VaultKeyService {
  VaultKeyService({
    Future<File> Function()? vaultFileResolver,
    this.iterations = 600000,
  }) : _vaultFileResolver = vaultFileResolver ?? _defaultVaultFile;

  // ---- 共享实例（批次①c：无 context 场景的密钥访问点） ----
  //
  // 图片渲染（EncryptedFileImage / DocumentImageCache）深埋在绘制管线里，
  // 拿不到组合根的实例——与 MediaCryptoService.instance 同模式，提供全局
  // 访问点。组合根在 initState 显式 registerShared()，测试可注册隔离实例。
  static VaultKeyService? _shared;

  static VaultKeyService? get shared => _shared;

  /// 注册为应用级共享实例（组合根调用；后注册覆盖前者）。
  void registerShared() => _shared = this;

  /// 共享实例的解锁态主密钥；未注册 / 未解锁返回 null（fail-closed）。
  static Uint8List? get sharedMasterKeyOrNull {
    final s = _shared;
    if (s == null || !s.isUnlocked) return null;
    return s.masterKey;
  }

  /// 仅测试注入：绕过 KDF 直接设置内存主密钥（不落盘）。
  @visibleForTesting
  void debugInjectMasterKey(List<int> key) => _masterKey = List<int>.of(key);

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

  /// U 盘钥匙槽位（批次④）：槽 2 用 U 盘密钥文件（32B CSPRNG）直接作
  /// AEAD 密钥包裹主密钥——LUKS/BitLocker「多保护器」模式（调研结论
  /// 2026-09-01）：主密钥副本不出设备，U 盘上只有随机钥匙文件。
  static const String _aadUsbSlot = 'drawing-notes|vault-usb|v1';
  static const String _slotPin = 'pin';
  static const String _slotUsb = 'usb';
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
  /// 批次④：直接写 v2 槽位结构（单 PIN 槽；U 盘槽位由绑定流程追加）。
  Future<void> initialize(String pin) async {
    if (pin.isEmpty) throw ArgumentError('PIN 不能为空');
    final salt = randomBytes(_saltBytes);
    final mk = randomBytes(_mkBytes);
    final wrapped = await _wrap(pin, salt, mk);
    await _persistSlots(
      pinSlot: {
        'type': _slotPin,
        'salt': base64Encode(salt),
        'wrapped': base64Encode(wrapped),
      },
    );
    _masterKey = mk;
  }

  /// 解锁：PIN 派生 KEK → 解包 MK。错误 PIN / 载荷篡改 → 抛
  /// [VaultUnlockException]（GCM tag 校验，fail-closed）。
  ///
  /// 批次④：v1（单 PIN 槽顶层字段）与 v2（slots 数组）均兼容读取；
  /// v1 解锁成功后惰性迁移为 v2 双槽结构（等价改写，不重新 KDF）。
  Future<void> unlock(String pin) async {
    final doc = await _readDoc();
    if (doc == null) {
      throw const VaultUnlockException('保险库不存在（尚未设置密码）');
    }
    final (pinSlot, usbSlot) = _slotsOf(doc);
    if (pinSlot == null) {
      throw const VaultUnlockException('保险库缺少 PIN 槽位');
    }
    final salt = base64Decode(pinSlot['salt'] as String);
    final wrapped = base64Decode(pinSlot['wrapped'] as String);
    final kek = await deriveKek(pin, salt, iterations);
    try {
      final mk = await aeadDecrypt(kek, wrapped, _aad.codeUnits);
      _masterKey = mk;
    } on SecretBoxAuthenticationError {
      throw const VaultUnlockException('PIN 错误或密钥载荷被篡改');
    }
    // v1 → v2 惰性迁移（批次④）：首解成功后升级为槽位结构。
    if (doc['v'] != 2) {
      try {
        await _persistSlots(
          pinSlot: {
            'type': _slotPin,
            'salt': pinSlot['salt'],
            'wrapped': pinSlot['wrapped'],
          },
          usbSlot: usbSlot,
        );
      } catch (_) {
        // 迁移失败不阻塞解锁（下次成功解锁再试）；旧文件仍可读。
      }
    }
  }

  /// 修改 PIN：旧 PIN 验证通过后换盐重包裹（主密钥不变——旧密文无需迁移）。
  /// 批次④：U 盘钥匙槽位原样保留（它包的是主密钥，与 PIN 无关）。
  Future<void> changePin({
    required String oldPin,
    required String newPin,
  }) async {
    final doc = await _readDoc();
    if (doc == null) {
      throw const VaultUnlockException('保险库不存在（尚未设置密码）');
    }
    final (pinSlot, usbSlot) = _slotsOf(doc);
    if (pinSlot == null) {
      throw const VaultUnlockException('保险库缺少 PIN 槽位');
    }
    final oldSalt = base64Decode(pinSlot['salt'] as String);
    final oldWrapped = base64Decode(pinSlot['wrapped'] as String);
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
    await _persistSlots(
      pinSlot: {
        'type': _slotPin,
        'salt': base64Encode(newSalt),
        'wrapped': base64Encode(newWrapped),
      },
      usbSlot: usbSlot,
    );
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

  // ---------- U 盘钥匙槽位（批次④，LUKS/BitLocker 多保护器模式） ----------
  //
  // 保险库 v2 = slots 数组：槽 1（PIN 包裹）+ 槽 2（U 盘钥匙文件包裹），
  // 两把钥匙开同一把主密钥。安全属性（与 LUKS/KeePass 一致）：
  // - 只偷 U 盘：解不开任何东西（主密钥副本不出设备）；
  // - 只偷设备：还有防爆破守卫（批次③）挡着；
  // - 设备 + U 盘都拿到：等价于本人（两件东西分放两地正是防御的全部意义）。

  /// 保险库是否已绑定 U 盘恢复钥匙（槽 2 存在即视为绑定）。
  Future<bool> hasUsbSlot() async {
    final doc = await _readDocSafely();
    if (doc == null) return false;
    return _slotsOf(doc).$2 != null;
  }

  /// 绑定 U 盘恢复钥匙：用 [externalKey]（U 盘密钥文件的 32B 内容）包裹
  /// 当前主密钥写入槽 2。要求保险库已解锁。
  Future<void> addUsbKeySlot({required List<int> externalKey}) async {
    final mk = _masterKey;
    if (mk == null) {
      throw StateError('主密钥未解锁（请先 VaultKeyService.unlock）');
    }
    if (externalKey.length != _mkBytes) {
      throw ArgumentError('外部密钥须为 $_mkBytes 字节');
    }
    final doc = await _readDoc();
    if (doc == null) {
      throw const VaultUnlockException('保险库不存在（尚未设置密码）');
    }
    final (pinSlot, _) = _slotsOf(doc);
    if (pinSlot == null) {
      throw const VaultUnlockException('保险库缺少 PIN 槽位');
    }
    final wrapped = await aeadEncrypt(externalKey, mk, _aadUsbSlot.codeUnits);
    await _persistSlots(
      pinSlot: pinSlot,
      usbSlot: {'type': _slotUsb, 'wrapped': base64Encode(wrapped)},
    );
  }

  /// 解除绑定：删除槽 2（U 盘上的钥匙文件须用户自行删除——设备侧无法触达）。
  Future<void> removeUsbKeySlot() async {
    final doc = await _readDoc();
    if (doc == null) return;
    final (pinSlot, _) = _slotsOf(doc);
    if (pinSlot == null) return;
    await _persistSlots(pinSlot: pinSlot);
  }

  /// U 盘重置（忘记 PIN 通道）：[externalKey] 解开槽 2 恢复主密钥 →
  /// 以 [newPin] 重包裹槽 1 落盘。**不需要旧 PIN**；成功后保险库处于
  /// 已解锁态。槽 2 原样保留（U 盘继续有效）。
  Future<void> resetPinWithUsbKey({
    required List<int> externalKey,
    required String newPin,
  }) async {
    if (newPin.isEmpty) throw ArgumentError('新 PIN 不能为空');
    final doc = await _readDoc();
    if (doc == null) {
      throw const VaultUnlockException('保险库不存在（尚未设置密码）');
    }
    final (pinSlot, usbSlot) = _slotsOf(doc);
    if (pinSlot == null) {
      throw const VaultUnlockException('保险库缺少 PIN 槽位');
    }
    if (usbSlot == null) {
      throw const VaultUnlockException('未绑定 U 盘恢复钥匙');
    }
    final List<int> mk;
    try {
      mk = await aeadDecrypt(
        externalKey,
        base64Decode(usbSlot['wrapped'] as String),
        _aadUsbSlot.codeUnits,
      );
    } on SecretBoxAuthenticationError {
      // fail-closed：钥匙不对 / 槽位被篡改，一律不暴露主密钥。
      throw const VaultUnlockException('U 盘恢复钥匙不匹配或已损坏');
    }
    final newSalt = randomBytes(_saltBytes);
    final newWrapped = await _wrap(newPin, newSalt, mk);
    await _persistSlots(
      pinSlot: {
        'type': _slotPin,
        'salt': base64Encode(newSalt),
        'wrapped': base64Encode(newWrapped),
      },
      usbSlot: usbSlot,
    );
    _masterKey = mk;
  }

  // ---------- U 盘第二副本（批次①预留，静态数学层） ----------

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

  /// 读取保险库 JSON（不存在返回 null；损坏抛 [VaultUnlockException]）。
  Future<Map<String, dynamic>?> _readDoc() async {
    final file = await _vaultFile();
    if (!file.existsSync()) return null;
    try {
      return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    } on FormatException {
      throw const VaultUnlockException('保险库数据损坏');
    }
  }

  /// [hasUsbSlot] 用的静默版：损坏一律返回 null（查询不抛错）。
  Future<Map<String, dynamic>?> _readDocSafely() async {
    try {
      return await _readDoc();
    } catch (_) {
      return null;
    }
  }

  /// 归一化槽位：v2 读 slots 数组；v1（顶层 salt/wrapped）映射为单 PIN 槽。
  /// 返回记录 `(pinSlot, usbSlot)`，可能为 null。
  (Map<String, dynamic>?, Map<String, dynamic>?) _slotsOf(
    Map<String, dynamic> doc,
  ) {
    if (doc['v'] == 2) {
      final slots = (doc['slots'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      Map<String, dynamic>? pin;
      Map<String, dynamic>? usb;
      for (final s in slots) {
        if (s['type'] == _slotPin) pin = s;
        if (s['type'] == _slotUsb) usb = s;
      }
      return (pin, usb);
    }
    // v1 兼容：顶层字段即 PIN 槽。
    if (doc['salt'] is String && doc['wrapped'] is String) {
      return ({'salt': doc['salt'], 'wrapped': doc['wrapped']}, null);
    }
    return (null, null);
  }

  /// 槽位结构落盘（v2 格式，原子写：tmp + rename——断电不留半截保险库）。
  Future<void> _persistSlots({
    required Map<String, dynamic>? pinSlot,
    Map<String, dynamic>? usbSlot,
  }) async {
    final file = await _vaultFile();
    final doc = jsonEncode({
      'v': 2,
      'kdf': 'PBKDF2-HMAC-SHA256',
      'iter': iterations,
      'slots': [?pinSlot, ?usbSlot],
    });
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(doc, flush: true);
    await tmp.rename(file.path);
  }
}
