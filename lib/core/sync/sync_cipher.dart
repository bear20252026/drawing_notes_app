// 由 Claude 团队生成 | Drawing Notes App
// WebDAV 同步端到端加密（P4-A1）：纯逻辑密码模块。
// 复用 cryptography（AES-256-GCM）+ crypto（HMAC-SHA256），无新依赖。
// 纯 Dart，无 flutter/io/controller/storage/drawing 依赖（dart:isolate 不算）。

import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:meta/meta.dart';

import 'package:drawing_notes_app/core/security/kdf_params.dart';

import 'package:drawing_notes_app/core/security/kek_session_cache.dart';
import 'package:drawing_notes_app/core/utils/error_code.dart';

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

/// 解密认证失败专用异常（修复 1②）。
///
/// 仍是 [FormatException]（既有调用方与测试的 `on FormatException` /
/// `throwsFormatException` 口径不变），但类型可判别：GCM 认证失败意味着
/// 「密钥或 AAD 与密文不匹配」，对同一密钥+同一密文是**确定性**结果，
/// 退避重试永远不可能让它成功——与网络抖动/服务器 5xx 必须分开处理，
/// 否则一轮口令错配会被当成毒丸反复消耗，并被泛化成「检查网络」。
///
/// 消息为本地静态构造，不含口令、密钥、docId 或任何远端原文（脱敏红线）。
class SyncKeyMismatchException extends FormatException implements CodedFailure {
  @override
  String get errorCode => 'sync_key_mismatch';
  const SyncKeyMismatchException([super.message = defaultKeyMismatchMessage]);

  /// 与原 `_decrypt` 抛出的文案逐字一致（不改既有可观测行为）。
  static const String defaultKeyMismatchMessage = '同步数据认证失败：AAD 不符或密钥错误';
}

/// 恒等加密器（**仅测试用**）：全部透传，保现有行为与测试不变。
///
/// H2 修复（2026-11-11）：本类曾是从 [SyncController._buildCipher] 可达的
/// 生产路径——盐/口令为空时静默退化为明文透传，是 fail-open 陷阱。现：
/// - 标注 `@visibleForTesting`：analyzer 会在生产代码引用它时报错，
///   把「明文同步」从默认降级路径变为编译期不可达；
/// - 生产装配侧（`_buildCipher`）对空盐/空口令改为**抛异常**（fail-closed），
///   不再回落 Noop；
/// - [SyncService] 构造另加断言，作为纵深防御——即便未来有人绕过
///   analyzer 引入 Noop，运行时也会当场拒绝。
///
/// 测试仍在大量使用它（明文传输是测试的便利，不是产品行为），故类本体
/// 保留，仅切断其生产可达性。
@visibleForTesting
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
/// `{"mode":"sync-doc"|"sync-manifest","v":2,"n":base64(nonce),"c":base64(cipherText),"m":base64(mac)}`
///
/// **信封版本 v2（2026-11-10）**：同步主密钥派生升级为 Argon2id（见
/// [deriveMasterKey]），与 v1（PBKDF2 时代）信封不兼容——解密侧强制校验
/// `v == 2`，旧信封一律拒绝（fail-closed，且归入不可重试的密钥错配类）。
///
/// **v1 → v2 迁移（H3 修复，2026-11）**：旧信封不是只能「重新配置口令全量
/// 重传」——[migrateSyncDocumentEnvelopeV1ToV2] /
/// [migrateSyncManifestEnvelopeV1ToV2] 用旧口令派生 PBKDF2 密钥（
/// [deriveMasterKeyV1]）解开 v1 信封，再用当前 Argon2id 密钥重封。
/// 生产解密路径仍然只认 v2，迁移是**独立的、用户主动触发**的事件，不影
/// 响 fail-closed 口径。
class AesSyncCipher implements SyncCipher {
  AesSyncCipher({required this.key, int? isolateThreshold})
    : assert(key.length == 32, '主密钥必须 32 字节'),
      _isolateThreshold = isolateThreshold ?? isolateCodecThreshold;

  /// 32 字节主密钥。
  final List<int> key;

  /// 本实例的 isolate 门限（缺省 [isolateCodecThreshold]）。测试用它把
  /// **同一份字节**分别逼上主 isolate / worker isolate 两条路径，验证两侧
  /// 产出可互相解回；生产调用点不传（阈值口径单一事实来源仍是常量）。
  final int _isolateThreshold;

  static const int _nonceLength = 12;
  static const int _macLength = 16;

  /// 线格式版本：v2 = Argon2id 派生时代；v1 = PBKDF2 时代（已不兼容，
  /// 解密侧拒绝）。
  static const int _wireVersion = 2;

  // AAD 上下文常量。
  static const _docAadPrefix = 'drawing-notes|sync|doc|';
  static const _docAadSuffix = '|v1';
  static const _manifestAad = 'drawing-notes|sync|manifest|v1';
  static const _nameHmacContext = 'drawing-notes|sync|name|';

  /// 文档 AAD：绑定 docId。
  ///
  /// 静态而非实例：v1→v2 迁移工具要用**同一份构造**（AAD 必须逐字一致，
  /// 各抄一份迟早漂），而迁移工具在本类之外。
  static Uint8List _docAadBytes(String docId) =>
      Uint8List.fromList(utf8.encode('$_docAadPrefix$docId$_docAadSuffix'));

  /// 达阈值载荷的 AES 下沉 isolate 的门限（修复 2，本仓「大载荷才进
  /// isolate」口径）：一次同步要逐文档加解密，数十/数百条笔记时纯 Dart
  /// AES 连续占住主 isolate，UI 掉帧甚至假死——与 NoteBlockDocStore
  /// 的 `_isolateCodecThreshold`（32 KiB）同一形态的载荷（JSON 文档字节），
  /// 故取同值；低于它时 isolate 往返（spawn + 字节拷贝）开销大于收益，
  /// 留在主 isolate（对照 StorageService.isolateSealThreshold 的 64 KiB，
  /// 本域载荷更小、更密，取更低的文档侧阈值宁可早进 isolate 不漏大文档）。
  static const int isolateCodecThreshold = 32 * 1024;

  @override
  String remotePath(String docId) {
    // HMAC-SHA256(key, context|docId) → 小写 hex（64 字符）。确定性、不可逆。
    final hmac = crypto.Hmac(crypto.sha256, key);
    final digest = hmac.convert(utf8.encode('$_nameHmacContext$docId'));
    return digest.toString(); // 小写 hex
  }

  @override
  Future<Uint8List> encryptDocumentBytes(Uint8List plain, String docId) async {
    return _encrypt(plain, _docAadBytes(docId), 'sync-doc');
  }

  @override
  Future<Uint8List> decryptDocumentBytes(Uint8List cipher, String docId) async {
    return _decrypt(cipher, _docAadBytes(docId), 'sync-doc');
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
  ///
  /// 达 [isolateCodecThreshold] 的载荷在 worker isolate 完成全部计算
  /// （AES + base64 + JSON），跨 isolate 只传字节数组与 mode 字符串；
  /// 主密钥以 `Uint8List` 局部变量随闭包进 worker，绝不拼进 String、
  /// 不落盘、不进日志（修复 2 的泄密红线）。
  Future<Uint8List> _encrypt(
    Uint8List plain,
    Uint8List aad,
    String mode,
  ) async {
    if (plain.length < _isolateThreshold) {
      return _encryptToWire(plain, aad, mode, key);
    }
    final keyBytes = Uint8List.fromList(key);
    return Isolate.run(() => _encryptToWire(plain, aad, mode, keyBytes));
  }

  /// 解码 JSON 字符串并解密（mode 不匹配 → 抛异常）。
  ///
  /// 判阈值用的是**入参密文**字节数（与待处理工作量成正比，base64 后
  /// 比明文大 ~1.37×，同阈值只会更早进 isolate，方向安全）。
  Future<Uint8List> _decrypt(
    Uint8List cipher,
    Uint8List aad,
    String expectedMode,
  ) async {
    if (cipher.length < _isolateThreshold) {
      return _decryptFromWire(cipher, aad, expectedMode, key);
    }
    final keyBytes = Uint8List.fromList(key);
    return Isolate.run(
      () => _decryptFromWire(cipher, aad, expectedMode, keyBytes),
    );
  }

  /// 加密 + 封装为线格式字节（主 isolate 与 worker isolate 共用同一份实现，
  /// 纯静态函数：入参全可序列化，返回值 Uint8List 可序列化）。
  ///
  /// [version] 只由迁移/测试用入口覆写——生产加密恒写 [_wireVersion]。
  static Future<Uint8List> _encryptToWire(
    Uint8List plain,
    Uint8List aad,
    String mode,
    List<int> key, {
    int version = _wireVersion,
  }) async {
    final nonce = _randomBytes(_nonceLength);
    final box = await AesGcm.with256bits().encrypt(
      plain,
      secretKey: SecretKey(Uint8List.fromList(key)),
      nonce: nonce,
      aad: aad,
    );
    final payload = jsonEncode({
      'mode': mode,
      'v': version,
      'n': base64Encode(nonce),
      'c': base64Encode(box.cipherText),
      'm': base64Encode(box.mac.bytes),
    });
    return Uint8List.fromList(utf8.encode(payload));
  }

  /// 线格式字节 → 明文（与 [_encryptToWire] 对偶；语义与阈值分流前一致）。
  static Future<Uint8List> _decryptFromWire(
    Uint8List cipher,
    Uint8List aad,
    String expectedMode,
    List<int> key, {
    int? allowedVersion,
  }) async {
    // B9 修复（审计 2026-09-07）：解密载荷是远端/他人可控数据——裸
    // `as Map<String, dynamic>` 强转会抛 TypeError；改类型检查抛
    // FormatException（与本文件既有错误口径一致）。
    final decoded = jsonDecode(utf8.decode(cipher));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('加密数据格式损坏（非 JSON 对象）');
    }
    final map = decoded;
    final mode = map['mode'];
    if (mode != expectedMode) {
      throw FormatException('加密数据 mode 不匹配（期望 $expectedMode，实际 $mode）');
    }
    final nonce = base64Decode(_requireString(map, 'n'));
    final cipherText = base64Decode(_requireString(map, 'c'));
    final macBytes = base64Decode(_requireString(map, 'm'));
    _requireFixedLength('nonce', nonce, _nonceLength);
    _requireFixedLength('MAC', macBytes, _macLength);
    // 版本闸门（2026-11-10）：生产路径只认 Argon2id 时代的 v2 信封；v1
    // （PBKDF2 时代）已不兼容。字段缺失/类型不符同样拒绝。归入
    // [SyncKeyMismatchException]——确定性失败、不可重试，避免旧信封被当
    // 网络类失败反复退避。
    //
    // [allowedVersion] 是 v1→v2 迁移专用的放宽口（只开到 v1）；缺省仍是 v2。
    final expectedVersion = allowedVersion ?? _wireVersion;
    if (map['v'] != expectedVersion) {
      throw SyncKeyMismatchException(
        '同步数据版本不兼容（期望 v$expectedVersion，实际 ${map['v']}）',
      );
    }
    try {
      final plain = await AesGcm.with256bits().decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes)),
        secretKey: SecretKey(Uint8List.fromList(key)),
        aad: aad,
      );
      return Uint8List.fromList(plain);
    } on SecretBoxAuthenticationError {
      // AAD 不符（docId 被替换）或密钥错误 → 认证失败。
      // 修复 1②：抛可判别的子类型（仍是 FormatException，文案不变）。
      throw const SyncKeyMismatchException();
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

  /// 测试专用：用**指定密钥与线格式版本**封装一个信封。
  ///
  /// 存在的唯一理由是让测试能构造出**真实形状**的 v1 信封（PBKDF2 时代产物）
  /// ——否则迁移路径只能拿手工拼的假信封自证。生产加解密走实例方法，不碰
  /// 这里；`@visibleForTesting` 让 analyzer 在生产代码引用它时报错。
  @visibleForTesting
  static Future<Uint8List> encryptEnvelopeWithKey({
    required Uint8List plain,
    required Uint8List aad,
    required String mode,
    required List<int> key,
    required int version,
  }) => _encryptToWire(plain, aad, mode, key, version: version);
}

// ── v1（PBKDF2）→ v2（Argon2id）信封迁移（H3 修复，2026-11）─────────────

/// v1（PBKDF2 时代）信封的线格式版本号。
///
/// v1 与 v2 的**线格式**只差 `v` 字段（AAD、nonce/MAC 长度、mode 取值全部
/// 相同）——不兼容的只是**密钥派生**（PBKDF2 → Argon2id，见 [deriveMasterKey]）。
/// 所以迁移 = 用旧口令派生 v1 密钥解开、再用当前 Argon2id 密钥重封，不改线
/// 格式本身。
const int syncEnvelopeV1 = 1;

/// v1 时代 PBKDF2-HMAC-SHA256 的迭代次数。
///
/// 与 [deriveMasterKey] 切换成 Argon2id 之前的默认值逐字一致（600k，OWASP
/// 2026 推荐）。迁移时用它派生旧密钥。
const int syncV1Pbkdf2Iterations = 600000;

/// 派生 v1（PBKDF2）时代的 32B 主密钥——**仅供 v1→v2 迁移使用**。
///
/// 生产路径一律走 [deriveMasterKey]（Argon2id）。本函数存在的唯一理由是让
/// 「旧口令仍能派生 v1 密钥」这件事可被机器验证：迁移工具用它解开 PBKDF2
/// 时代上传的信封，再用当前密钥重封。
Future<List<int>> deriveMasterKeyV1(
  String password,
  List<int> salt, {
  int iterations = syncV1Pbkdf2Iterations,
}) {
  return KekSessionCache.instance.deriveKek(
    password,
    salt,
    KdfParams.pbkdf2(iterations),
  );
}

/// v1 → v2 **文档**信封迁移。
///
/// 语义：用 [password]/[salt] 派生 v1 PBKDF2 密钥（[deriveMasterKeyV1]）
/// 解开 [v1Cipher]，再用当前 Argon2id 主密钥重封成 v2 线格式。旧口令仍能
/// 派生 v1 密钥时迁移成功；解不开（口令已改 / 数据损坏）抛
/// [SyncKeyMismatchException]——确定性失败，调用方据此提示用户重新配置口令，
/// 不做退避重试。
///
/// [deriveV2Key] 供测试注入轻量派生；生产缺省走 [deriveMasterKey]。
Future<Uint8List> migrateSyncDocumentEnvelopeV1ToV2({
  required Uint8List v1Cipher,
  required String docId,
  required String password,
  required List<int> salt,
  Future<List<int>> Function(String password, List<int> salt)? deriveV2Key,
}) {
  return _migrateSyncEnvelopeV1ToV2(
    v1Cipher: v1Cipher,
    aad: AesSyncCipher._docAadBytes(docId),
    mode: 'sync-doc',
    password: password,
    salt: salt,
    deriveV2Key: deriveV2Key,
  );
}

/// v1 → v2 **manifest** 信封迁移（AAD 口径见 [AesSyncCipher] 的 manifest 常量）。
///
/// 与 [migrateSyncDocumentEnvelopeV1ToV2] 同语义，只是 AAD 绑定的是 manifest
/// 上下文（不绑 docId）。
Future<Uint8List> migrateSyncManifestEnvelopeV1ToV2({
  required Uint8List v1Cipher,
  required String password,
  required List<int> salt,
  Future<List<int>> Function(String password, List<int> salt)? deriveV2Key,
}) {
  return _migrateSyncEnvelopeV1ToV2(
    v1Cipher: v1Cipher,
    aad: AesSyncCipher._manifestAadBytes,
    mode: 'sync-manifest',
    password: password,
    salt: salt,
    deriveV2Key: deriveV2Key,
  );
}

/// 迁移内核：v1 密钥解 → v2 密钥封。线格式与 AAD 由调用方按文档/manifest 给。
Future<Uint8List> _migrateSyncEnvelopeV1ToV2({
  required Uint8List v1Cipher,
  required Uint8List aad,
  required String mode,
  required String password,
  required List<int> salt,
  Future<List<int>> Function(String, List<int>)? deriveV2Key,
}) async {
  final v1Key = await deriveMasterKeyV1(password, salt);
  final plain = await _decryptWithKey(
    cipher: v1Cipher,
    aad: aad,
    expectedMode: mode,
    key: v1Key,
    allowedVersion: syncEnvelopeV1,
  );
  final v2Key = await (deriveV2Key ?? deriveMasterKey)(password, salt);
  return _encryptWithKey(plain: plain, aad: aad, mode: mode, key: v2Key);
}

/// 与 [AesSyncCipher] 实例方法同口径的阈值分流（迁移工具复用，不另抄一份算法）。
Future<Uint8List> _decryptWithKey({
  required Uint8List cipher,
  required Uint8List aad,
  required String expectedMode,
  required List<int> key,
  required int allowedVersion,
}) {
  if (cipher.length < AesSyncCipher.isolateCodecThreshold) {
    return AesSyncCipher._decryptFromWire(
      cipher,
      aad,
      expectedMode,
      key,
      allowedVersion: allowedVersion,
    );
  }
  final keyBytes = Uint8List.fromList(key);
  return Isolate.run(
    () => AesSyncCipher._decryptFromWire(
      cipher,
      aad,
      expectedMode,
      keyBytes,
      allowedVersion: allowedVersion,
    ),
  );
}

Future<Uint8List> _encryptWithKey({
  required Uint8List plain,
  required Uint8List aad,
  required String mode,
  required List<int> key,
}) {
  if (plain.length < AesSyncCipher.isolateCodecThreshold) {
    return AesSyncCipher._encryptToWire(plain, aad, mode, key);
  }
  final keyBytes = Uint8List.fromList(key);
  return Isolate.run(
    () => AesSyncCipher._encryptToWire(plain, aad, mode, keyBytes),
  );
}

// ── 密钥派生工具（供上层使用）─────────────────────────────────

/// 生成 [length] 字节随机盐（默认 16）。
List<int> generateSalt({int length = 16}) {
  final rng = Random.secure();
  return List<int>.generate(length, (_) => rng.nextInt(256));
}

/// 从密码派生 32 字节主密钥：**Argon2id**（RFC 9106，cryptography 纯 Dart
/// 实现，经 [KekSessionCache] 后台 isolate 派生 + 会话缓存）。
///
/// 参数与主 PIN 路径一致：[KdfParams.argon2idProduction]（64 MiB / t2 / p2）
/// ——内存硬度抗 GPU/ASIC 爆破，优于旧 PBKDF2-HMAC-SHA256 600k 的纯计算
/// 硬度。密码/盐相同 → 同 key。
///
/// **不兼容旧版（2026-11-10 用户裁决）**：同步 KDF 从 PBKDF2 切换到
/// Argon2id 后，同口令同盐产出**不同** key——PBKDF2 时代上传的云端密文
/// 从此不可解（同步信封同时升级到 v2，解密侧拒绝 v1）。要继续使用云端
/// 数据，用户需重新配置同步口令并全量重传。
Future<List<int>> deriveMasterKey(String password, List<int> salt) {
  return KekSessionCache.instance.deriveKek(
    password,
    salt,
    KdfParams.argon2idProduction,
  );
}
