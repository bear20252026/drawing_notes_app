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
/// `{"mode":"sync-doc"|"sync-manifest","v":2,"n":base64(nonce),"c":base64(cipherText),"m":base64(mac)}`
///
/// **信封版本 v2（2026-11-10）**：同步主密钥派生升级为 Argon2id（见
/// [deriveMasterKey]），与 v1（PBKDF2 时代）信封不兼容——解密侧强制校验
/// `v == 2`，旧信封一律拒绝（fail-closed，且归入不可重试的密钥错配类）。
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
  Uint8List _docAad(String docId) =>
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
  static Future<Uint8List> _encryptToWire(
    Uint8List plain,
    Uint8List aad,
    String mode,
    List<int> key,
  ) async {
    final nonce = _randomBytes(_nonceLength);
    final box = await AesGcm.with256bits().encrypt(
      plain,
      secretKey: SecretKey(Uint8List.fromList(key)),
      nonce: nonce,
      aad: aad,
    );
    final payload = jsonEncode({
      'mode': mode,
      'v': _wireVersion,
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
    List<int> key,
  ) async {
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
    // 版本闸门（2026-11-10）：只认 Argon2id 时代的 v2 信封；v1（PBKDF2 时代）
    // 已不兼容。字段缺失/类型不符同样拒绝。归入 [SyncKeyMismatchException]
    // ——确定性失败、不可重试，避免旧信封被当网络类失败反复退避。
    if (map['v'] != _wireVersion) {
      throw const SyncKeyMismatchException('同步数据版本不兼容（旧版加密信封）');
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
