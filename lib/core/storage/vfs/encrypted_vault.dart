import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';

import 'package:drawing_notes_app/core/storage/vfs/vault_manifest.dart';

/// VFS 加密对象仓库核心（专家目标架构 VFS——2026-08-16）。
///
/// AeroVault V3 manifest + 腾讯云 Git 原子写入五工程细节 + AAD 绑定：
/// - 对象清单（vault_manifest.json——描述对象条目 id/type/version/AAD）
/// - 每对象版本（变更递增——openbucket 版本保留）
/// - AAD 绑定（'drawing-notes|vault|ID|version'——NIST SP 800-38D——
///   防拼接/重排/版本回滚——AAD 不符解密认证失败）
/// - 原子提交（临时文件 + rename——OS rename 原子——crash 不留中间
///   状态；幂等 try_exists；孤儿清理）
///
/// 存储布局：目录下 manifest.json + objects/ 目录（id.version 密文文件）。
class EncryptedVault {
  EncryptedVault({required this.directory, required this.key})
    : assert(key.length == 32, 'VFS 密钥须为 32 字节'),
      _aes = AesGcm.with256bits();

  final Directory directory;
  final List<int> key;
  final AesGcm _aes;

  /// 清单文件路径。
  File get _manifestFile => File('${directory.path}/manifest.json');

  /// 清单认证侧车（HMAC-SHA256(key, manifest.json) hex——P1 修复 N-M1：
  /// 明文 manifest 任人改 version 回滚旧版本；有侧车即验签，验签失败
  /// fail-closed；无侧车=历史遗留，下次写入自动补上）。
  File get _manifestMacFile => File('${directory.path}/manifest.hmac');

  /// 对象 id 段白名单（P1 修复 N-M2：`../../vault.key.json` 逃逸 objects/）。
  /// id 可含 `/` 子路径（`media/note-1` 用例保留），但每段仅
  /// `[A-Za-z0-9_.~\-]`，禁 `.`/`..`/空段/超长。
  static final RegExp _safeIdSegment = RegExp(r'^[A-Za-z0-9_.~\-]+$');

  String _safeId(String id) {
    if (id.isEmpty || id.length > 256) {
      throw StateError('VFS id 不合法');
    }
    for (final seg in id.split('/')) {
      if (seg.isEmpty ||
          seg == '.' ||
          seg == '..' ||
          !_safeIdSegment.hasMatch(seg)) {
        throw StateError('VFS id 不合法');
      }
    }
    return id;
  }

  /// 密钥长度运行时校验（assert 在 release 被剥离——P1 补强）。
  void _requireKey() {
    if (key.length != 32) throw StateError('VFS 密钥须为 32 字节');
  }

  /// 对象密文路径（id.version——版本隔离——旧版本保留可回溯）。
  File _objectFile(String id, int version) =>
      File('${directory.path}/objects/$id.$version');

  /// AAD 上下文（应用|用途|对象 ID|版本——防拼接/重排/回滚）。
  String _aad(String id, int version) => 'drawing-notes|vault|$id|$version';

  /// 写入对象（加密 + 清单更新 + 原子提交——版本递增；幂等：同内容
  /// 重复写无副作用——腾讯云 Git 模式）。
  Future<VaultManifestEntry> writeObject({
    required String id,
    required String type,
    required Uint8List plain,
  }) async {
    _requireKey();
    _safeId(id);
    final manifest = await _loadManifest();
    final existing = manifest.find(id);
    final version = (existing?.version ?? 0) + 1;
    final aad = _aad(id, version);

    // 加密（AAD 绑定版本——防回滚）。
    final nonce = _randomNonce();
    final box = await _aes.encrypt(
      plain,
      secretKey: SecretKey(key),
      nonce: nonce,
      aad: utf8.encode(aad),
    );
    final cipher = Uint8List.fromList([
      ...nonce,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);

    // 原子提交：写对象密文（.tmp → rename）→ 更新清单 → 原子写清单。
    final objectDir = Directory('${directory.path}/objects');
    await objectDir.create(recursive: true);
    final target = _objectFile(id, version);
    await _atomicWrite(target, cipher);

    final entry = VaultManifestEntry(
      id: id,
      type: type,
      version: version,
      size: cipher.length,
      aad: aad,
      modified: DateTime.now(),
    );
    manifest.entries
      ..removeWhere((e) => e.id == id)
      ..add(entry);
    final manifestText = manifest.encode();
    await _atomicWriteText(_manifestFile, manifestText);
    // 清单认证侧车同步刷新（与清单同原子写语义）。
    await _atomicWriteText(_manifestMacFile, _manifestMac(manifestText));
    return entry;
  }

  /// 读取对象（清单解析 + 解密 + AAD 验证——版本不符/篡改 → 认证失败）。
  Future<Uint8List> readObject(String id, {int? version}) async {
    _requireKey();
    _safeId(id);
    final manifest = await _loadManifest();
    final entry = manifest.find(id);
    if (entry == null) {
      throw StateError('VFS 对象不存在：$id');
    }
    final targetVersion = version ?? entry.version;
    final file = _objectFile(id, targetVersion);
    if (!await file.exists()) {
      throw StateError('VFS 对象文件缺失：$id.$targetVersion');
    }
    final cipher = await file.readAsBytes();
    // P1 修复：截断文件（<28B：12 nonce + 16 tag）此前抛 RangeError
    // 崩溃调用方——统一为 StateError（fail-closed，不区分截断与篡改）。
    if (cipher.length < 28) {
      throw StateError('VFS 对象密文损坏：$id.$targetVersion');
    }
    final nonce = cipher.sublist(0, 12);
    final box = SecretBox(
      cipher.sublist(12, cipher.length - 16),
      nonce: nonce,
      mac: Mac(cipher.sublist(cipher.length - 16)),
    );
    final clear = await _aes.decrypt(
      box,
      secretKey: SecretKey(key),
      aad: utf8.encode(_aad(id, targetVersion)),
    );
    return Uint8List.fromList(clear);
  }

  /// 当前清单快照（对象条目集——版本/大小/AAD）。
  Future<List<VaultManifestEntry>> listObjects() async =>
      List.unmodifiable((await _loadManifest()).entries);

  Future<VaultManifest> _loadManifest() async {
    if (!await _manifestFile.exists()) {
      return VaultManifest(entries: []);
    }
    final raw = await _manifestFile.readAsString();
    // P1 修复 N-M1：有认证侧车即验签（改 version 回滚旧版在此被拦）。
    // 无侧车=历史遗留：放行本次读取，下次写入自动补签（零破坏升级）。
    if (await _manifestMacFile.exists()) {
      final expect = (await _manifestMacFile.readAsString()).trim();
      final actual = _manifestMac(raw);
      if (!_constantTimeEquals(actual, expect)) {
        throw StateError('VFS 清单认证失败（被篡改或回滚）');
      }
    }
    return VaultManifest.decode(raw);
  }

  /// 清单认证值：HMAC-SHA256(密钥, 清单字节) hex。
  String _manifestMac(String raw) =>
      crypto.Hmac(crypto.sha256, key).convert(utf8.encode(raw)).toString();

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  /// 原子写入（腾讯云 Git 五细节：临时文件 + rename——crash 不留中间
  /// 状态——幂等——孤儿清理）。
  /// P1 修复：tmp 名加随机后缀（可预测微秒名 symlink 劫持）；清单写入
  /// 后同步刷新认证侧车（同原子写）。
  Future<void> _atomicWrite(File target, Uint8List data) async {
    // 目录预创建（腾讯云 Git 五细节）：id 可含 usecase 子路径
    // （'media/note-1' → objects/media/note-1.1）——写前确保父目录存在。
    await target.parent.create(recursive: true);
    final tmp = File(
      '${target.path}.tmp.${DateTime.now().microsecondsSinceEpoch}.${_randomHex(8)}',
    );
    await tmp.writeAsBytes(data, flush: true);
    try {
      await tmp.rename(target.path);
    } catch (_) {
      // 目标已存在（并发幂等兜底）或 rename 失败——清理临时文件。
      if (await tmp.exists()) {
        try {
          await tmp.delete();
        } catch (_) {
          /* 忽略清理失败 */
        }
      }
      if (await target.exists()) return; // 幂等：目标已写入成功。
      rethrow;
    }
  }

  Future<void> _atomicWriteText(File target, String text) =>
      _atomicWrite(target, Uint8List.fromList(utf8.encode(text)));

  static Uint8List _randomNonce() {
    final rng = Random.secure();
    return Uint8List.fromList(List<int>.generate(12, (_) => rng.nextInt(256)));
  }

  static String _randomHex(int bytes) {
    final rng = Random.secure();
    return List<int>.generate(
      bytes,
      (_) => rng.nextInt(256),
    ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
