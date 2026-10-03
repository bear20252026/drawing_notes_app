import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/security/session_secrets.dart';
import 'package:drawing_notes_app/core/storage/document_codec.dart';
import 'package:drawing_notes_app/core/storage/local_id_generator.dart';
import 'package:drawing_notes_app/core/storage/repository.dart';
import 'package:drawing_notes_app/core/storage/storage_directories.dart';
import 'package:drawing_notes_app/core/storage/storage_file_password_manager.dart';
import 'package:drawing_notes_app/core/storage/storage_media_store.dart';
import 'package:drawing_notes_app/core/storage/storage_secret_session.dart';
import 'package:drawing_notes_app/core/storage/storage_trash_bin.dart';
import 'package:drawing_notes_app/core/storage/storage_write_pipeline.dart';
import 'package:drawing_notes_app/core/storage/vault_file_codec.dart';
import 'package:drawing_notes_app/core/utils/time_serialization.dart';

// C-08（审计 2026-09-27）：原「单类五职责」（638 行本体 + 4 个共享全部
// 私有态的 part——O1 域分权只做了物理拆分）分解为五个真协作类：
//   目录域 StorageDirectories / 会话机密域 StorageSecretSession /
//   写入管线域 StorageWritePipeline / 媒体资产域 StorageMediaStore /
//   回收站域 StorageTrashBin / 文件密码域 StorageFilePasswordManager。
// 本类保留门面：实现 DocumentRepository + SessionSecretsHolder，全部
// 公共 API（含文件密码管理面）逐一委托，消费方与测试零改动。
//
// 装配依赖（无环）：directories/secrets → pipeline → media →
// filePasswords；trash 依赖 media/pipeline/secrets。门面按序构造，
// 媒体域对「是否受文件密码保护」经回调取自密码域（构造序解环）。

/// 本地文件存储服务：负责工程文件的保存、读取、列表、删除。
///
/// 目录结构（应用文档目录下）：
///   `appDir/documents/`
///     `docId.json` —— 工程文件（含全部图层与笔画）
///
/// 设计要点：
/// - 全部为本地文件操作，不发起任何网络请求（符合开发计划约束）；
/// - 保存采用"先写临时文件再原子替换"，防止写入中断导致文件损坏；
/// - 存储层与绘图引擎层解耦：UI/引擎不感知文件格式细节，
///   后续若更换为数据库（sqflite）或云同步，只需替换本类实现
///   （已通过 [DocumentRepository] 接口抽象，见 repository.dart）。
class StorageService implements DocumentRepository, SessionSecretsHolder {
  StorageService({
    DocumentCodec? codec,
    this.directoryProvider,
    this.keyProvider,
  }) : _codec = codec ?? const DocumentCodec() {
    _directories = StorageDirectories(directoryProvider: directoryProvider);
    _secrets = StorageSecretSession();
    _pipeline = StorageWritePipeline(
      directories: _directories,
      secrets: _secrets,
      keyProvider: keyProvider,
    );
    _media = StorageMediaStore(
      directories: _directories,
      secrets: _secrets,
      pipeline: _pipeline,
      codec: _codec,
      isFilePasswordProtected: (id) =>
          _filePasswords.isFilePasswordProtected(id),
      keyProvider: keyProvider,
      fireOnWrite: _fireOnWrite,
    );
    _filePasswords = StorageFilePasswordManager(
      directories: _directories,
      secrets: _secrets,
      pipeline: _pipeline,
      media: _media,
      fireOnWrite: _fireOnWrite,
    );
    _trash = StorageTrashBin(
      directories: _directories,
      secrets: _secrets,
      pipeline: _pipeline,
      media: _media,
      codec: _codec,
      fireOnWrite: _fireOnWrite,
    );
    // P1 修复 M-05：注册会话机密清理——切后台回锁时口令/DEK 一并失效。
    SessionSecrets.register(this);
  }

  final DocumentCodec _codec;

  late final StorageDirectories _directories;
  late final StorageSecretSession _secrets;
  late final StorageWritePipeline _pipeline;
  late final StorageMediaStore _media;
  late final StorageFilePasswordManager _filePasswords;
  late final StorageTrashBin _trash;

  /// 目录提供者：测试时可注入临时目录，生产环境使用系统文档目录。
  final Future<Directory> Function()? directoryProvider;

  /// 主密钥提供者（加密底座批次①b）：返回解锁态主密钥时，文档 JSON 以
  /// AES-256-GCM 信封落盘（`DNV` 魔数，AAD 绑定文档 ID）；返回 null
  /// （未设密码 / 保险库锁定）时保持明文兼容。由组合根注入。
  final Future<Uint8List?> Function()? keyProvider;

  /// 写成功回调（首页刷新修复①）：画布保存/缩略图更新/删除落盘成功后触发，
  /// 由装配层注入（AppServices.bumpDataVersion），驱动首页/AllDocs 刷新。
  void Function()? onWrite;

  void _fireOnWrite() => onWrite?.call();

  // ---- 文档 CRUD（DocumentRepository） ----

  /// 保存文档。成功后返回文件路径。
  ///
  /// 崩溃恢复：写入新版本前，把上一版正式文件备份为 `.bak`，
  /// 加载时若正式文件损坏可自动回退到备份（借鉴 nb 版本回溯思想）。
  ///
  /// 链 G 说明（军工审计 2026-08-15）：`.bak` 保留上一版内容（含用户已
  /// 删除的对象——崩溃恢复的必要代价，仅最近 1 版且 delete 时彻底清理）；
  /// 敏感内容建议启用加密（密文 .bak 无明文残留）。
  @override
  Future<String> save(DrawingDocument doc) {
    if (!isValidId(doc.id)) {
      throw ArgumentError.value(doc.id, 'doc.id', '文档 ID 不合法');
    }
    // 在进入异步队列前编码出不可变快照。编辑器继续修改 doc 时，队列中的
    // 某次保存仍代表其被请求时的完整版本，而不是可变对象的半成品状态。
    // U2 优化（2026-09-02，P1-10）：主线程只构建快照 Map，jsonEncode +
    // UTF-8 交给 isolate（大文档时），保存瞬间不再阻塞 UI。
    final snapshot = DocumentCodec.snapshotOf(doc);
    final id = doc.id;
    final operation = _pipeline.enqueueSave(id, () async {
      final data = await DocumentCodec.encodeSnapshotAsync(snapshot);
      await _pipeline.saveEncoded(id, data);
    });
    return operation
        .then((_) async {
          await _directories.ensureDocuments();
          return _directories.documentPathFor(id);
        })
        .then((path) {
          onWrite?.call();
          return path;
        });
  }

  /// 加载指定文档。文件不存在返回 null，格式损坏抛出异常（由调用方提示）。
  ///
  /// 崩溃恢复：正式文件损坏时，尝试读取 `.bak` 上一版备份。
  @override
  Future<DrawingDocument?> load(String id) async {
    await _directories.ensureDocuments();
    final path = _directories.documentPathFor(id);
    final file = File(path);
    final bak = File('$path.bak');
    if (!file.existsSync() && !bak.existsSync()) return null;
    Future<Uint8List> preparedBytes(File source) async {
      final raw = await StorageWritePipeline.readWithRetry(
        () async => await source.readAsBytes(),
      );
      return _pipeline.prepareDocBytes(id, raw);
    }

    try {
      return _codec.decode(
        await preparedBytes(file.existsSync() ? file : bak),
      );
    } on FormatException {
      // 正式文件损坏：尝试备份恢复。
      if (bak.existsSync()) {
        return _codec.decode(await preparedBytes(bak));
      }
      rethrow;
    }
  }

  /// 列出所有已保存文档（含元信息），按更新时间倒序。
  @override
  Future<List<DocumentMeta>> listDocuments() async {
    // M-06：列表时自动清理过期回收站项（30 天保留——Android 官方模式）。
    // P1 修复（本次）：改走节流入口——原实现每次列表都全扫回收站，配合
    // 「过期判定用 mtime」的缺陷把误删放大到每次刷新首页（详见
    // StorageTrashBin.purgeTrashThrottled）。
    await _trash.purgeTrashThrottled();
    final dir = await _directories.ensureDocuments();
    final metas = <DocumentMeta>[];
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        // 链 9 修复（军工审计 2026-08-15）：列表页大小预检——原实现无
        // 限制 readAsBytes + jsonDecode，恶意超大 .json（如 90MB）会在
        // 打开主页时 OOM（D-4 只约束 load 路径）。
        if (await entity.length() > _maxListMetaBytes) continue;
        final raw = await entity.readAsBytes();
        // 批次①b：文件名即文档 ID（save 以 doc.id 命名），AAD 绑定用。
        final fileName = entity.uri.pathSegments.last;
        final fileId = fileName.substring(0, fileName.length - '.json'.length);
        var bytes = raw;
        var locked = false;
        if (VaultFileCodec.isPasswordEnvelope(raw)) {
          // 批次②：单文件密码信封——会话有密码 → 正常读元信息；
          // 无密码 → 锁定占位（不暴露标题等任何元信息）。
          final filePassword = _secrets.filePasswordFor(fileId);
          if (filePassword == null) {
            locked = true;
          } else if (VaultFileCodec.isV3Envelope(raw)) {
            // N4 批 2：v3 信封——解锁并缓存 DEK/USB 槽位。
            final unlock = await VaultFileCodec.unlockWithPasswordV3(
              raw,
              filePassword,
              aadContext: 'doc:$fileId',
            );
            _secrets.cacheV3Material(fileId, unlock);
            bytes = unlock.plain;
          } else {
            bytes = await VaultFileCodec.decryptWithPassword(
              raw,
              filePassword,
              aadContext: 'doc:$fileId',
            );
          }
        } else if (VaultFileCodec.isEncrypted(raw)) {
          final key = await _pipeline.currentKey();
          // fail-closed：锁定状态不暴露加密文档（跳过，不中断整个列表）。
          if (key == null) continue;
          bytes = await VaultFileCodec.decrypt(
            raw,
            key,
            aadContext: 'doc:$fileId',
          );
        } else if (await _pipeline.currentKey() != null) {
          // 懒迁移：明文文档排队重写为密文。
          if (isValidId(fileId)) _pipeline.enqueueRawRewrite(fileId, raw);
        }
        if (locked) {
          if (!isValidId(fileId)) continue;
          metas.add(
            DocumentMeta(
              id: fileId,
              // L-04：锁定占位标题不产出——空串 + locked 标志，展示层统一渲染。
              title: '',
              width: 0,
              height: 0,
              createdAt: DateTime.now(),
              updatedAt: await _fileModifiedOrNow(entity),
              layerCount: 0,
              strokeCount: 0,
              locked: true,
            ),
          );
          continue;
        }
        final root = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        final doc = root['document'] as Map<String, dynamic>;
        final docId = doc['id'];
        // 链 A 修复（军工审计 2026-08-15）：列表 id 校验——恶意工程文件
        // 可携带任意 id，过滤不合法 id 防路径遍历（load/delete 入口）。
        if (docId is! String || !isValidId(docId)) continue;
        metas.add(
          DocumentMeta(
            id: docId,
            title: doc['title'] as String? ?? '',
            width: (doc['width'] as num?)?.toInt() ?? 2048,
            height: (doc['height'] as num?)?.toInt() ?? 1536,
            createdAt: timeFromIso(doc['createdAt']),
            updatedAt: timeFromIso(doc['updatedAt']),
            layerCount: (doc['layers'] as List? ?? const []).length,
            strokeCount: _countStrokes(
              (doc['layers'] as List? ?? const []).cast<Map<String, Object?>>(),
            ),
            folder: doc['folder'] is String ? doc['folder'] as String : '',
          ),
        );
      } on FormatException {
        // 跳过损坏文件，不中断整个列表。
        continue;
      } catch (_) {
        continue;
      }
    }
    metas.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return metas;
  }

  /// 删除指定文档及其不再被任何其他文档引用的受管图片副本。
  ///
  /// E-17 修复（审计 2026-09-07）：整个删除流程挂入与保存相同的 per-id
  /// 写尾队列——此前在途保存与删除交错会让已删文档复活（rename 进回收站
  /// 后，队列中的保存又写出正式文件）。
  @override
  Future<bool> delete(String id) =>
      _pipeline.runDocExclusive(id, () => _trash.deleteDocumentToTrash(id));

  int _countStrokes(List<Map<String, Object?>> layers) {
    var n = 0;
    for (final l in layers) {
      n += (l['strokes'] as List? ?? const []).length;
    }
    return n;
  }

  /// 文件修改时间（失败回退当前时间——锁定占位元信息排序用）。
  static Future<DateTime> _fileModifiedOrNow(File f) async {
    try {
      return f.statSync().modified;
    } catch (_) {
      return DateTime.now();
    }
  }

  /// 列表页单文件大小上限（链 9 修复 2026-08-15）：防恶意超大 .json
  /// 在 listDocuments 时 OOM（与 DocumentCodec 100MB 预检一致）。
  static const int _maxListMetaBytes = 100 * 1024 * 1024;

  /// 校验文档 ID 是否安全（仅允许字母、数字、下划线、'-'）。
  ///
  /// 安全说明：ID 直接拼入文件路径，若允许 `../` 等字符会造成路径遍历。
  /// 所有合法 ID 由 [newId] 生成；此校验作为防御性边界。
  static bool isValidId(String id) =>
      StorageDirectories.validIdPattern.hasMatch(id);

  /// 生成一个唯一的文档 ID。
  static String newId() => LocalIdGenerator.next('doc');

  // ---- 媒体资产域（缩略图 + 受管图片） ----

  Future<String> saveThumbnail(String docId, Uint8List pngBytes) =>
      _media.saveThumbnail(docId, pngBytes);

  Future<Uint8List?> thumbnailBytes(String docId) =>
      _media.thumbnailBytes(docId);

  Future<String?> thumbnailPath(String docId) => _media.thumbnailPath(docId);

  Future<String> storeImage(String sourcePath, String docId) =>
      _media.storeImage(sourcePath, docId);

  // ---- 回收站域（M-06） ----

  Future<String?> restoreTrash(String trashName) =>
      _trash.restoreTrash(trashName);

  /// 列出回收站项（M-06）：返回 (trashName, 原始 id, 删除时间)，最近在前。
  Future<List<(String, String, DateTime)>> listTrash() => _trash.listTrash();

  /// 清理过期回收站项（M-06）：超过保留期（默认 30 天）永久删除。
  Future<int> purgeTrash({
    Duration retention = StorageTrashBin.defaultTrashRetention,
  }) => _trash.purgeTrash(retention: retention);

  /// 永久删除单个回收站项（M-06 UI：Delete forever 与 Restore 分离——
  /// UX Patterns 官方模式）。返回是否删除成功。
  Future<bool> deleteTrashPermanently(String trashName) =>
      _trash.deleteTrashPermanently(trashName);

  // ---- 会话机密域（SessionSecretsHolder） ----

  /// 该文档本会话内是否已解锁文件密码（编辑器保存走同一密封路径）。
  String? filePasswordFor(String docId) => _secrets.filePasswordFor(docId);

  /// 缓存会话文件密码（verifyFilePassword 成功后调用）。
  void cacheFilePassword(String docId, String password) =>
      _secrets.cacheFilePassword(docId, password);

  /// 清除会话文件密码（移除文件密码 / 文档删除后调用）。
  void forgetFilePassword(String docId) => _secrets.forgetFilePassword(docId);

  /// P1 修复 M-05：清空全部会话机密（切后台回锁联动经 [SessionSecrets]）。
  @override
  void clearAllSessionSecrets() => _secrets.clearAll();

  // ---- 文件密码域（批次②/N2 管理面） ----

  /// 该文档是否受独立文件密码保护（读文件头版本字节，不解密）。
  Future<bool> isFilePasswordProtected(String id) =>
      _filePasswords.isFilePasswordProtected(id);

  /// 校验文件密码；正确则缓存进会话（解锁一次本会话免重复输入）。
  Future<bool> verifyFilePassword(String id, String password) =>
      _filePasswords.verifyFilePassword(id, password);

  /// 该文档是否绑定了重置密码盘（v3 信封且含 USB 槽位；读头部不解密）。
  Future<bool> hasFileUsbSlot(String id) => _filePasswords.hasFileUsbSlot(id);

  /// 为未设密文档设置独立文件密码（v3 双保护器信封重封 + 删除缩略图）。
  Future<void> setFilePassword(
    String id,
    String password, {
    List<int>? resetDiskKey,
  }) => _filePasswords.setFilePassword(
    id,
    password,
    resetDiskKey: resetDiskKey,
  );

  /// 修改文件密码（验证旧密码 → 重封）。旧密码错误抛 [VaultFileException]。
  Future<void> changeFilePassword(
    String id,
    String oldPassword,
    String newPassword,
  ) => _filePasswords.changeFilePassword(id, oldPassword, newPassword);

  /// 绑定重置密码盘到已设密文档（事后绑定通道；须验证文件密码）。
  Future<void> bindFileUsbSlot(String id, String password, List<int> usbKey) =>
      _filePasswords.bindFileUsbSlot(id, password, usbKey);

  /// 重置密码盘重置文件密码（N4 批 2：忘记密码通道）。
  Future<bool> resetFilePasswordWithUsb(
    String id,
    List<int> usbKey,
    String newPassword,
  ) => _filePasswords.resetFilePasswordWithUsb(id, usbKey, newPassword);

  /// 移除文件密码：回封为 v1 主密钥信封（应用锁未解锁时拒绝，fail-closed）。
  Future<void> removeFilePassword(String id, String password) =>
      _filePasswords.removeFilePassword(id, password);
}
