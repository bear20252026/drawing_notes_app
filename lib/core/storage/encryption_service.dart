import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'package:drawing_notes_app/core/security/kek_session_cache.dart';
import 'package:drawing_notes_app/core/security/kdf_params.dart';
import 'package:drawing_notes_app/core/security/vault_key_service.dart';

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
  static const int _maxEncryptedInputBytes = 10 * 1024 * 1024; // 10MB

  /// 按格式版本选择 PBKDF2 迭代次数（无 v 字段视为旧格式 v=2）。
  static int _iterationsFor(int version) =>
      version >= 3 ? _pbkdf2IterationsCurrent : _pbkdf2IterationsLegacy;

  /// 派生 32 字节密钥：KDF 按槽位/版本声明分派（v ≤ 4 格式 = PBKDF2，
  /// 批B 起仅存量数据；v5 双保护器槽位走 Argon2id，见 _wrapSlotsV5）。
  ///
  /// N3 提速 B 方案：走 KekSessionCache（会话缓存 + isolate 后台派生；
  /// 写路径随机新盐的条目由 LRU 上限自动淘汰，调用点零特判）。
  Future<SecretKey> _deriveKey(
    String password,
    List<int> salt, {
    int iterations = _pbkdf2IterationsCurrent,
  }) async {
    final bytes = await KekSessionCache.instance.deriveKek(
      password,
      salt,
      KdfParams.pbkdf2(iterations),
    );
    return SecretKey(bytes);
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
    final key = await _deriveKey(password, salt, iterations: _iterationsFor(v));
    return _gcmDecrypt(map, key);
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
  /// v4 载荷加密核心（N2 泛化）：scope 感知 AAD。
  Future<String> _encryptPayload({
    required String scope,
    required String id,
    required String plaintext,
    required List<int> key,
  }) async {
    final aes = AesGcm.with256bits();
    final nonce = _randomBytes(12);
    final aad = _payloadAad(scope, id);
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

  /// v4 载荷解密核心（N2 泛化）：scope 感知 AAD 校验。
  Future<String> _decryptPayload({
    required String scope,
    required String id,
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
      aad: _payloadAad(scope, id),
    );
    return utf8.decode(clear);
  }

  /// 加密分页画布 v4 载荷（AAD 绑定 notebook id）。
  Future<String> encryptNotebookPayload({
    required String notebookId,
    required String plaintext,
    required List<int> key,
  }) {
    return _encryptPayload(
      scope: 'nb',
      id: notebookId,
      plaintext: plaintext,
      key: key,
    );
  }

  /// 解密分页画布 v4 载荷（AAD 校验：notebookId 不符即认证失败）。
  Future<String> decryptNotebookPayload({
    required String notebookId,
    required String encryptedJson,
    required List<int> key,
  }) {
    return _decryptPayload(
      scope: 'nb',
      id: notebookId,
      encryptedJson: encryptedJson,
      key: key,
    );
  }

  /// v4 AAD：绑定应用/文档 ID/用途/版本（NIST SP 800-38D 上下文绑定）。
  /// [scope]：'nb' = 分页画布（notebook），'bd' = 笔记（blockdoc，N2）。
  static Uint8List _payloadAad(String scope, String id) => Uint8List.fromList(
    utf8.encode(
      'drawing-notes|${scope == 'bd' ? 'blockdoc' : 'notebook'}|$id|payload|v4',
    ),
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

  /// 密码模式 v4 解密：v5 双保护器优先，v4 AAD 次之，v3/v2 旧数据回退
  /// （flutter_secure_storage 两步迁移：兼容期新旧并存，旧格式仅读）。
  Future<String> decryptWithPasswordAad({
    required String notebookId,
    required String encryptedJson,
    required String password,
  }) async {
    _requireInputSize(encryptedJson);
    final map = jsonDecode(encryptedJson) as Map<String, dynamic>;
    if (isDualProtectorEnvelope(encryptedJson)) {
      final dek = await _unwrapPasswordSlotV5(
        scope: 'nb',
        id: notebookId,
        map: map,
        password: password,
      );
      if (dek == null) {
        throw const FormatException('密码错误或数据已损坏');
      }
      return _decryptPayloadV5(scope: 'nb', id: notebookId, map: map, dek: dek);
    }
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

  // ==== v5 双保护器载荷（N4 批 3，2026-09-02 定案） ====
  //
  // 随机 32B DEK 加密 payload（沿用 v4 AAD 上下文绑定）；密码槽
  // （PBKDF2 包裹 DEK）+ 可选重置盘槽（U 盘钥匙直接包裹 DEK）各持一把
  // 钥匙开同一把 DEK——与 VaultFileCodec v3 同一套 LUKS 槽位语义。
  // 重置 = 重置盘解开 DEK → 新盐重绕密码槽，payload 密文一字节不动。
  // DEK 从密码槽可随时重解（知道密码即知 DEK）——续写/改密天然不失效
  // 已绑定的重置盘槽位。

  static const int _v5DekLength = 32;

  /// 槽位 AAD：绑定用途与文档 ID（防槽位密文跨文档移植）。
  /// [scope]：`'nb'` = 分页画布（nb-slot / `nb:<id>`），`'bd'` = 笔记（bd-slot / `bd:<id>`）。
  static Uint8List _slotAadV5(String scope, String kind, String id) =>
      Uint8List.fromList(
        utf8.encode(
          'drawing-notes|${scope == 'bd' ? 'bd-slot' : 'nb-slot'}|$kind|v5|'
          '${scope == 'bd' ? 'bd' : 'nb'}:$id',
        ),
      );

  /// 嗅探是否为 v5 双保护器载荷。
  static bool isDualProtectorEnvelope(String encryptedJson) {
    try {
      final map = jsonDecode(encryptedJson) as Map<String, dynamic>;
      return map['mode'] == 'password' && map['v'] == 5;
    } catch (_) {
      return false;
    }
  }

  /// 读取 v5 信封是否已绑定重置密码盘（不解密）。
  static bool hasUsbSlotV5(String encryptedJson) {
    if (!isDualProtectorEnvelope(encryptedJson)) return false;
    try {
      final map = jsonDecode(encryptedJson) as Map<String, dynamic>;
      final slots = map['slots'] as Map<String, dynamic>;
      return slots['usb'] != null;
    } catch (_) {
      return false;
    }
  }

  /// v5 加密核心（scope 感知）：随机 DEK 加密 payload + 密码槽包裹
  /// （可选重置盘槽）。
  Future<String> _encryptWithPasswordV5({
    required String scope,
    required String id,
    required String plaintext,
    required String password,
    List<int>? usbKey,
  }) async {
    final dek = VaultKeyService.randomBytes(_v5DekLength);
    final payload = await _encryptPayload(
      scope: scope,
      id: id,
      plaintext: plaintext,
      key: dek,
    );
    final slots = await _wrapSlotsV5(
      scope: scope,
      id: id,
      dek: dek,
      password: password,
      usbKey: usbKey,
    );
    return jsonEncode({
      'mode': 'password',
      'v': 5,
      'slots': slots,
      'payload': jsonDecode(payload),
    });
  }

  /// 分页画布 v5 加密（N4 批 3）。
  Future<String> encryptWithPasswordV5({
    required String notebookId,
    required String plaintext,
    required String password,
    List<int>? usbKey,
  }) {
    return _encryptWithPasswordV5(
      scope: 'nb',
      id: notebookId,
      plaintext: plaintext,
      password: password,
      usbKey: usbKey,
    );
  }

  /// 笔记（块文档）v5 加密（N2）：与分页画布同一套双保护器语义，
  /// AAD 绑定 blockdoc id（槽位/载荷密文不可跨文档移植）。
  Future<String> encryptBlockDocPasswordV5({
    required String docId,
    required String plaintext,
    required String password,
    List<int>? usbKey,
  }) {
    return _encryptWithPasswordV5(
      scope: 'bd',
      id: docId,
      plaintext: plaintext,
      password: password,
      usbKey: usbKey,
    );
  }

  /// 生成 v5 槽位组：密码槽（KDF 包裹 DEK——批B 起新槽位 Argon2id，
  /// 槽位 JSON 自描述）+ 可选重置盘槽。
  static Future<Map<String, dynamic>> _wrapSlotsV5({
    required String scope,
    required String id,
    required List<int> dek,
    required String password,
    List<int>? usbKey,
  }) async {
    final kdf = KdfParams.newSlotDefault;
    final salt = VaultKeyService.randomBytes(_saltLength);
    final kek = await VaultKeyService.deriveKek(password, salt, kdf);
    final pwWrapped = await VaultKeyService.aeadEncrypt(
      kek,
      dek,
      _slotAadV5(scope, 'pw', id),
    );
    String? usbWrapped;
    if (usbKey != null) {
      final w = await VaultKeyService.aeadEncrypt(
        usbKey,
        dek,
        _slotAadV5(scope, 'usb', id),
      );
      usbWrapped = base64Encode(w);
    }
    return {
      'pw': {
        's': base64Encode(salt),
        ...kdf.toSlotJson(),
        'w': base64Encode(pwWrapped),
      },
      if (usbWrapped != null) 'usb': {'w': usbWrapped},
    };
  }

  /// 用密码解开密码槽取出 DEK；密码错误/信封非法返回 null。
  /// 槽位 KDF 自描述（批B）：kdf 字段缺失 = 旧 PBKDF2 槽位（it 字段）。
  static Future<List<int>?> _unwrapPasswordSlotV5({
    required String scope,
    required String id,
    required Map<String, dynamic> map,
    required String password,
  }) async {
    try {
      final slots = map['slots'] as Map<String, dynamic>;
      final pw = slots['pw'] as Map<String, dynamic>;
      final salt = base64Decode(_requireString(pw, 's'));
      _requireFixedLength('盐', salt, _saltLength);
      final KdfParams params;
      if (pw['kdf'] == null) {
        // 旧 PBKDF2 槽位（it 字段；缺失按当前迭代数兜底）。
        // P0 修复：`it` 无界——超限按字段畸形处理（FormatException →
        // 调用方统一报「密码错误或数据已损坏」，不给敌手区分口径）。
        final legacyIt = pw['it'] is int
            ? pw['it'] as int
            : _pbkdf2IterationsCurrent;
        if (legacyIt <= 0 || legacyIt > KdfParams.maxPbkdf2Iterations) {
          throw const FormatException('密码槽 KDF 迭代数不合法');
        }
        params = KdfParams.pbkdf2(legacyIt);
      } else {
        params = KdfParams.fromSlotJson(
          pw,
          legacyDefault: KdfParams.pbkdf2(_pbkdf2IterationsCurrent),
        );
      }
      final wrapped = base64Decode(_requireString(pw, 'w'));
      final kek = await VaultKeyService.deriveKek(password, salt, params);
      return await VaultKeyService.aeadDecrypt(
        kek,
        wrapped,
        _slotAadV5(scope, 'pw', id),
      );
    } on FormatException {
      rethrow; // 字段畸形（篡改）保持契约
    } catch (_) {
      return null; // 密码错误（AEAD 认证失败）
    }
  }

  /// 用 DEK 解密 v5 payload（复用 v4 AAD 上下文）。
  Future<String> _decryptPayloadV5({
    required String scope,
    required String id,
    required Map<String, dynamic> map,
    required List<int> dek,
  }) async {
    final payload = map['payload'];
    if (payload is! Map<String, dynamic>) {
      throw const FormatException('v5 载荷缺失');
    }
    return _decryptPayload(
      scope: scope,
      id: id,
      encryptedJson: jsonEncode(payload),
      key: dek,
    );
  }

  /// v5 改密核心（scope 感知）：旧密码解出 DEK → 新盐重绕密码槽。
  /// payload 与重置盘槽 **原样保留**（LUKS 语义——改密不动数据密文）。
  /// 旧密码错误抛 [FormatException]。
  Future<String> _changePasswordV5({
    required String scope,
    required String id,
    required String encryptedJson,
    required String oldPassword,
    required String newPassword,
  }) async {
    _requireInputSize(encryptedJson);
    final map = jsonDecode(encryptedJson) as Map<String, dynamic>;
    if (!isDualProtectorEnvelope(encryptedJson)) {
      throw const FormatException('不是 v5 双保护器载荷');
    }
    final dek = await _unwrapPasswordSlotV5(
      scope: scope,
      id: id,
      map: map,
      password: oldPassword,
    );
    if (dek == null) {
      throw const FormatException('密码错误或数据已损坏');
    }
    final slots = await _wrapSlotsV5(
      scope: scope,
      id: id,
      dek: dek,
      password: newPassword,
      usbKey: null,
    );
    // 保留原重置盘槽位（DEK 未变——槽位仍然有效）。
    final oldSlots = map['slots'] as Map<String, dynamic>;
    final usb = oldSlots['usb'];
    if (usb is Map<String, dynamic>) slots['usb'] = usb;
    return jsonEncode({
      'mode': 'password',
      'v': 5,
      'slots': slots,
      'payload': map['payload'],
    });
  }

  /// 分页画布 v5 改密（N4 批 3）。
  Future<String> changeNotebookPasswordV5({
    required String notebookId,
    required String encryptedJson,
    required String oldPassword,
    required String newPassword,
  }) {
    return _changePasswordV5(
      scope: 'nb',
      id: notebookId,
      encryptedJson: encryptedJson,
      oldPassword: oldPassword,
      newPassword: newPassword,
    );
  }

  /// 笔记（块文档）v5 改密（N2）。
  Future<String> changeBlockDocPasswordV5({
    required String docId,
    required String encryptedJson,
    required String oldPassword,
    required String newPassword,
  }) {
    return _changePasswordV5(
      scope: 'bd',
      id: docId,
      encryptedJson: encryptedJson,
      oldPassword: oldPassword,
      newPassword: newPassword,
    );
  }

  /// v5 重置盘重置核心（scope 感知）：U 盘钥匙解出 DEK → 新盐重绕密码
  /// 槽。payload 与密码槽外的其他槽位原样保留。盘不匹配/未绑定/非 v5
  /// → null（fail-closed）。
  Future<String?> _resetPasswordWithUsbV5({
    required String scope,
    required String id,
    required String encryptedJson,
    required List<int> usbKey,
    required String newPassword,
  }) async {
    _requireInputSize(encryptedJson);
    final map = jsonDecode(encryptedJson) as Map<String, dynamic>;
    if (!isDualProtectorEnvelope(encryptedJson)) return null;
    List<int> dek;
    try {
      final slots = map['slots'] as Map<String, dynamic>;
      final usb = slots['usb'];
      if (usb is! Map<String, dynamic>) return null;
      final wrapped = base64Decode(_requireString(usb, 'w'));
      dek = await VaultKeyService.aeadDecrypt(
        usbKey,
        wrapped,
        _slotAadV5(scope, 'usb', id),
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      return null; // 盘不匹配（AEAD 认证失败）
    }
    final slots = await _wrapSlotsV5(
      scope: scope,
      id: id,
      dek: dek,
      password: newPassword,
      usbKey: null,
    );
    // 保留原重置盘槽位。
    final oldSlots = map['slots'] as Map<String, dynamic>;
    final usb = oldSlots['usb'];
    if (usb is Map<String, dynamic>) slots['usb'] = usb;
    return jsonEncode({
      'mode': 'password',
      'v': 5,
      'slots': slots,
      'payload': map['payload'],
    });
  }

  /// 分页画布 v5 重置盘重置（N4 批 3）。
  Future<String?> resetNotebookPasswordWithUsbV5({
    required String notebookId,
    required String encryptedJson,
    required List<int> usbKey,
    required String newPassword,
  }) {
    return _resetPasswordWithUsbV5(
      scope: 'nb',
      id: notebookId,
      encryptedJson: encryptedJson,
      usbKey: usbKey,
      newPassword: newPassword,
    );
  }

  /// 笔记（块文档）v5 重置盘重置（N2）。
  Future<String?> resetBlockDocPasswordWithUsbV5({
    required String docId,
    required String encryptedJson,
    required List<int> usbKey,
    required String newPassword,
  }) {
    return _resetPasswordWithUsbV5(
      scope: 'bd',
      id: docId,
      encryptedJson: encryptedJson,
      usbKey: usbKey,
      newPassword: newPassword,
    );
  }

  /// v5 事后绑定重置盘核心（scope 感知）：用密码解出 DEK → 追加重置盘
  /// 槽位。已绑定/密码错误/非 v5 → null 或抛 [FormatException]（密码错）。
  Future<String> _bindUsbSlotV5({
    required String scope,
    required String id,
    required String encryptedJson,
    required String password,
    required List<int> usbKey,
  }) async {
    _requireInputSize(encryptedJson);
    final map = jsonDecode(encryptedJson) as Map<String, dynamic>;
    if (!isDualProtectorEnvelope(encryptedJson)) {
      throw const FormatException('不是 v5 双保护器载荷');
    }
    if (hasUsbSlotV5(encryptedJson)) {
      throw const FormatException('已绑定重置密码盘');
    }
    final dek = await _unwrapPasswordSlotV5(
      scope: scope,
      id: id,
      map: map,
      password: password,
    );
    if (dek == null) {
      throw const FormatException('密码错误或数据已损坏');
    }
    final w = await VaultKeyService.aeadEncrypt(
      usbKey,
      dek,
      _slotAadV5(scope, 'usb', id),
    );
    final slots = map['slots'] as Map<String, dynamic>;
    slots['usb'] = {'w': base64Encode(w)};
    return jsonEncode({
      'mode': 'password',
      'v': 5,
      'slots': slots,
      'payload': map['payload'],
    });
  }

  /// 分页画布 v5 事后绑定重置盘（N4 批 3）。
  Future<String> bindNotebookUsbSlotV5({
    required String notebookId,
    required String encryptedJson,
    required String password,
    required List<int> usbKey,
  }) {
    return _bindUsbSlotV5(
      scope: 'nb',
      id: notebookId,
      encryptedJson: encryptedJson,
      password: password,
      usbKey: usbKey,
    );
  }

  /// 笔记（块文档）v5 事后绑定重置盘（N2）。
  Future<String> bindBlockDocUsbSlotV5({
    required String docId,
    required String encryptedJson,
    required String password,
    required List<int> usbKey,
  }) {
    return _bindUsbSlotV5(
      scope: 'bd',
      id: docId,
      encryptedJson: encryptedJson,
      password: password,
      usbKey: usbKey,
    );
  }

  /// [encryptAndSave] 续写辅助：密码解出 DEK（错误返回 null，不抛）。
  Future<List<int>?> unwrapPasswordSlotForRewrap({
    required String notebookId,
    required String encryptedJson,
    required String password,
  }) async {
    _requireInputSize(encryptedJson);
    final map = jsonDecode(encryptedJson) as Map<String, dynamic>;
    return _unwrapPasswordSlotV5(
      scope: 'nb',
      id: notebookId,
      map: map,
      password: password,
    );
  }

  /// [encryptAndSave] 续写辅助：复用 DEK 与既有槽位组，仅重生成 payload
  /// 密文（DEK 不变 → 重置盘槽位继续有效——LUKS 槽位语义）。
  Future<String> rewrapPayloadV5({
    required String notebookId,
    required Map<String, dynamic> map,
    required List<int> dek,
    required String plaintext,
  }) {
    return _rewrapPayloadV5(
      scope: 'nb',
      id: notebookId,
      map: map,
      dek: dek,
      plaintext: plaintext,
    );
  }

  /// 笔记（块文档）续写辅助：密码解出 DEK（N2；错误返回 null，不抛）。
  Future<List<int>?> unwrapBlockDocPasswordSlotForRewrap({
    required String docId,
    required String encryptedJson,
    required String password,
  }) async {
    _requireInputSize(encryptedJson);
    final map = jsonDecode(encryptedJson) as Map<String, dynamic>;
    return _unwrapPasswordSlotV5(
      scope: 'bd',
      id: docId,
      map: map,
      password: password,
    );
  }

  /// 笔记（块文档）续写辅助：复用 DEK 与既有槽位组，仅重生成 payload
  /// 密文（N2；DEK 不变 → 重置盘槽位继续有效）。
  Future<String> rewrapBlockDocPayloadV5({
    required String docId,
    required Map<String, dynamic> map,
    required List<int> dek,
    required String plaintext,
  }) {
    return _rewrapPayloadV5(
      scope: 'bd',
      id: docId,
      map: map,
      dek: dek,
      plaintext: plaintext,
    );
  }

  /// rewrap 核心（scope 感知）。
  Future<String> _rewrapPayloadV5({
    required String scope,
    required String id,
    required Map<String, dynamic> map,
    required List<int> dek,
    required String plaintext,
  }) async {
    final payload = await _encryptPayload(
      scope: scope,
      id: id,
      plaintext: plaintext,
      key: dek,
    );
    return jsonEncode({
      'mode': 'password',
      'v': 5,
      'slots': map['slots'],
      'payload': jsonDecode(payload),
    });
  }

  // ==== 笔记（块文档）v5 解密（N2） ====

  /// 笔记 v5 解密（密码模式）：密码错/非 v5 抛 [FormatException]。
  /// 笔记文件密码仅存在 v5 格式（无旧格式回退路径）。
  Future<String> decryptBlockDocPassword({
    required String docId,
    required String encryptedJson,
    required String password,
  }) async {
    _requireInputSize(encryptedJson);
    final map = jsonDecode(encryptedJson) as Map<String, dynamic>;
    if (!isDualProtectorEnvelope(encryptedJson)) {
      throw const FormatException('不是 v5 双保护器载荷');
    }
    final dek = await _unwrapPasswordSlotV5(
      scope: 'bd',
      id: docId,
      map: map,
      password: password,
    );
    if (dek == null) {
      throw const FormatException('密码错误或数据已损坏');
    }
    try {
      return await _decryptPayloadV5(
        scope: 'bd',
        id: docId,
        map: map,
        dek: dek,
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      // payload 内层 AEAD 认证失败（密文被篡改）→ 统一契约。
      throw const FormatException('载荷认证失败（数据已损坏）');
    }
  }

  /// 笔记 v5 解密（会话 DEK 模式）：自动保存/续写零 PBKDF2 路径。
  /// 非法信封/DEK 不匹配抛 [FormatException]。
  Future<String> decryptBlockDocPayloadWithDek({
    required String docId,
    required String encryptedJson,
    required List<int> dek,
  }) async {
    _requireInputSize(encryptedJson);
    final map = jsonDecode(encryptedJson) as Map<String, dynamic>;
    if (!isDualProtectorEnvelope(encryptedJson)) {
      throw const FormatException('不是 v5 双保护器载荷');
    }
    try {
      return await _decryptPayloadV5(
        scope: 'bd',
        id: docId,
        map: map,
        dek: dek,
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      // AEAD 认证失败（DEK 不匹配/密文被篡改）→ 统一契约。
      throw const FormatException('DEK 认证失败（载荷损坏或 DEK 不匹配）');
    }
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
    } catch (_) {
      return 2;
    }
  }
}
