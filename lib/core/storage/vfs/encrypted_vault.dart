import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:meta/meta.dart';

import 'package:drawing_notes_app/core/storage/vfs/vault_manifest.dart';
import 'package:drawing_notes_app/core/utils/hex_encode.dart';

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
  EncryptedVault({
    required this.directory,
    required this.key,
    this.vacuumCommitBarrier,
  }) : assert(key.length == 32, 'VFS 密钥须为 32 字节'),
       _aes = AesGcm.with256bits();

  final Directory directory;
  final List<int> key;
  final AesGcm _aes;

  /// [仅测试] 清单提交屏障：在 [vacuum] 删除任何对象文件前调用一次。
  /// 抛错即模拟"清单更新失败"，用于验证失败安全（中止删除、保留旧版本
  /// 可回溯）。普通调用置 null（默认）时不生效，行为与无钩子完全一致。
  @visibleForTesting
  final Future<void> Function()? vacuumCommitBarrier;

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

  /// 生命周期整理（vacuum/compact）：**显式调用才触发**，绝不自动执行。
  ///
  /// 为每个对象保留最新的 [retention]（须 >= 1）个版本，删除更旧的
  /// 物理对象文件（`objects/<id>.<v>`）。默认行为与旧版本回读语义完全
  /// 不变：不调用本方法，历史版本始终可读。
  ///
  /// 失败安全：删除任何对象文件前，先刷新清单（内容不变——清单本就只
  /// 记录最新版本——作为原子提交的持久化屏障）；清单加载（HMAC 校验）
  /// 或持久化失败即中止，**不删除任何旧版本**。删除阶段为尽力而为，
  /// 单文件失败不计入 [VaultVacuumResult.removed] 且不致命（残留文件仍
  /// 可回溯）。
  ///
  /// 返回整理结果（删除数/失败数/保留版本文件数）。
  Future<VaultVacuumResult> vacuum({int retention = 3}) async {
    _requireKey();
    if (retention < 1) {
      throw ArgumentError.value(retention, 'retention', '保留版本数必须 >= 1');
    }
    final manifest = await _loadManifest();

    // 计算待删文件：version 大于 retention 的对象，删除 1..(version-retention)。
    final targets = <File>[];
    for (final e in manifest.entries) {
      if (e.version > retention) {
        for (var v = 1; v <= e.version - retention; v++) {
          targets.add(_objectFile(e.id, v));
        }
      }
    }

    // 失败安全提交屏障：先持久化清单（内容不变，刷新认证侧车），再删物理
    // 对象。清单加载或持久化任一失败（含测试注入的真空失败）→ 中止删除。
    final manifestText = manifest.encode();
    await _atomicWriteText(_manifestFile, manifestText);
    await _atomicWriteText(_manifestMacFile, _manifestMac(manifestText));
    final barrier = vacuumCommitBarrier;
    if (barrier != null) await barrier();

    var removed = 0;
    var failed = 0;
    for (final f in targets) {
      try {
        if (await f.exists()) {
          await f.delete();
          removed++;
        }
      } catch (_) {
        failed++; // 尽力而为——残留文件不破坏回溯。
      }
    }
    final retained = manifest.entries.fold<int>(
      0,
      (acc, e) => acc + (e.version > retention ? retention : e.version),
    );
    return VaultVacuumResult(
      removed: removed,
      failed: failed,
      retained: retained,
    );
  }

  /// 扫描孤儿对象文件（**只读，不删除**——删除须显式调用 [purgeOrphans]）。
  ///
  /// 孤儿定义：`objects/` 下存在物理文件，但清单无对应对象条目，或版本号
  /// 超出该对象当前记录版本（崩溃/中断残留），以及未解析的临时文件
  /// （`.tmp.*`）。**合法的历史版本（version <= 清单当前版本）不会被判为
  /// 孤儿**——旧版本回溯语义不受影响。
  ///
  /// 返回相对 `objects/` 的路径列表（已排序）。
  Future<List<String>> scanOrphans() async {
    _requireKey();
    final manifest = await _loadManifest();
    final objectDir = Directory('${directory.path}/objects');
    if (!await objectDir.exists()) return const <String>[];
    final orphans = <String>[];
    await for (final entity in objectDir.list(recursive: true)) {
      if (entity is! File) continue;
      // 归一化分隔符（Windows 用 \，统一为 / 保证跨平台 API 稳定）。
      final rel = entity.path
          .substring(objectDir.path.length + 1)
          .replaceAll('\\', '/');
      if (rel.contains('.tmp')) {
        orphans.add(rel); // 临时文件残留。
        continue;
      }
      final parsed = _parseObjectFileName(rel);
      if (parsed == null) {
        orphans.add(rel); // 不合规文件名。
        continue;
      }
      final entry = manifest.find(parsed.key);
      if (entry == null || parsed.value > entry.version) {
        orphans.add(rel);
      }
      // entry != null && version <= entry.version → 合法保留版本，跳过。
    }
    orphans.sort();
    return List.unmodifiable(orphans);
  }

  /// 删除孤儿对象文件（**显式调用才触发**，绝不自动执行）。
  ///
  /// 基于 [scanOrphans] 判定，只删确属孤儿的文件，**绝不触碰**清单内任何
  /// 对象的合法历史版本。单文件删除失败忽略（尽力而为）。
  ///
  /// 返回成功删除的相对路径列表。
  Future<List<String>> purgeOrphans() async {
    _requireKey();
    final orphans = await scanOrphans();
    final removed = <String>[];
    for (final rel in orphans) {
      try {
        final f = File('${directory.path}/objects/$rel');
        if (await f.exists()) {
          await f.delete();
          removed.add(rel);
        }
      } catch (_) {
        /* 忽略单文件删除失败 */
      }
    }
    return removed;
  }

  /// 解析 `objects/` 相对路径里的 `id.version`（id 可含 `/` 子路径，
  /// 版本号为末段点之后的整数）。无法解析返回 null。
  MapEntry<String, int>? _parseObjectFileName(String rel) {
    final dot = rel.lastIndexOf('.');
    if (dot <= 0 || dot == rel.length - 1) return null;
    final ver = int.tryParse(rel.substring(dot + 1));
    if (ver == null) return null;
    return MapEntry(rel.substring(0, dot), ver);
  }

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
    return hexEncode(List<int>.generate(bytes, (_) => rng.nextInt(256)));
  }
}
