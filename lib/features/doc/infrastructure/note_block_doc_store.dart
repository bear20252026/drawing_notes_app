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
///
/// L-03 拆分：回收站域与文件密码域为本库的 part（同库共享私有成员，
/// 行为与单文件完全一致）；part 用库名关联，不依赖相对路径解析。
library note_block_doc_store;

import 'package:drawing_notes_app/core/storage/app_data_root.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drawing_notes_app/core/security/session_secrets.dart';
import 'package:drawing_notes_app/core/storage/encryption_service.dart';
import 'package:drawing_notes_app/core/storage/local_id_generator.dart';
import 'package:drawing_notes_app/core/storage/vault_file_codec.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block_doc.dart';


part 'note_block_doc_store_trash.dart';
part 'note_block_doc_store_password.dart';
/// 笔记（块文档）受独立文件密码保护且本会话未解锁（N2）。
///
/// loadDocument 在锁定态抛出此异常——调用方（打开路径）应先走
/// UnlockFlow 解锁（verifyBlockDocPassword 成功即入会话 DEK 缓存）。
class BlockDocLockedException implements Exception {
  const BlockDocLockedException();

  @override
  String toString() => 'BlockDocLockedException: 笔记已加密且会话未解锁';
}

/// 块文档本地存储门面。
///
/// 用法：
/// ```dart
/// final store = NoteBlockDocStore();
/// await store.saveDocument(doc);
/// final loaded = await store.loadDocument(doc.id);
/// await store.deleteDocument(doc.id);
/// ```
class NoteBlockDocStore implements SessionSecretsHolder {
  /// 创建块文档存储门面。
  ///
  /// [directoryProvider] 为可选的目录提供者回调。测试时可注入临时目录，
  /// 生产环境默认使用系统文档目录。
  NoteBlockDocStore({this.directoryProvider, this.keyProvider}) {
    // P1 修复：注册会话机密清理——切后台回锁时 DEK 一并擦除失效。
    SessionSecrets.register(this);
  }

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

  /// 回收站目录缓存（字段必须驻留主文件——extension 内禁止声明实例字段；
  /// 读写经 part 扩展方法，见 note_block_doc_store_trash.dart）。
  Directory? _trashDir;

  // ==== 文件密码（N2：笔记单文件接入 v5 双保护器体系） ====
  //
  // 受密文件 = v5 信封 JSON 直落盘（{"mode":"password","v":5,"slots",
  // "payload"}，AAD 绑定 blockdoc id）——不再叠加主密钥信封（与分页画布
  // v5 同口径：一层密码保护独立成立）。会话 DEK 缓存（LUKS 同款）：
  // 解锁成功缓存 DEK，续写 rewrap 免 PBKDF2 重派生。

  static const EncryptionService _encryption = EncryptionService();

  /// 会话 DEK 缓存：解锁成功（verifyBlockDocPassword/encryptAndSave/
  /// 改密/重置）后缓存，saveDocument 续写复用（零 PBKDF2）。
  final Map<String, List<int>> _sessionDeks = <String, List<int>>{};

  /// 该笔记本会话内是否已解锁文件密码（DEK 在缓存中）。
  bool isBlockDocUnlocked(String id) => _sessionDeks.containsKey(id);

  /// 清除会话 DEK（切后台锁屏 / 移除密码 / 删除文档后调用）。
  /// DEK 字节先擦除再移除（防内存残留）。
  /// 头信息缓存同步失效——列表立即回「加密笔记」占位，不泄露真实标题。
  void forgetBlockDocPassword(String id) {
    final dek = _sessionDeks.remove(id);
    if (dek != null) {
      for (var i = 0; i < dek.length; i++) {
        dek[i] = 0;
      }
      _headerCache = null;
    }
  }

  /// P1 修复：清空全部会话 DEK（切后台回锁经 [SessionSecrets] 联动）。
  /// 逐个字节擦除 + 头缓存失效；幂等、永不抛错。
  @override
  void clearAllSessionSecrets() {
    try {
      for (final dek in _sessionDeks.values) {
        try {
          for (var i = 0; i < dek.length; i++) {
            dek[i] = 0;
          }
        } catch (_) {}
      }
      _sessionDeks.clear();
      _headerCache = null;
    } catch (_) {}
  }

  /// 读取指定笔记的落盘字节；若为 v5 文件密码信封则返回其 JSON 串，
  /// 否则（不存在/主密钥信封/明文/损坏）返回 null。
  Future<String?> _readEnvelopeJson(String id) async {
    try {
      final file = File(await _pathFor(id));
      if (!await file.exists()) return null;
      final raw = await file.readAsBytes();
      if (VaultFileCodec.isEncrypted(raw)) return null; // 主密钥信封——非文件密码
      final text = utf8.decode(raw);
      return EncryptionService.isDualProtectorEnvelope(text) ? text : null;
    } catch (_) {
      return null;
    }
  }

  /// 该笔记是否受独立文件密码保护（v5 信封；不解密、不暴露内容）。
  Future<bool> isBlockDocPasswordProtected(String id) async =>
      await _readEnvelopeJson(id) != null;

  Future<Directory> _baseDir() async {
    final provider = directoryProvider;
    if (provider != null) return provider();
    return AppDataRoot.defaultRootDir();
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
          // N2：v5 文件密码信封不参与主密钥懒迁移（受密文件直落盘，
          // 不做主密钥双信封——见 _saveDocumentLocked 注释）。
          if (!EncryptionService.isDualProtectorEnvelope(utf8.decode(bytes))) {
            _enqueueRawRewrite(fileId, bytes);
          }
        }
        final text = utf8.decode(bytes);
        // N2：文件密码信封——会话已解锁（DEK 在缓存）解密出真实头信息；
        // 未解锁给锁定占位（标题/标签不泄露，fail-closed）。
        if (EncryptionService.isDualProtectorEnvelope(text)) {
          if (!isValidId(fileId)) continue;
          final dek = _sessionDeks[fileId];
          if (dek != null) {
            try {
              final clear = await _encryption.decryptBlockDocPayloadWithDek(
                docId: fileId,
                encryptedJson: text,
                dek: dek,
              );
              final root = jsonDecode(clear) as Map<String, dynamic>;
              result.add(
                NoteBlockDocHeader(
                  id: root['id'] as String? ?? fileId,
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
              continue;
            } catch (_) {
              continue; // 解密失败（DEK 失效/损坏）按损坏处理
            }
          }
          final stat = await entity.stat();
          result.add(
            NoteBlockDocHeader(
              id: fileId,
              title: '加密笔记',
              tags: const [],
              createdAt: stat.modified,
              updatedAt: stat.modified,
              locked: true,
            ),
          );
          continue;
        }
        final root = jsonDecode(text) as Map<String, dynamic>;
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
    final plaintext = utf8.encode(
      const JsonEncoder.withIndent('  ').convert(doc.toJson()),
    );

    // N2：文件密码拦截——受密文件续写必须走会话 DEK rewrap（v5 信封
    // 直落盘，仅重生成 payload 密文、槽位组原样保留——LUKS 语义）。
    // 无 DEK 时 fail-closed：绝不把明文覆盖到密文上（与 NotebookStorage
    // save 守卫同纪律）。DocPage 自动保存零改动——透明 rewrap。
    final envelope = await _readEnvelopeJson(doc.id);
    if (envelope != null) {
      final dek = _sessionDeks[doc.id];
      if (dek == null) {
        throw StateError('笔记「${doc.id}」已加密且会话未解锁：禁止明文覆盖');
      }
      final map = jsonDecode(envelope) as Map<String, dynamic>;
      final sealed = utf8.encode(
        await _encryption.rewrapBlockDocPayloadV5(
          docId: doc.id,
          map: map,
          dek: dek,
          plaintext: utf8.decode(plaintext),
        ),
      );
      await _writeFileAtomic(doc.id, sealed);
      return;
    }

    // 批次①c：有主密钥 → 信封加密（AAD 绑定 block:<id>）。
    var data = plaintext;
    final key = await _currentKey();
    if (key != null) {
      data = await VaultFileCodec.encrypt(
        data,
        key,
        aadContext: 'block:${doc.id}',
      );
    }
    await _writeFileAtomic(doc.id, data);
  }

  /// 原子写（bak 备份 + tmp + rename）——保存/设密/改密/重置/移除共用。
  Future<void> _writeFileAtomic(String id, List<int> data) async {
    final path = await _pathFor(id);
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
  ///
  /// N2：受独立文件密码保护（v5 信封）的笔记——会话已解锁（DEK 在
  /// 缓存）直接解密返回；未解锁抛 [BlockDocLockedException]（fail-closed，
  /// 调用方先走 UnlockFlow）。
  Future<NoteBlockDoc?> loadDocument(String pageId) async {
    await _ensureDir();
    final path = await _pathFor(pageId);
    final file = File(path);
    final backup = File('$path.bak');
    if (!await file.exists() && !await backup.exists()) return null;
    Future<NoteBlockDoc> parse(File source) async {
      final raw = await _prepareDocBytes(pageId, await source.readAsBytes());
      final text = utf8.decode(raw);
      if (EncryptionService.isDualProtectorEnvelope(text)) {
        final dek = _sessionDeks[pageId];
        if (dek == null) throw const BlockDocLockedException();
        final clear = await _encryption.decryptBlockDocPayloadWithDek(
          docId: pageId,
          encryptedJson: text,
          dek: dek,
        );
        return NoteBlockDoc.fromJson(jsonDecode(clear) as Map<String, dynamic>);
      }
      return NoteBlockDoc.fromJson(jsonDecode(text) as Map<String, dynamic>);
    }

    try {
      return await parse(await file.exists() ? file : backup);
    } on BlockDocLockedException {
      rethrow; // 锁定态不做 .bak 回退（fail-closed）
    } catch (_) {
      if (!await backup.exists()) rethrow;
      return parse(backup);
    }
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
  ///
  /// N2：受文件密码保护且未解锁的笔记跳过（fail-closed——反向链接/
  /// 搜索不泄露受密内容）。
  Future<List<NoteBlockDoc>> loadAll() async {
    final docs = <NoteBlockDoc>[];
    for (final id in await listIds()) {
      try {
        final d = await loadDocument(id);
        if (d != null) docs.add(d);
      } on BlockDocLockedException {
        continue; // 锁定态跳过（解锁后自然出现）
      }
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
    this.locked = false,
  });

  final String id;
  final String title;
  final List<String> tags;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// 是否受独立文件密码保护且本会话尚未解锁（N2）——
  /// 列表显示锁定占位（「加密笔记」），真实标题/标签不泄露。
  final bool locked;
}
