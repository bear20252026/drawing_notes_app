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
class SyncKeyMismatchException extends FormatException {
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
/// `{"mode":"sync-doc"|"sync-manifest","v":1,"n":base64(nonce),"c":base64(cipherText),"m":base64(mac)}`
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
      'v': 1,
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

/// 从密码派生 32 字节主密钥：PBKDF2-HMAC-SHA256。
///
/// 默认 60 万次迭代（OWASP 2026 推荐）。密码/盐相同 → 同 key。
/// N3 提速 B 方案：走 KekSessionCache（会话缓存 + isolate 后台派生）。
/// 批B 注：同步格式跨设备互操作，KDF 与既有密文耦合，维持 PBKDF2。
///
/// 为何不升 Argon2id（审计 2026-09-26 #39 评估结论，全量分析见
/// `docs/KDF_MIGRATION_EVALUATION_2026-09-26.md`）：PBKDF2 600k 是纯
/// 计算硬度，GPU 吞吐下实耗毫秒级/口令；Argon2id 的 64MiB 内存硬度可
/// 把同硬件爆破吞吐压低 2–3 个数量级。差距真实但兑现需「WebDAV 服务器
/// 副本泄露 + 低熵口令」双条件叠加，当前 OWASP 合规、非紧急漏洞。
/// 迁移方案（信封版本化 + 用户主动事件触发重绕，不做后台静默迁移）与
/// 风险对策见上述评估文档；下次触及同步加密域（改密/配对协议）时顺车
/// 实施。
Future<List<int>> deriveMasterKey(
  String password,
  List<int> salt, {
  int iterations = 600000,
}) {
  return KekSessionCache.instance.deriveKek(
    password,
    salt,
    KdfParams.pbkdf2(iterations),
  );
}
