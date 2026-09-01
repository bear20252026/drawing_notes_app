import 'package:drawing_notes_app/core/storage/app_data_root.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';


import 'package:drawing_notes_app/core/storage/encryption_service.dart';
import 'package:drawing_notes_app/core/security/media_crypto_service.dart';
import 'package:drawing_notes_app/core/storage/vault_file_codec.dart';
import 'package:drawing_notes_app/core/storage/vfs/vault_service.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook_repository.dart';
import 'package:drawing_notes_app/core/storage/local_id_generator.dart';
import 'package:drawing_notes_app/core/notes_accessor.dart';

/// 笔记本本地存储服务。
///
/// 目录结构（应用文档目录下）：
///   `appDir/notebooks/`
///     `notebookId.json` —— 笔记本工程文件（含全部页面、画布、文字/图片块）
///   `appDir/notebook_images/`
///     `pageId_xxx.png` —— 插入页面中的图片副本
///
/// 与 [StorageService] 一样：全部本地操作、无网络请求；
/// 图片以副本方式保存进应用目录，保证离线可用且原文件删除不影响笔记。
///
/// 密码保护（C3/C5）：启用加密的笔记本以 AES-GCM 密文存储页面内容，
/// 明文不落盘；打开时需输入密码解密（见 [encryptNotebook]/[decryptNotebook]）。
///
/// 已通过 [NotebookRepository] 接口抽象（见 repository.dart），
/// 未来替换为云同步实现时无需改动上层逻辑。
class NotebookStorage implements NotebookRepository, INotebookAccessor {
  NotebookStorage({
    this.directoryProvider,
    this.vaultService,
    this.keyProvider,
  });

  /// 主密钥提供者（加密底座批次①c）：返回解锁态主密钥时，笔记本工程文件
  /// JSON 以 DNV 信封落盘（AAD 绑定 `nb:<id>`）、页面图片以 DNV 信封落盘
  /// （AAD 绑定 `file:<basename>`）；null 时保持既有行为明文/DAN 兼容。
  final Future<Uint8List?> Function()? keyProvider;

  /// VFS 媒体仓库（可选——解锁时注入——新媒体写 VFS 对象——双轨：
  /// s3-encryption-gateway 双读窗口模式——旧媒体 DAN 文件兼容读）。
  VaultService? vaultService;

  /// 写成功回调（首页刷新修复①）：笔记本保存/删除落盘成功后触发，由装配层
  /// 注入（AppServices.bumpDataVersion）。所有保存路径（save/encryptAndSave）
  /// 均汇入 _writeNotebook 单一出口，此处通知即全覆盖。
  void Function()? onWrite;

  // ---- INotebookAccessor 跨功能契约适配（S4b：NotebookStorage 直接实现契约）----

  @override
  Future<List<NotebookSearchDocument>> listSearchDocuments() async {
    final notebooks = await listAll();
    return [
      for (final notebook in notebooks)
        NotebookSearchDocument(
          id: notebook.id,
          title: notebook.title,
          searchSummary: notebook.searchSummary,
          pages: [
            for (final page in notebook.pages)
              NotebookSearchPage(
                id: page.id,
                title: page.title,
                textContents: [
                  for (final textItem in page.textItems) textItem.text,
                ],
              ),
          ],
        ),
    ];
  }

  @override
  bool get isStorageAvailable => true;

  /// 目录提供者：测试时可注入临时目录，生产环境使用系统文档目录。
  final Future<Directory> Function()? directoryProvider;

  static const EncryptionService _encryption = EncryptionService();

  Directory? _notebooksDir;
  Directory? _imagesDir;

  /// 按笔记本 ID 隔离的落盘队列：同一笔记本保序，不同笔记本不共享临时文件。
  final Map<String, Future<void>> _writeTails = <String, Future<void>>{};

  Future<Uint8List?> _currentKey() async {
    final provider = keyProvider;
    if (provider == null) return null;
    return provider();
  }

  /// 读取后的字节准备（批次①c，与 StorageService/NoteBlockDocStore 同纪律）：
  /// 密文+解锁 → 解密；密文+锁定 → [VaultFileLockException]；
  /// 明文+有钥 → 原样返回并经写尾队列懒迁移（[migrate] 为 false 时仅解密，
  /// 不排队迁移——备份回退路径用，避免用备份内容覆盖主文件）。
  Future<Uint8List> _prepareNotebookBytes(
    String id,
    Uint8List raw, {
    bool migrate = true,
  }) async {
    final key = await _currentKey();
    if (VaultFileCodec.isEncrypted(raw)) {
      if (key == null) throw const VaultFileLockException();
      return VaultFileCodec.decrypt(raw, key, aadContext: 'nb:$id');
    }
    if (key != null && migrate) _enqueueRawRewrite(id, raw);
    return raw;
  }

  /// 懒迁移：明文笔记本经写尾队列重写为 DNV 密文。
  void _enqueueRawRewrite(String id, Uint8List plaintext) {
    final previous = _writeTails[id] ?? Future<void>.value();
    late final Future<void> operation;
    operation = previous.catchError((_) {}).then((_) async {
      final key = await _currentKey();
      if (key == null) return;
      final sealed = await VaultFileCodec.encrypt(
        plaintext,
        key,
        aadContext: 'nb:$id',
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
    });
    _writeTails[id] = operation;
    operation.catchError((_) {
      // 迁移失败静默（下次读取再试——幂等）。
      if (identical(_writeTails[id], operation)) _writeTails.remove(id);
    });
  }

  Future<Directory> _baseDir() async {
    final provider = directoryProvider;
    if (provider != null) return provider();
    return AppDataRoot.defaultRootDir();
  }

  Future<Directory> _ensureNotebooksDir() async {
    if (_notebooksDir != null) return _notebooksDir!;
    final base = await _baseDir();
    final dir = Directory('${base.path}${Platform.pathSeparator}notebooks');
    if (!await dir.exists()) await dir.create(recursive: true);
    _notebooksDir = dir;
    return dir;
  }

  /// 公开的图片目录提供（供编辑器粘贴图片保存用，包装私有实现）。
  Future<Directory> ensureImagesDir() => _ensureImagesDir();

  Future<Directory> _ensureImagesDir() async {
    if (_imagesDir != null) return _imagesDir!;
    final base = await _baseDir();
    final dir = Directory(
      '${base.path}${Platform.pathSeparator}notebook_images',
    );
    if (!await dir.exists()) await dir.create(recursive: true);
    _imagesDir = dir;
    return dir;
  }

  /// 校验 ID 是否安全（仅允许字母、数字、下划线）。
  ///
  /// 安全说明：ID 直接拼入文件路径，若允许 `../` 等字符会造成路径遍历。
  /// 所有合法 ID 由 [newId] 生成；此校验作为防御性边界。
  /// 链 9 修复（军工审计 2026-08-15）：允许 '-'（与 StorageService/
  /// DocumentCodec 一致——'-' 无路径遍历风险）。
  static bool isValidId(String id) => RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id);

  /// H-03 部分落地（专家审计 2026-08-15）：图片源文件大小上限。
  static const int _maxImageSourceBytes = 50 * 1024 * 1024; // 50MB

  Future<String> _pathFor(String id) async {
    // C-02 修复（专家审计 2026-08-15）：assert-only 校验在 release 失效——
    // 运行时强制校验（load/save/delete 均经此统一防护路径遍历）。
    if (!isValidId(id)) {
      throw ArgumentError.value(id, 'id', '非法 ID（路径遍历防护）');
    }
    return '${(await _ensureNotebooksDir()).path}${Platform.pathSeparator}$id.json';
  }

  /// 原子写入笔记本文件（不涉及加密判断；被 [save] 调用）。
  Future<String> _writeNotebook(Notebook notebook) async {
    if (!isValidId(notebook.id)) {
      throw ArgumentError.value(notebook.id, 'notebook.id', '笔记本 ID 不合法');
    }
    await _ensureNotebooksDir();
    // 在排队前编码快照，避免用户继续编辑时旧任务写入可变的混合状态。
    final data = utf8.encode(
      const JsonEncoder.withIndent('  ').convert(notebook.toJson()),
    );
    final finalPath = await _pathFor(notebook.id);
    final id = notebook.id;
    final previous = _writeTails[id] ?? Future<void>.value();
    late final Future<void> operation;
    operation = previous.catchError((_) {}).then((_) async {
      // 批次①c：保险库解锁 → DNV 信封（AAD 绑定 nb:<id>）；锁定 → 明文
      // 兼容（既有单笔记本密码/DAN 层不受影响，读取时懒迁移）。
      final key = await _currentKey();
      final payload = key == null
          ? data
          : await VaultFileCodec.encrypt(data, key, aadContext: 'nb:$id');
      await _writeNotebookBytes(File(finalPath), payload);
    });
    _writeTails[id] = operation;
    try {
      await operation;
      onWrite?.call();
      return finalPath;
    } finally {
      if (identical(_writeTails[id], operation)) _writeTails.remove(id);
    }
  }

  Future<void> _writeNotebookBytes(File destination, List<int> data) async {
    final tmp = File(
      '${destination.path}.${LocalIdGenerator.next('write')}.tmp',
    );
    await tmp.writeAsBytes(data, flush: true);
    if (await destination.exists()) {
      try {
        await destination.copy('${destination.path}.bak');
      } catch (_) {
        // 备份是恢复保障；其失败不阻塞当前写入。
      }
    }
    try {
      await tmp.rename(destination.path);
    } on FileSystemException {
      if (!await destination.exists()) rethrow;
      await destination.delete();
      await tmp.rename(destination.path);
    }
  }

  /// 加载笔记本。不存在返回 null，损坏抛出异常。
  ///
  /// 批次①c：DNV 密文 → 解锁解密 / 锁定抛 [VaultFileLockException]；
  /// 明文+解锁 → 懒迁移（备份回退路径不迁移，避免覆盖主文件）。
  @override
  Future<Notebook?> load(String id) async {
    await _ensureNotebooksDir();
    final file = File(await _pathFor(id));
    final backup = File('${file.path}.bak');
    if (!await file.exists() && !await backup.exists()) return null;
    try {
      final bytes = await (await file.exists() ? file : backup).readAsBytes();
      final prepared = await _prepareNotebookBytes(id, bytes);
      return Notebook.fromJson(
        jsonDecode(utf8.decode(prepared)) as Map<String, dynamic>,
      );
    } on VaultFileLockException {
      rethrow; // 锁定不回退备份——备份同为密文，fail-closed
    } catch (_) {
      if (!await backup.exists()) rethrow;
      final bytes = await backup.readAsBytes();
      final prepared = await _prepareNotebookBytes(id, bytes, migrate: false);
      return Notebook.fromJson(
        jsonDecode(utf8.decode(prepared)) as Map<String, dynamic>,
      );
    }
  }

  /// 列出所有笔记本（按更新时间倒序）。
  ///
  /// 批次①c：DNV 密文 → 解锁解密（明文懒迁移）/ 锁定跳过该条目
  /// （fail-closed，不中断列表）。
  @override
  Future<List<Notebook>> listAll() async {
    await _ensureNotebooksDir();
    final result = <Notebook>[];
    await for (final entity in (await _ensureNotebooksDir()).list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final name = entity.uri.pathSegments.last;
        final id = name.substring(0, name.length - '.json'.length);
        final raw = await entity.readAsBytes();
        if (VaultFileCodec.isEncrypted(raw)) {
          final key = await _currentKey();
          if (key == null) continue; // 锁定——跳过（fail-closed）
        }
        final bytes = await _prepareNotebookBytes(id, raw);
        result.add(
          Notebook.fromJson(
            jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
          ),
        );
      } catch (_) {
        // 跳过损坏文件，不中断列表。
        continue;
      }
    }
    result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return result;
  }

  /// 删除笔记本（同时清理其关联图片副本）。返回是否删除成功。
  @override
  Future<bool> delete(String id) async {
    await _ensureNotebooksDir();
    final file = File(await _pathFor(id));
    if (!await file.exists()) return false;
    // 先收集图片路径再删除文件：文件删除后无法再读取其内容。
    final imagePaths = await _collectImagePaths(id);
    await file.delete();
    // 清理该笔记本所有页面引用的图片副本（尽力而为）。
    for (final p in imagePaths) {
      try {
        // C-01 修复（专家审计 2026-08-15）：图片路径来自笔记 JSON（不可信
        // 数据）——删除前验证受管目录 + 非符号链接（CVE-2026-55667 同源：
        // 符号链接跟随可删除越界文件）。仅删除受管目录内的普通文件。
        final managed = await _managedImagePathOrNull(p);
        if (managed == null) continue;
        final type = await FileSystemEntity.type(managed, followLinks: false);
        if (type != FileSystemEntityType.file) continue;
        final f = File(managed);
        if (await f.exists()) await f.delete();
      } catch (_) {
        // 单个图片删除失败忽略。
      }
    }
    onWrite?.call();
    return true;
  }

  /// 收集笔记本所有页面引用的图片副本路径（不修改任何文件）。
  ///
  /// 读取失败（文件损坏等）时返回空列表，不影响笔记本删除本身。
  Future<List<String>> _collectImagePaths(String id) async {
    try {
      final notebook = await load(id);
      if (notebook == null) return const [];
      return <String>{
        for (final page in notebook.pages)
          for (final img in page.imageItems) img.filePath,
      }.toList();
    } catch (_) {
      return const [];
    }
  }

  /// C-01 修复（专家审计 2026-08-15）：验证路径位于受管图片目录内
  /// （防笔记 JSON 携带外部路径驱动越界删除——CVE-2026-55667 同源）。
  Future<String?> _managedImagePathOrNull(String path) async {
    if (path.isEmpty) return null;
    try {
      final root = await _ensureImagesDir();
      final image = File(path).absolute;
      final parentPath = image.parent.absolute.uri.normalizePath().toFilePath();
      final rootPath = root.absolute.uri.normalizePath().toFilePath();
      if (parentPath != rootPath) return null;
      return image.uri.normalizePath().toFilePath();
    } catch (_) {
      return null;
    }
  }

  /// 保存页面图片副本，返回副本的绝对路径。
  ///
  /// [sourcePath] 为用户选择的图片原路径；[pageId] 用于文件名分组。
  @override
  Future<String> storeImage(String sourcePath, String pageId) async {
    if (!isValidId(pageId)) {
      throw ArgumentError('非法 pageId: $pageId');
    }
    // 媒体 VFS 双轨（2026-08-16）：新媒体写入 VFS 对象（'vfs:' 标记——
    // 解锁会话内 VaultService 注入——s3-encryption-gateway 双读窗口模式）；
    // 旧媒体 DAN 文件保持兼容读。
    final vfs = vaultService;
    if (vfs != null && vfs.hasKey) {
      final src = File(sourcePath);
      if (!await src.exists()) {
        throw FileSystemException('源图片不存在', sourcePath);
      }
      final id = 'media/${pageId}_${DateTime.now().microsecondsSinceEpoch}';
      await vfs.putObject(id, plain: await src.readAsBytes(), type: 'media');
      return 'vfs:$id';
    }
    final src = File(sourcePath);
    if (!await src.exists()) throw FileSystemException('源图片不存在', sourcePath);
    // H-03 部分落地（专家审计 2026-08-15）：源文件大小配额（防超大图片
    // 资产入库；完整媒体加密——每笔记 DEK + 渲染解密——评估为数据保密
    // 重构专项，涉及渲染管线跨域改造，见 Inqrypt/heritage 分层加密模式）。
    if (await src.length() > _maxImageSourceBytes) {
      throw FileSystemException('图片源文件过大（超过 50MB 限制）', sourcePath);
    }
    // 扩展名白名单：只接受常见图片格式，防止任意文件以图片身份入库。
    final ext = sourcePath.contains('.')
        ? sourcePath.split('.').last.toLowerCase()
        : '';
    const allowed = {
      'png',
      'jpg',
      'jpeg',
      'gif',
      'webp',
      'bmp',
      'svg',
      'heic',
      'heif',
      'tif',
      'tiff',
    };
    final safeExt = allowed.contains(ext) ? ext : 'png';
    final dir = await _ensureImagesDir();
    final target = File(
      '${dir.path}${Platform.pathSeparator}${pageId}_${DateTime.now().microsecondsSinceEpoch}.$safeExt',
    );
    try {
      // H-03 双端接入（专家审计 2026-08-15）+ 批次①c 三级加密封支：
      // ① 会话密钥已注入（加密笔记本解锁场景）→ DAN 文件头加密；
      // ② 保险库解锁 → DNV 信封（AAD 绑定 file:<basename>）；
      // ③ 均未解锁 → 明文写入（旧数据兼容，读取时懒迁移）。
      final bytes = await src.readAsBytes();
      final Uint8List stored;
      if (MediaCryptoService.instance.isActive) {
        stored = await MediaCryptoService.instance.encryptFile(bytes);
      } else {
        final key = await _currentKey();
        stored = key == null
            ? bytes
            : await VaultFileCodec.encrypt(
                bytes,
                key,
                aadContext: VaultFileCodec.contextForPath(target.path),
              );
      }
      await target.writeAsBytes(stored, flush: true);
      return target.path;
    } catch (_) {
      // 不让加密或写入异常留下可被清理器误认为有效媒体的半成品。
      try {
        if (await target.exists()) await target.delete();
      } catch (_) {
        // 清理失败不覆盖原始异常。
      }
      rethrow;
    }
  }

  /// 旧明文媒体迁移（H-03 专家审计 2026-08-15）：解锁后批量重加密——
  /// payload-plugins 批量加密器模式（幂等——已 DAN 密文跳过）。
  /// 返回迁移的文件数；未解锁（会话密钥未注入）返回 0。
  Future<int> migrateLegacyMedia() async {
    final service = MediaCryptoService.instance;
    if (!service.isActive) return 0; // 未解锁——不迁移
    final dir = await _ensureImagesDir();
    var migrated = 0;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      try {
        final bytes = await entity.readAsBytes();
        if (MediaCryptoService.isEncryptedFile(bytes)) continue;
        await entity.writeAsBytes(
          await service.encryptFile(bytes),
          flush: true,
        );
        migrated++;
      } catch (_) {
        // 单个迁移失败忽略（后续解锁再试——幂等）。
      }
    }
    return migrated;
  }

  /// 全局媒体加密盐（H-03 方案 B 2026-08-15）：密码模式媒体加密的派生
  /// 盐——明文持久（盐无需保密），跨会话一致（解密媒体重派生同 key）。
  Future<List<int>> ensureMediaSalt() async {
    final base = await _baseDir();
    final file = File('${base.path}${Platform.pathSeparator}media_crypto_salt');
    if (await file.exists()) {
      final bytes = await file.readAsBytes();
      if (bytes.length >= 16) return bytes.take(16).toList();
    }
    final salt = MediaCryptoService.generateSalt();
    await file.writeAsBytes(salt, flush: true);
    return salt;
  }

  /// 启用密码保护并保存：把页面内容 AES-GCM 加密为载荷，明文不落盘。
  Future<String> encryptAndSave(Notebook notebook, String password) async {
    // 第一步合规（2026-08-16 专家审计最优先行动②）：加密笔记本不生成
    // 明文 searchSummary——"废除默认明文 searchSummary"。未来 K_note
    // 密钥层级落地后摘要可加密存储（解锁会话内搜索——安全）。
    final payloadJson = jsonEncode({
      'pages': notebook.pages.map((p) => p.toJson()).toList(),
    });
    notebook.encrypted = true;
    notebook.encryptedPayload = await _encryption.encryptWithPasswordAad(
      notebookId: notebook.id,
      plaintext: payloadJson,
      password: password,
    );
    // 直接原子写入（toJson 中 encrypted 时 pages 序列化为空，仅存密文载荷）。
    // 注意：不能走 save()——save 对"加密且内存有明文页面"会抛 StateError
    // （这是编辑会话的守卫），而加密保存时内存本来就有明文页面。
    return _writeNotebook(notebook);
  }

  /// 用密码解密加密笔记本的页面内容（密码错误抛 [FormatException]）。
  /// 成功后将页面填充回 [notebook.pages] 并返回 true。
  ///
  /// 注意：解密后**保留** [encryptedPayload]（密文仍是持久化的唯一内容源），
  /// 否则后续保存会把 `pages: []` 写入磁盘、永久丢失全部加密内容
  /// （评审发现 P1）。
  Future<bool> decryptNotebook(Notebook notebook, String password) async {
    final payload = notebook.encryptedPayload;
    if (payload == null) return false;
    // 密码模式 v4（H-06 补全）：AAD 绑定 notebook.id——v4 优先，v3 旧数据
    // 回退（兼容期新旧并存）。
    final clear = await _encryption.decryptWithPasswordAad(
      notebookId: notebook.id,
      encryptedJson: payload,
      password: password,
    );
    final map = jsonDecode(clear) as Map<String, dynamic>;
    final pages = (map['pages'] as List? ?? const [])
        .map((e) => NotebookPage.fromJson(e as Map<String, dynamic>))
        .toList();
    notebook.pages
      ..clear()
      ..addAll(pages);
    // 保留 encryptedPayload：密文仍是持久化的唯一副本；
    // 修改加密笔记本时由调用方重新加密（见 save 的重加密逻辑）。
    return true;
  }

  /// 保存笔记本：加密笔记本不落盘明文 pages（评审发现 P1 修复）。
  ///
  /// - 非加密：直接原子写入；
  /// - 加密且未修改（pages 为空、密文仍在）：保留原密文写入，避免覆盖为空；
  /// - 加密且内存有明文页面：需要密钥才能重加密——若无密钥则拒绝保存
  ///   （防止静默清空磁盘内容），由调用方走 [encryptAndSave]。
  @override
  Future<String> save(Notebook notebook) async {
    if (notebook.encrypted) {
      final payload = notebook.encryptedPayload;
      if (payload != null && notebook.pages.isEmpty) {
        // 解密后未修改：保留原密文，避免覆盖为空。
        return _writeNotebook(notebook);
      }
      throw StateError(
        '加密笔记本需要会话密码才能保存，请使用 encryptAndSave',
      );
    }
    return _writeNotebook(notebook);
  }

  /// 生成唯一 ID。
  static String newId(String prefix) => LocalIdGenerator.next(prefix);
}
