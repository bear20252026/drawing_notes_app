import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'package:drawing_notes_app/core/security/kdf_params.dart';
import 'package:drawing_notes_app/core/security/vault_key_service.dart';

/// 密码保护加密服务（C3/C5，借鉴 Joplin 端到端加密理念）。
///
/// **仅支持 v5 双保护器格式（M-06 收口 2026-11-14，删除旧版）**：
/// AES-256-GCM 载荷 + Argon2id 密码槽（64MiB/t2/p2）+ 可选重置盘槽，
/// AAD 绑定文档 ID/用途（NIST SP 800-38D，防跨文档密文交换）。
/// 旧版 v2/v3（PBKDF2 无 AAD）、v4（PBKDF2+AAD）与 PBKDF2 旧槽**一律拒绝**
/// （fail-closed 抛 [FormatException]）——存量旧数据须先升级 v5 方可读取。
/// 纯 Dart 实现，离线可用，无平台依赖。
class EncryptionService {
  const EncryptionService();

  // H-07 修复（专家审计 2026-08-15）：封装输入严格校验——固定字段长度
  // （GCM nonce 12 / MAC 16 / 盐 16 / 主密钥 32）+ 输入大小上限。
  static const int _saltLength = 16;
  static const int _nonceLength = 12;
  static const int _macLength = 16;
  static const int _maxEncryptedInputBytes = 10 * 1024 * 1024; // 10MB

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

  /// 密码模式解密（**仅 v5**，M-06 收口 2026-11-14）：v5 双保护器信封。
  /// 旧版 v2/v3/v4 一律拒绝（fail-closed 抛 [FormatException]）——存量旧
  /// 数据须先升级 v5 方可读取。方法名保留 Aad 后缀以兼容生产调用点。
  Future<String> decryptWithPasswordAad({
    required String notebookId,
    required String encryptedJson,
    required String password,
  }) async {
    try {
      return await _decryptNotebookEnvelope(
        notebookId: notebookId,
        encryptedJson: encryptedJson,
        password: password,
      );
    } on SecretBoxAuthenticationError {
      // P2-2 收口（2026-10-06）：AEAD 认证失败（密码错 / 密文篡改）抛的是
      // cryptography 的 `SecretBoxAuthenticationError`，而本方法的三个生产
      // 调用点全按文档只捕 `FormatException`——
      //   · `NotebookStorage.verifyNotebookPassword`（`on FormatException → false`）
      //   · `NotebookStorage.decryptNotebook`（头注释即「密码错误抛 FormatException」）
      //   · `notebook_storage_password.dart:228` 改密前校验
      // 于是 v5 之前加密、之后没改过密的**遗留笔记本**（走 v4 分支）输错密码时，
      // 异常一路穿透到 `pin_pad.dart:207` / `unlock_sheets.dart:243`（两处都无 try），
      // 用户看到的是「点了确定没反应」——既不抖动也不提示，像按钮坏了。
      // 收口放在本方法（契约声明处）而不是底层 `_decryptPayload`：后者是加密
      // 原语，其「认证失败抛原生异常」的语义有独立单测守着
      // （`test/encryption_v4_aad_test.dart`），不该为了迁就上层契约而改宽。
      throw const FormatException('密码错误或数据已损坏');
    }
  }

  Future<String> _decryptNotebookEnvelope({
    required String notebookId,
    required String encryptedJson,
    required String password,
  }) async {
    _requireInputSize(encryptedJson);
    final map = jsonDecode(encryptedJson) as Map<String, dynamic>;
    // M-06 收口（2026-11-14）：仅 v5 双保护器信封。旧版 v2/v3/v4 一律
    // fail-closed 拒绝——存量旧数据须先升级 v5 方可读取（删除旧版支持）。
    if (!isDualProtectorEnvelope(encryptedJson)) {
      throw const FormatException('旧版加密格式已不再支持，请升级后重试');
    }
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
  ///
  /// M-06 收口（2026-11-14）：**仅 Argon2id 槽位**。旧 PBKDF2 槽位（无 kdf
  /// 字段或 kdf=pbkdf2）一律 fail-closed 拒绝（FormatException）——存量旧
  /// 槽位须先改密升级 Argon2id 方可读取（删除旧版 KDF 支持）。
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
      // 仅 Argon2id：kdf 字段缺失（旧 PBKDF2 槽位）或非 argon2id 一律拒绝。
      if (pw['kdf'] != KdfParams.kdfArgon2id) {
        throw const FormatException('旧版 KDF 槽位已不再支持，请升级后重试');
      }
      final params = KdfParams.fromSlotJson(
        pw,
        legacyDefault: KdfParams.argon2idProduction,
      );
      final wrapped = base64Decode(_requireString(pw, 'w'));
      final kek = await VaultKeyService.deriveKek(password, salt, params);
      return await VaultKeyService.aeadDecrypt(
        kek,
        wrapped,
        _slotAadV5(scope, 'pw', id),
      );
    } on FormatException {
      rethrow; // 字段畸形（篡改）/旧版拒绝保持契约
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
