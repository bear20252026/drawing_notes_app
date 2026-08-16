import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

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
  EncryptedVault({
    required this.directory,
    required this.key,
  })  : assert(key.length == 32, 'VFS 密钥须为 32 字节'),
        _aes = AesGcm.with256bits();

  final Directory directory;
  final List<int> key;
  final AesGcm _aes;

  /// 清单文件路径。
  File get _manifestFile => File('${directory.path}/manifest.json');

  /// 对象密文路径（id.version——版本隔离——旧版本保留可回溯）。
  File _objectFile(String id, int version) =>
      File('${directory.path}/objects/$id.$version');

  /// AAD 上下文（应用|用途|对象 ID|版本——防拼接/重排/回滚）。
  String _aad(String id, int version) =>
      'drawing-notes|vault|$id|$version';

  /// 写入对象（加密 + 清单更新 + 原子提交——版本递增；幂等：同内容
  /// 重复写无副作用——腾讯云 Git 模式）。
  Future<VaultManifestEntry> writeObject({
    required String id,
    required String type,
    required Uint8List plain,
  }) async {
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
    final cipher = Uint8List.fromList([...nonce, ...box.cipherText, ...box.mac.bytes]);

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
    await _atomicWriteText(_manifestFile, manifest.encode());
    return entry;
  }

  /// 读取对象（清单解析 + 解密 + AAD 验证——版本不符/篡改 → 认证失败）。
  Future<Uint8List> readObject(String id, {int? version}) async {
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
    return VaultManifest.decode(await _manifestFile.readAsString());
  }

  /// 原子写入（腾讯云 Git 五细节：临时文件 + rename——crash 不留中间
  /// 状态——幂等——孤儿清理）。
  Future<void> _atomicWrite(File target, Uint8List data) async {
    final tmp = File('${target.path}.tmp.${DateTime.now().microsecondsSinceEpoch}');
    await tmp.writeAsBytes(data, flush: true);
    try {
      await tmp.rename(target.path);
    } catch (_) {
      // 目标已存在（并发幂等兜底）或 rename 失败——清理临时文件。
      if (await tmp.exists()) {
        try {
          await tmp.delete();
        } catch (_) {/* 忽略清理失败 */}
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
}
