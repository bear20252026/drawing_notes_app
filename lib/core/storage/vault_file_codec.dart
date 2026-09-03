import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'package:drawing_notes_app/core/security/kdf_params.dart';
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

/// v3 解锁结果：明文 + 会话续用密钥材料（DEK 复用、USB 槽位原样保留）。
class VaultFileV3Unlock {
  const VaultFileV3Unlock(this.plain, this.dek, this.usbWrapped);

  final Uint8List plain;

  /// 数据加密密钥（会话缓存后写入复用，保持重置盘槽位有效）。
  final Uint8List dek;

  /// 重置盘槽位密文（信封未绑定重置盘时为 null）。
  final Uint8List? usbWrapped;
}

/// v3 重绕结果：新信封字节 + 会话续用密钥材料。
class VaultFileV3Rewrap {
  const VaultFileV3Rewrap(this.blob, this.dek, this.usbWrapped);

  final Uint8List blob;
  final Uint8List dek;
  final Uint8List? usbWrapped;
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
/// v3（N4 批 2 双保护器信封——文件密码可被重置密码盘重置）：
///   "DNV"(3B 魔数) | 0x03 | jsonLen(u32 BE) | JSON 槽位头
///                  | AES-256-GCM 载荷 [nonce(12) | cipherText | tag(16)]
///   JSON 槽位头 = {"v":3,"slots":[
///     {"type":"pw","salt":b64, KDF字段, "wrapped":b64},   // 密码槽：包裹 DEK
///     {"type":"usb","wrapped":b64}?                       // 重置盘槽（可选）
///   ]}
///   KDF 字段（批B，LUKS2 每槽位独立 KDF 语义——槽位自描述，信封结构
///   不变故版本字节不动）：
///     新写入: {"kdf":"argon2id","m":65536,"t":2,"p":2}
///     旧数据: {"iter":n}（无 kdf 字段 = PBKDF2，批B 前产物）
/// ```
/// 设计要点：
/// - 明文 JSON 以 `{` 开头、PNG 以魔数开头，攻击者一眼可辨；`DNV` 头让
///   加密文件同样可辨识——被辨识≠被读取，GCM tag 保证一个字节都改不动；
/// - AAD 绑定文件用途与 ID（`drawing-notes|file|v1|doc:<id>`），
///   防止密文在不同文件间移植（swap 攻击）；
/// - v1 密钥 = 保险库主密钥（与开屏密码同源）；v2 密钥 = PBKDF2(文件密码,
///   salt) 现场派生——主密钥泄露不等于单文件密码文件可读（层级独立）；
/// - v3 引入随机 32B DEK 加密载荷（载荷 AAD 与 v1/v2 同串），密码槽 /
///   重置盘槽各自包裹同一把 DEK（LUKS/BitLocker 多保护器模式）：忘记
///   密码时插重置盘解开 DEK → 新盐重绕密码槽，**载荷密文一字节不动**；
///   槽位 AAD 绑定 context，防止槽位被移植到其他文件；
/// - 加解密统一走 [VaultKeyService] statics（单一事实来源，
///   与保险库/媒体层共用同一套 AEAD/PBKDF2 实现）。
abstract final class VaultFileCodec {
  /// 魔数 "DNV"（Drawing Notes Vault）。
  static const int _m0 = 0x44, _m1 = 0x4E, _m2 = 0x56;

  static const int _version = 1;
  static const int _passwordVersion = 2;
  static const int _v3Version = 3;
  static const int _headerBytes = 4;

  /// v2 头部长度：魔数(3)+版本(1)+salt(16)+iterations(4)。
  static const int _passwordHeaderBytes = 4 + 16 + 4;

  /// v3 头部长度：魔数(3)+版本(1)+jsonLen(4)。
  static const int _v3HeaderBytes = 8;

  /// v3 槽位类型标记（与保险库 `_slotPin/_slotUsb` 命名对齐）。
  static const String _slotPw = 'pw';
  static const String _slotUsb = 'usb';

  /// v3 DEK / 重置盘钥匙长度（AES-256）。
  static const int _dekBytes = 32;
  static const int _v3SaltBytes = 16;

  /// 单文件密码 PBKDF2 迭代次数（批B 前产线值——仅用于旧 v2 头部与
  /// 旧 v3 槽位读取兜底；新槽位走 Argon2id，见 [KdfParams.argon2idProduction]）。
  static const int filePasswordIterations = 600000;

  /// 嗅探字节是否为本加密信封（读路径自动分流：密文解密 / 明文兼容）。
  static bool isEncrypted(Uint8List bytes) =>
      bytes.length > _headerBytes &&
      bytes[0] == _m0 &&
      bytes[1] == _m1 &&
      bytes[2] == _m2;

  /// 嗅探是否为单文件密码信封（v2 / v3 均算——读路径据此要求会话密码）。
  static bool isPasswordEnvelope(Uint8List bytes) =>
      isEncrypted(bytes) &&
      (bytes[3] == _passwordVersion || bytes[3] == _v3Version);

  /// 嗅探是否为 v2 单文件密码信封（v2 解密路径专用——v3 结构不同）。
  static bool isPasswordEnvelopeV2(Uint8List bytes) =>
      isEncrypted(bytes) && bytes[3] == _passwordVersion;

  /// 嗅探是否为 v3 双保护器信封（N4 批 2）。
  static bool isV3Envelope(Uint8List bytes) =>
      isEncrypted(bytes) && bytes[3] == _v3Version;

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
    if (version == _passwordVersion || version == _v3Version) {
      throw const VaultFileException(
        '该文件受独立密码保护，请使用 decryptWithPassword / unlockWithPasswordV3',
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
    final key = await VaultKeyService.deriveKek(
      password,
      salt,
      KdfParams.pbkdf2(iterations),
    );
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
    if (!isPasswordEnvelopeV2(blob)) {
      throw const VaultFileException('不是 v2 单文件密码信封');
    }
    if (blob.length <= _passwordHeaderBytes) {
      throw const VaultFileException('信封长度不合法');
    }
    final salt = blob.sublist(4, 20);
    final iter = ByteData.sublistView(blob, 20, 24).getUint32(0);
    // P0 修复：v2 头部 iter 无界——`1` 瞬间爆破、`0xFFFFFFFF` 挂起 isolate。
    // 合法产线仅 100k/600k，上限取 2 倍生产值，超限 fail-closed。
    if (iter <= 0 || iter > KdfParams.maxPbkdf2Iterations) {
      throw const VaultFileException('信封 KDF 迭代数不合法');
    }
    final key = await VaultKeyService.deriveKek(
      password,
      salt,
      KdfParams.pbkdf2(iter),
    );
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

  // ================= v3 双保护器信封（N4 批 2，2026-09-02 定案） =================
  //
  // 随机 32B DEK 加密载荷；密码槽（PBKDF2 包裹 DEK）+ 可选重置盘槽（U 盘
  // 钥匙直接包裹 DEK）各持一把钥匙开同一把 DEK（LUKS/BitLocker 多保护器）。
  // 重置 = 重置盘解开 DEK → 新盐重绕密码槽，载荷密文一字节不动。
  // DEK 须按文档稳定复用（会话缓存）——否则每次保存都会作废重置盘槽位。

  /// 生成随机 DEK（setFilePassword 时调用并缓存进会话）。
  static Uint8List generateDek() => VaultKeyService.randomBytes(_dekBytes);

  /// 用重置盘钥匙包裹 DEK，产出 USB 槽位密文（设密绑定 / 事后绑定共用）。
  static Future<Uint8List> wrapUsbSlotV3({
    required List<int> usbKey,
    required Uint8List dek,
    required String aadContext,
  }) async {
    if (usbKey.length != _dekBytes) {
      throw ArgumentError('重置盘钥匙须为 $_dekBytes 字节');
    }
    return VaultKeyService.aeadEncrypt(usbKey, dek, _usbSlotAadFor(aadContext));
  }

  /// v3 信封加密：密码槽必建（批B：Argon2id KDF 字段自描述）；
  /// [dek] 传入则复用（会话续写场景，配合 [usbWrapped] 保留重置盘槽位）；
  /// [usbWrapped] 为已有 USB 槽位密文（必须包裹同一把 [dek]——传入槽位
  /// 不传 DEK 直接拒绝，防静默失效）。
  static Future<Uint8List> encryptWithPasswordV3(
    Uint8List plain,
    String password, {
    required String aadContext,
    KdfParams? kdf,
    Uint8List? dek,
    Uint8List? usbWrapped,
  }) async {
    final params = kdf ?? KdfParams.newSlotDefault;
    if (usbWrapped != null && dek == null) {
      throw ArgumentError('传入 USB 槽位必须同时传入其包裹的 DEK');
    }
    final actualDek = dek ?? generateDek();
    final salt = VaultKeyService.randomBytes(_v3SaltBytes);
    final kek = await VaultKeyService.deriveKek(password, salt, params);
    final wrapped = await VaultKeyService.aeadEncrypt(
      kek,
      actualDek,
      _pwSlotAadFor(aadContext),
    );
    final body = utf8.encode(
      jsonEncode({
        'v': 3,
        'slots': [
          {
            'type': _slotPw,
            'salt': base64Encode(salt),
            ...params.toSlotJson(),
            'wrapped': base64Encode(wrapped),
          },
          if (usbWrapped != null)
            {'type': _slotUsb, 'wrapped': base64Encode(usbWrapped)},
        ],
      }),
    );
    final payload = await VaultKeyService.aeadEncrypt(
      actualDek,
      plain,
      _aadFor(aadContext),
    );
    final len = ByteData(4)..setUint32(0, body.length);
    return Uint8List.fromList([
      _m0,
      _m1,
      _m2,
      _v3Version,
      ...len.buffer.asUint8List(),
      ...body,
      ...payload,
    ]);
  }

  /// v3 密码解锁：密码槽解出 DEK → 解密载荷；同时返回会话续用材料。
  /// 密码错误 / 载荷篡改 → 抛 [VaultFileException]。
  static Future<VaultFileV3Unlock> unlockWithPasswordV3(
    Uint8List blob,
    String password, {
    required String aadContext,
  }) async {
    final (body, payload) = _parseV3(blob);
    final (pwSlot, usbSlot) = _slotsOfV3(body);
    final salt = base64Decode(pwSlot['salt'] as String);
    final wrapped = base64Decode(pwSlot['wrapped'] as String);
    final kek = await VaultKeyService.deriveKek(
      password,
      salt,
      _paramsOfPwSlot(pwSlot),
    );
    List<int> dek;
    try {
      dek = await VaultKeyService.aeadDecrypt(
        kek,
        wrapped,
        _pwSlotAadFor(aadContext),
      );
    } on SecretBoxAuthenticationError {
      throw const VaultFileException('密码错误或密文被篡改');
    }
    final plain = await _decryptPayloadV3(dek, payload, aadContext);
    final usbWrapped = usbSlot == null
        ? null
        : base64Decode(usbSlot['wrapped'] as String);
    return VaultFileV3Unlock(
      Uint8List.fromList(plain),
      Uint8List.fromList(dek),
      usbWrapped,
    );
  }

  /// v3 重置盘解锁：U 盘钥匙从 USB 槽解出 DEK（忘记密码时的验证通道）。
  static Future<VaultFileV3Unlock> unlockWithUsbKeyV3(
    Uint8List blob,
    List<int> usbKey, {
    required String aadContext,
  }) async {
    final (body, payload) = _parseV3(blob);
    final (_, usbSlot) = _slotsOfV3(body);
    if (usbSlot == null) {
      throw const VaultFileException('该信封未绑定重置密码盘');
    }
    List<int> dek;
    try {
      dek = await VaultKeyService.aeadDecrypt(
        usbKey,
        base64Decode(usbSlot['wrapped'] as String),
        _usbSlotAadFor(aadContext),
      );
    } on SecretBoxAuthenticationError {
      throw const VaultFileException('重置密码盘不匹配或密文被篡改');
    }
    final plain = await _decryptPayloadV3(dek, payload, aadContext);
    return VaultFileV3Unlock(
      Uint8List.fromList(plain),
      Uint8List.fromList(dek),
      Uint8List.fromList(base64Decode(usbSlot['wrapped'] as String)),
    );
  }

  /// v3 重置文件密码：USB 钥匙解出 DEK → 新盐重绕密码槽（批B：新槽位
  /// Argon2id——旧 PBKDF2 槽位借此懒升级）。**载荷密文与 USB 槽位字节
  /// 原样保留**（LUKS 同款），旧密文无需迁移；U 盘继续有效。
  static Future<VaultFileV3Rewrap> rewrapPasswordSlotV3(
    Uint8List blob,
    List<int> usbKey,
    String newPassword, {
    required String aadContext,
    KdfParams? kdf,
  }) async {
    final params = kdf ?? KdfParams.newSlotDefault;
    final unlock = await unlockWithUsbKeyV3(
      blob,
      usbKey,
      aadContext: aadContext,
    );
    final (parsedBody, payload) = _parseV3(blob);
    final (_, usbSlot) = _slotsOfV3(parsedBody);
    final newSalt = VaultKeyService.randomBytes(_v3SaltBytes);
    final kek = await VaultKeyService.deriveKek(newPassword, newSalt, params);
    final newWrapped = await VaultKeyService.aeadEncrypt(
      kek,
      unlock.dek,
      _pwSlotAadFor(aadContext),
    );
    final body = utf8.encode(
      jsonEncode({
        'v': 3,
        'slots': [
          {
            'type': _slotPw,
            'salt': base64Encode(newSalt),
            ...params.toSlotJson(),
            'wrapped': base64Encode(newWrapped),
          },
          if (usbSlot != null)
            {'type': _slotUsb, 'wrapped': base64Encode(unlock.usbWrapped!)},
        ],
      }),
    );
    final len = ByteData(4)..setUint32(0, body.length);
    final newBlob = Uint8List.fromList([
      _m0,
      _m1,
      _m2,
      _v3Version,
      ...len.buffer.asUint8List(),
      ...body,
      ...payload,
    ]);
    return VaultFileV3Rewrap(newBlob, unlock.dek, unlock.usbWrapped);
  }

  /// 该 v3 信封是否已绑定重置密码盘（读头部 JSON，不解密）。
  static bool hasUsbSlotV3(Uint8List blob) {
    try {
      final (body, _) = _parseV3(blob);
      return _slotsOfV3(body).$2 != null;
    } on VaultFileException {
      return false;
    }
  }

  static Future<Uint8List> _decryptPayloadV3(
    List<int> dek,
    Uint8List payload,
    String aadContext,
  ) async {
    try {
      return Uint8List.fromList(
        await VaultKeyService.aeadDecrypt(dek, payload, _aadFor(aadContext)),
      );
    } on SecretBoxAuthenticationError {
      throw const VaultFileException('密钥不匹配或密文被篡改');
    }
  }

  /// 解析 v3 头部：返回 (JSON body, 载荷密文)。结构不合法抛
  /// [VaultFileException]（fail-closed）。
  static (Map<String, dynamic>, Uint8List) _parseV3(Uint8List blob) {
    if (!isV3Envelope(blob)) {
      throw const VaultFileException('不是 v3 密码信封');
    }
    if (blob.length <= _v3HeaderBytes) {
      throw const VaultFileException('信封长度不合法');
    }
    final jsonLen = ByteData.sublistView(blob, 4, 8).getUint32(0);
    // P0 修复：槽位 JSON 头部 1MB 上限（合法 <1KB）——防畸形大长度
    // 触发大内存 sublist/decode（OOM 放大）。
    if (jsonLen == 0 ||
        jsonLen > 1048576 ||
        _v3HeaderBytes + jsonLen >= blob.length) {
      throw const VaultFileException('信封头部长度不合法');
    }
    Map<String, dynamic> body;
    try {
      body =
          jsonDecode(utf8.decode(blob.sublist(8, 8 + jsonLen)))
              as Map<String, dynamic>;
    } on FormatException {
      throw const VaultFileException('信封头部 JSON 损坏');
    }
    return (body, blob.sublist(_v3HeaderBytes + jsonLen));
  }

  /// v3 槽位归一：返回 (密码槽, 重置盘槽)；密码槽缺失抛
  /// [VaultFileException]。
  static (Map<String, dynamic>, Map<String, dynamic>?) _slotsOfV3(
    Map<String, dynamic> body,
  ) {
    final slots = (body['slots'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    Map<String, dynamic>? pw;
    Map<String, dynamic>? usb;
    for (final s in slots) {
      if (s['type'] == _slotPw) pw = s;
      if (s['type'] == _slotUsb) usb = s;
    }
    if (pw == null) {
      throw const VaultFileException('信封缺少密码槽位');
    }
    if (pw['salt'] is! String || pw['wrapped'] is! String) {
      throw const VaultFileException('密码槽位字段不合法');
    }
    // KDF 字段校验（批B）：kdf 字段缺失 = 批B 前数据，iter 必填；
    // 存在则必须完整合法（argon2id m/t/p 或 pbkdf2 iter）。
    if (pw['kdf'] == null && pw['iter'] is! int) {
      throw const VaultFileException('密码槽位缺少 KDF 信息');
    }
    _paramsOfPwSlot(pw);
    return (pw, usb);
  }

  /// 密码槽 KDF 参数解析（槽位自描述）。字段畸形抛 [VaultFileException]
  /// （fail-closed——由 [_slotsOfV3] 预检后调用，此处仅防越界）。
  static KdfParams _paramsOfPwSlot(Map<String, dynamic> pwSlot) {
    try {
      // P0 修复：批B 前旧槽位 `iter` 同样无界——先封顶再进解析
      //（fromSlotJson 不校验 legacyDefault 本身）。
      final legacyIter = pwSlot['iter'] is int
          ? pwSlot['iter'] as int
          : filePasswordIterations;
      if (legacyIter <= 0 || legacyIter > KdfParams.maxPbkdf2Iterations) {
        throw const VaultFileException('密码槽 KDF 字段不合法');
      }
      return KdfParams.fromSlotJson(
        pwSlot,
        legacyDefault: KdfParams.pbkdf2(legacyIter),
      );
    } on ArgumentError {
      throw const VaultFileException('密码槽 KDF 字段不合法');
    }
  }

  static List<int> _aadFor(String context) =>
      'drawing-notes|file|v1|$context'.codeUnits;

  /// 密码槽 AAD：绑定 context——槽位不可移植到其他文件（swap 攻击面）。
  static List<int> _pwSlotAadFor(String context) =>
      'drawing-notes|file-slot|pw|v3|$context'.codeUnits;

  /// 重置盘槽 AAD：与保险库 `_aadUsbSlot` 命名同族（`usb|v1` 格式稳定，
  /// 与开屏密码槽位钥匙文件完全通用——同一把重置盘）。
  static List<int> _usbSlotAadFor(String context) =>
      'drawing-notes|file-slot|usb|v1|$context'.codeUnits;

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
