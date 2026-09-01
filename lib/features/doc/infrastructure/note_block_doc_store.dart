/// 块文档（NoteBlockDoc）本地存储门面。
///
/// 提供 [NoteBlockDoc] 的加载、保存、删除能力。存储键与现有
/// [NotebookStorage] 区分（独立 `blockdocs` 目录），避免混叠。
///
/// 目录结构（应用文档目录下）：
///   `appDir/blockdocs/`
///     `{docId}.json` —— 块文档序列化文件
///
/// 仅依赖 [NoteBlockDoc]（domain）+ dart:io + directoryProvider；
/// 不 import presentation，层方向严格 domain ← infrastructure。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'package:drawing_notes_app/core/storage/local_id_generator.dart';
import 'package:drawing_notes_app/core/storage/vault_file_codec.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block_doc.dart';

/// 块文档本地存储门面。
///
/// 用法：
/// ```dart
/// final store = NoteBlockDocStore();
/// await store.saveDocument(doc);
/// final loaded = await store.loadDocument(doc.id);
/// await store.deleteDocument(doc.id);
/// ```
class NoteBlockDocStore {
  /// 创建块文档存储门面。
  ///
  /// [directoryProvider] 为可选的目录提供者回调。测试时可注入临时目录，
  /// 生产环境默认使用系统文档目录。
  NoteBlockDocStore({this.directoryProvider, this.keyProvider});

  /// 目录提供者：测试时可注入临时目录，生产环境使用系统文档目录。
  final Future<Directory> Function()? directoryProvider;

  /// 主密钥提供者（加密底座批次①c）：返回解锁态主密钥时，块文档 JSON
  /// 以 AES-256-GCM 信封落盘（AAD 绑定 `block:<id>`）；null 时明文兼容。
  final Future<Uint8List?> Function()? keyProvider;

  /// 写成功回调（首页刷新修复①）：保存/删除/恢复/彻底删除落盘成功后触发，
  /// 由装配层注入（AppServices.bumpDataVersion）——把刷新通知下沉到存储层，
  /// 覆盖所有写路径（笔记本内新建、DocPage 自动保存等），不再依赖调用点逐一通知。
  void Function()? onWrite;

  Directory? _dir;

  Future<Directory> _baseDir() async {
    final provider = directoryProvider;
    if (provider != null) return provider();
    return getApplicationDocumentsDirectory();
  }

  Future<Directory> _ensureDir() async {
    if (_dir != null) return _dir!;
    final base = await _baseDir();
    final dir = Directory('${base.path}${Platform.pathSeparator}blockdocs');
    if (!await dir.exists()) await dir.create(recursive: true);
    _dir = dir;
    return dir;
  }

  /// P0-H3 写尾队列：同 id 的写操作（保存/删除/恢复）串行化，
  /// 消除自动保存与软删除交错导致的「已删文档复活/新内容被覆盖」竞态。
  final Map<String, Future<void>> _writeChains = {};

  /// 把 [op] 挂到 [id] 的写链尾；链上某步失败不影响后续步骤。
  /// 任何写操作完成后使头信息缓存失效（P2-M5）。
  Future<T> _enqueue<T>(String id, Future<T> Function() op) {
    final prev = _writeChains[id] ?? Future<void>.value();
    final task = prev.then((_) => op());
    _writeChains[id] = task.then(
      (_) => _headerCache = null,
      onError: (_) => _headerCache = null,
    );
    return task;
  }

  /// 文档头信息缓存（P2-M5）：列表热路径（AllDocs/反向链接面板）不再
  /// 每次全量解析全部文档 JSON——冷路径解析一次，之后走内存。
  List<NoteBlockDocHeader>? _headerCache;

  Future<Uint8List?> _currentKey() async {
    final provider = keyProvider;
    if (provider == null) return null;
    return provider();
  }

  /// 读取后的字节准备（批次①c，与 StorageService 同纪律）：
  /// 密文+解锁 → 解密；密文+锁定 → [VaultFileLockException]；
  /// 明文+有钥 → 原样返回并经写链懒迁移。
  Future<Uint8List> _prepareDocBytes(String id, Uint8List raw) async {
    final key = await _currentKey();
    if (VaultFileCodec.isEncrypted(raw)) {
      if (key == null) throw const VaultFileLockException();
      return VaultFileCodec.decrypt(raw, key, aadContext: 'block:$id');
    }
    if (key != null) _enqueueRawRewrite(id, raw);
    return raw;
  }

  /// 懒迁移：明文块文档经写链重写为密文。
  void _enqueueRawRewrite(String id, Uint8List plaintext) {
    _enqueue(id, () async {
      final key = await _currentKey();
      if (key == null) return;
      final sealed = await VaultFileCodec.encrypt(
        plaintext,
        key,
        aadContext: 'block:$id',
      );
      final file = File(await _pathFor(id));
      if (!await file.exists()) return; // 已被删除——不复活
      final tmp = File('${file.path}.${LocalIdGenerator.next('write')}.tmp');
      await tmp.writeAsBytes(sealed, flush: true);
      try {
        await tmp.rename(file.path);
      } on FileSystemException {
        if (!await file.exists()) rethrow;
        await file.delete();
        await tmp.rename(file.path);
      }
    }).catchError((_) {
      // 迁移失败静默（下次读取再试——幂等）。
    });
  }

  /// 读回收站条目内容（批次①c）：激活区 rename 进来的文件可能是密文，
  /// 解密后返回文本；锁定/损坏返回 null（调用方跳过——fail-closed）。
  Future<String?> _readTrashContent(File f) async {
    var raw = await f.readAsBytes();
    if (VaultFileCodec.isEncrypted(raw)) {
      final name = f.uri.pathSegments.last;
      if (!name.endsWith('.json')) return null;
      final id = name.substring(0, name.length - '.json'.length);
      final key = await _currentKey();
      if (key == null) return null;
      try {
        raw = await VaultFileCodec.decrypt(raw, key, aadContext: 'block:$id');
      } catch (_) {
        return null;
      }
    }
    return utf8.decode(raw);
  }

  /// 轻量文档头（不含 body 块树）。
  /// 列出全部文档头（updatedAt 倒序；缓存命中时零 IO）。
  Future<List<NoteBlockDocHeader>> listDocHeaders() async {
    final cached = _headerCache;
    if (cached != null) return cached;
    await _ensureDir();
    final result = <NoteBlockDocHeader>[];
    await for (final entity in (await _ensureDir()).list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final name = entity.uri.pathSegments.last;
        final fileId = name.substring(0, name.length - '.json'.length);
        var bytes = await entity.readAsBytes();
        if (VaultFileCodec.isEncrypted(bytes)) {
          // fail-closed：锁定状态不暴露加密文档（跳过，不中断列表）。
          final key = await _currentKey();
          if (key == null) continue;
          bytes = await VaultFileCodec.decrypt(
            bytes,
            key,
            aadContext: 'block:$fileId',
          );
        } else if (isValidId(fileId) && await _currentKey() != null) {
          _enqueueRawRewrite(fileId, bytes);
        }
        final root = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        final id = root['id'];
        if (id is! String || !isValidId(id)) continue;
        result.add(
          NoteBlockDocHeader(
            id: id,
            title: root['title'] as String? ?? '',
            tags: (root['tags'] as List? ?? const [])
                .whereType<String>()
                .toList(),
            createdAt:
                DateTime.tryParse(root['createdAt'] as String? ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0),
            updatedAt:
                DateTime.tryParse(root['updatedAt'] as String? ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0),
          ),
        );
      } catch (_) {
        continue; // 损坏文件跳过
      }
    }
    result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    _headerCache = result;
    return result;
  }

  /// 校验 ID 是否安全（仅允许字母、数字、下划线、短横线）。
  static bool isValidId(String id) => RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id);

  Future<String> _pathFor(String id) async {
    if (!isValidId(id)) {
      throw ArgumentError.value(id, 'id', '非法 ID（路径遍历防护）');
    }
    return '${(await _ensureDir()).path}${Platform.pathSeparator}$id.json';
  }

  /// 保存块文档到本地存储。
  ///
  /// 使用原子写入（先写 .tmp → 再 rename），并在覆盖前将现有文件
  /// 复制为 .bak 备份，确保写入中断时可恢复。
  Future<void> saveDocument(NoteBlockDoc doc) =>
      _enqueue(doc.id, () => _saveDocumentLocked(doc));

  /// saveDocument 的串行化主体（调用方必须已持有该 id 的写链）。
  Future<void> _saveDocumentLocked(NoteBlockDoc doc) async {
    if (!isValidId(doc.id)) {
      throw ArgumentError.value(doc.id, 'doc.id', '文档 ID 不合法');
    }
    await _ensureDir();
    var data = utf8.encode(
      const JsonEncoder.withIndent('  ').convert(doc.toJson()),
    );
    // 批次①c：有主密钥 → 信封加密（AAD 绑定 block:<id>）。
    final key = await _currentKey();
    if (key != null) {
      data = await VaultFileCodec.encrypt(data, key, aadContext: 'block:${doc.id}');
    }
    final path = await _pathFor(doc.id);
    final file = File(path);
    final tmp = File('$path.${LocalIdGenerator.next('write')}.tmp');
    await tmp.writeAsBytes(data, flush: true);
    if (await file.exists()) {
      try {
        await file.copy('$path.bak');
      } catch (_) {
        // 备份失败不阻塞写入
      }
    }
    try {
      await tmp.rename(path);
    } on FileSystemException {
      if (!await file.exists()) rethrow;
      await file.delete();
      await tmp.rename(path);
    }
    onWrite?.call();
  }

  /// 加载指定 ID 的块文档。不存在返回 null，损坏时尝试 .bak 恢复。
  Future<NoteBlockDoc?> loadDocument(String pageId) async {
    await _ensureDir();
    final path = await _pathFor(pageId);
    final file = File(path);
    final backup = File('$path.bak');
    if (!await file.exists() && !await backup.exists()) return null;
    Future<Uint8List> prepared(File source) async =>
        _prepareDocBytes(pageId, await source.readAsBytes());
    try {
      return NoteBlockDoc.fromJson(
        jsonDecode(utf8.decode(await prepared(await file.exists() ? file : backup)))
            as Map<String, dynamic>,
      );
    } catch (_) {
      if (!await backup.exists()) rethrow;
      return NoteBlockDoc.fromJson(
        jsonDecode(utf8.decode(await prepared(backup)))
            as Map<String, dynamic>,
      );
    }
  }

  /// 删除指定 ID 的块文档（M12.6：软删除——移入回收站，30 天保留，
  /// 可经 [restoreDocument] 恢复；与画布 StorageService 的 M-06 策略一致）。
  ///
  /// P0-H3：原子化——先写 sidecar 元数据（删除时间），再把激活文件
  /// **rename** 到回收站（同卷单次原子操作），不再有「写 trash 与删激活
  /// 之间可被自动保存插入」的窗口；rename 失败时回退旧 envelope 流程。
  /// 返回是否实际移动了文件。
  Future<bool> deleteDocument(String pageId) =>
      _enqueue(pageId, () => _deleteDocumentLocked(pageId));

  Future<bool> _deleteDocumentLocked(String pageId) async {
    final active = File(await _pathFor(pageId));
    if (!await active.exists()) return false;
    final trashFile = await _trashPathFor(pageId);
    final metaFile = File('$trashFile.meta.json');
    final metaTmp = File('$trashFile.meta.tmp');
    await metaTmp.writeAsString(
      jsonEncode({'deletedAt': DateTime.now().toIso8601String()}),
      flush: true,
    );
    await metaTmp.rename(metaFile.path);
    try {
      await active.rename(trashFile);
    } on FileSystemException {
      // 回退：读内容→写 envelope→删激活（非原子，仅 rename 不可用时）
      final doc = await loadDocument(pageId);
      if (doc == null) return false;
      final tmp = File('$trashFile.tmp');
      await tmp.writeAsString(
        jsonEncode({
          'deletedAt': DateTime.now().toIso8601String(),
          'document': doc.toJson(),
        }),
        flush: true,
      );
      await tmp.rename(trashFile);
      await _removeActiveFiles(pageId);
      onWrite?.call();
      return true;
    }
    await _removeBak(pageId);
    onWrite?.call();
    return true;
  }

  Future<void> _removeBak(String pageId) async {
    try {
      final backup = File('${await _pathFor(pageId)}.bak');
      if (await backup.exists()) await backup.delete();
    } catch (_) {
      // 备份删除失败忽略
    }
  }

  /// 彻底删除（不经回收站）：删除笔记页时联动清理迁移副本使用。
  Future<bool> purgeDocument(String pageId) =>
      _enqueue(pageId, () => _purgeDocumentLocked(pageId));

  Future<bool> _purgeDocumentLocked(String pageId) async {
    await _removeActiveFiles(pageId);
    try {
      final trashFile = await _trashPathFor(pageId);
      final f = File(trashFile);
      if (await f.exists()) await f.delete();
      final meta = File('$trashFile.meta.json');
      if (await meta.exists()) await meta.delete();
    } catch (_) {
      // 回收站文件不存在时忽略。
    }
    onWrite?.call();
    return true;
  }

  Future<void> _removeActiveFiles(String pageId) async {
    final path = await _pathFor(pageId);
    final file = File(path);
    if (await file.exists()) await file.delete();
    try {
      final backup = File('$path.bak');
      if (await backup.exists()) await backup.delete();
    } catch (_) {
      // 备份删除失败忽略
    }
  }

  /// 解码回收站条目：兼容两种格式——
  /// 旧 envelope（{deletedAt, document}）与 M12.6b 原子格式
  /// （裸文档 json + `<id>.meta.json` sidecar；meta 缺失时用文件修改时间）。
  ({NoteBlockDoc doc, DateTime deletedAt})? _decodeTrashEntry(
    String content,
    File source,
  ) {
    try {
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) return null;
      final docRaw = decoded['document'];
      if (docRaw is Map<String, dynamic>) {
        final deletedAt = DateTime.tryParse(
          decoded['deletedAt'] as String? ?? '',
        );
        if (deletedAt == null) return null;
        return (doc: NoteBlockDoc.fromJson(docRaw), deletedAt: deletedAt);
      }
      final doc = NoteBlockDoc.fromJson(decoded);
      final meta = File('${source.path}.meta.json');
      var deletedAt = DateTime.tryParse(
        meta.existsSync() ? meta.readAsStringSync() : '',
      );
      deletedAt ??= source.lastModifiedSync();
      return (doc: doc, deletedAt: deletedAt);
    } catch (_) {
      return null;
    }
  }

  /// 列出回收站条目（按删除时间倒序）。
  Future<List<({NoteBlockDoc doc, DateTime deletedAt})>> listTrash() async {
    final dir = await _ensureTrashDir();
    final entries = <({NoteBlockDoc doc, DateTime deletedAt})>[];
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      if (entity.path.endsWith('.meta.json')) continue;
      try {
        final entry = _decodeTrashEntry(await _readTrashContent(entity) ?? '', entity);
        if (entry != null) entries.add(entry);
      } catch (_) {
        continue; // 损坏条目跳过
      }
    }
    entries.sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
    return entries;
  }

  /// 从回收站恢复（若激活区已存在同 ID 文档则拒绝，返回 false）。
  Future<bool> restoreDocument(String pageId) =>
      _enqueue(pageId, () => _restoreDocumentLocked(pageId));

  Future<bool> _restoreDocumentLocked(String pageId) async {
    final trashFile = await _trashPathFor(pageId);
    final f = File(trashFile);
    if (!await f.exists()) return false;
    final active = File(await _pathFor(pageId));
    if (await active.exists()) return false; // 同 ID 已存在，拒绝覆盖
    final entry = _decodeTrashEntry(await _readTrashContent(f) ?? '', f);
    if (entry == null) {
      // 旧 envelope 格式：恢复内部文档对象
      try {
        final content = await _readTrashContent(f);
        if (content == null) return false;
        final decoded = jsonDecode(content);
        if (decoded is Map<String, dynamic> &&
            decoded['document'] is Map<String, dynamic>) {
          await saveDocument(
            NoteBlockDoc.fromJson(decoded['document'] as Map<String, dynamic>),
          );
          await f.delete();
          return true;
        }
      } catch (_) {
        return false;
      }
      return false;
    }
    // 新原子格式：rename 回激活区
    await f.rename(active.path);
    final meta = File('$trashFile.meta.json');
    if (meta.existsSync()) meta.deleteSync();
    onWrite?.call();
    return true;
  }

  /// 从回收站彻底删除单条。
  Future<bool> purgeFromTrash(String pageId) =>
      _enqueue(pageId, () => _purgeFromTrashLocked(pageId));

  Future<bool> _purgeFromTrashLocked(String pageId) async {
    final trashFile = await _trashPathFor(pageId);
    final f = File(trashFile);
    if (!await f.exists()) return false;
    await f.delete();
    final meta = File('$trashFile.meta.json');
    if (meta.existsSync()) meta.deleteSync();
    onWrite?.call();
    return true;
  }

  /// 清理过期回收站条目（默认 30 天，与画布 M-06 策略一致）。
  /// 返回清理条数。listIds 会自动触发（惰性清理）。
  Future<int> purgeExpiredTrash({int retainDays = 30}) => _enqueue(
    'trash:$retainDays',
    () async {
      final dir = await _ensureTrashDir();
      var purged = 0;
      final cutoff = DateTime.now().subtract(Duration(days: retainDays));
      await for (final entity in dir.list()) {
        if (entity is! File || !entity.path.endsWith('.json')) continue;
        if (entity.path.endsWith('.meta.json')) continue;
        try {
          final entry = _decodeTrashEntry(
            await _readTrashContent(entity) ?? '',
            entity,
          );
          if (entry != null && entry.deletedAt.isBefore(cutoff)) {
            await entity.delete();
            final meta = File('${entity.path}.meta.json');
            if (meta.existsSync()) meta.deleteSync();
            purged++;
          }
        } catch (_) {
          continue;
        }
      }
      return purged;
    },
  );

  Directory? _trashDir;

  Future<Directory> _ensureTrashDir() async {
    if (_trashDir != null) return _trashDir!;
    final base = await _baseDir();
    final dir = Directory(
      '${base.path}${Platform.pathSeparator}blockdocs_trash',
    );
    if (!await dir.exists()) await dir.create(recursive: true);
    _trashDir = dir;
    return dir;
  }

  Future<String> _trashPathFor(String id) async {
    if (!isValidId(id)) {
      throw ArgumentError.value(id, 'id', '非法 ID（路径遍历防护）');
    }
    return '${(await _ensureTrashDir()).path}${Platform.pathSeparator}$id.json';
  }

  DateTime? _lastTrashPurge;

  /// 列出所有块文档 ID（不含 .json 后缀）。惰性清理过期回收站条目。
  ///
  /// P1-H4（审计 2026-08-31）：清理节流为 1 小时一次——listIds 是列表
  /// 热路径（反向链接面板/AllDocs/首页刷新都会调用），每次全盘扫描
  /// 回收站会造成可感知卡顿。
  Future<List<String>> listIds() async {
    await _ensureDir();
    final now = DateTime.now();
    final last = _lastTrashPurge;
    if (last == null || now.difference(last) > const Duration(hours: 1)) {
      _lastTrashPurge = now;
      try {
        await purgeExpiredTrash();
      } catch (_) {}
    }
    final result = <String>[];
    await for (final entity in (await _ensureDir()).list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final name = entity.path.split(Platform.pathSeparator).last;
      result.add(name.substring(0, name.length - 5)); // 去掉 .json
    }
    return result;
  }

  /// 全量加载所有块文档（完整解析，含块树）。
  /// 高频调用方（如反向链接面板）请在上层做缓存——本方法每次全量 IO。
  Future<List<NoteBlockDoc>> loadAll() async {
    final docs = <NoteBlockDoc>[];
    for (final id in await listIds()) {
      final d = await loadDocument(id);
      if (d != null) docs.add(d);
    }
    return docs;
  }

  /// 生成唯一 ID（前缀可自定义，默认 'doc'）。
  static String newId([String prefix = 'doc']) => LocalIdGenerator.next(prefix);
}

/// 文档轻量头信息（P2-M5）：列表装配只取头部字段，避免构建整棵块树。
class NoteBlockDocHeader {
  const NoteBlockDocHeader({
    required this.id,
    required this.title,
    required this.tags,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final List<String> tags;
  final DateTime createdAt;
  final DateTime updatedAt;
}
