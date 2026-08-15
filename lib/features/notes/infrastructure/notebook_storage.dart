import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:drawing_notes_app/core/storage/encryption_service.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';
import 'package:drawing_notes_app/core/storage/local_id_generator.dart';
import 'package:drawing_notes_app/core/notes_accessor.dart';
import 'package:drawing_notes_app/core/storage/repository.dart';

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
  NotebookStorage({this.directoryProvider});

  // ---- INotebookAccessor 跨功能契约适配（S4b：NotebookStorage 直接实现契约）----

  @override
  NotebookPage? pageById(String notebookId, String pageId) => null;

  @override
  Future<List<Notebook>> listNotebooks() => listAll();

  @override
  bool get isStorageAvailable => true;

  /// 目录提供者：测试时可注入临时目录，生产环境使用系统文档目录。
  final Future<Directory> Function()? directoryProvider;

  static const EncryptionService _encryption = EncryptionService();

  Directory? _notebooksDir;
  Directory? _imagesDir;

  /// 按笔记本 ID 隔离的落盘队列：同一笔记本保序，不同笔记本不共享临时文件。
  final Map<String, Future<void>> _writeTails = <String, Future<void>>{};

  Future<Directory> _baseDir() async {
    final provider = directoryProvider;
    if (provider != null) return provider();
    return getApplicationDocumentsDirectory();
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

  Future<String> _pathFor(String id) async {
    assert(isValidId(id), '非法 ID: $id');
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
    operation = previous
        .catchError((_) {})
        .then((_) => _writeNotebookBytes(File(finalPath), data));
    _writeTails[id] = operation;
    try {
      await operation;
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
  @override
  Future<Notebook?> load(String id) async {
    await _ensureNotebooksDir();
    final file = File(await _pathFor(id));
    final backup = File('${file.path}.bak');
    if (!await file.exists() && !await backup.exists()) return null;
    try {
      final bytes = await (await file.exists() ? file : backup).readAsBytes();
      return Notebook.fromJson(
        jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
      );
    } catch (_) {
      if (!await backup.exists()) rethrow;
      final bytes = await backup.readAsBytes();
      return Notebook.fromJson(
        jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
      );
    }
  }

  /// 列出所有笔记本（按更新时间倒序）。
  @override
  Future<List<Notebook>> listAll() async {
    await _ensureNotebooksDir();
    final result = <Notebook>[];
    await for (final entity in (await _ensureNotebooksDir()).list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final bytes = await entity.readAsBytes();
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
        final f = File(p);
        if (await f.exists()) await f.delete();
      } catch (_) {
        // 单个图片删除失败忽略。
      }
    }
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

  /// 保存页面图片副本，返回副本的绝对路径。
  ///
  /// [sourcePath] 为用户选择的图片原路径；[pageId] 用于文件名分组。
  @override
  Future<String> storeImage(String sourcePath, String pageId) async {
    if (!isValidId(pageId)) {
      throw ArgumentError('非法 pageId: $pageId');
    }
    final dir = await _ensureImagesDir();
    final src = File(sourcePath);
    if (!await src.exists()) throw FileSystemException('源图片不存在', sourcePath);
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
    final target = File(
      '${dir.path}${Platform.pathSeparator}${pageId}_${DateTime.now().microsecondsSinceEpoch}.$safeExt',
    );
    await src.copy(target.path);
    return target.path;
  }

  /// 启用密码保护并保存：把页面内容 AES-GCM 加密为载荷，明文不落盘。
  Future<String> encryptAndSave(Notebook notebook, String password) async {
    final payloadJson = jsonEncode({
      'pages': notebook.pages.map((p) => p.toJson()).toList(),
    });
    notebook.encrypted = true;
    notebook.encryptedPayload = await _encryption.encrypt(
      payloadJson,
      password,
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
    final clear = await _encryption.decrypt(payload, password);
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

  /// 启用 U盘钥匙（keyfile 模式）加密并保存：用主密钥加密页面内容，
  /// 生成恢复密钥信封（U 盘丢失时凭 24 位恢复密钥找回主密钥），
  /// 明文不落盘（零知识架构，见 docs/PASSWORD_DISK_DESIGN.md）。
  Future<String> encryptAndSaveWithKey(
    Notebook notebook,
    List<int> masterKey,
    String recoveryKey,
  ) async {
    final payloadJson = jsonEncode({
      'pages': notebook.pages.map((p) => p.toJson()).toList(),
    });
    notebook.encrypted = true;
    notebook.encryptionMode = EncryptionMode.keyfile;
    notebook.encryptedPayload = await _encryption.encryptWithKey(
      payloadJson,
      masterKey,
    );
    notebook.recoveryEnvelope = await _encryption.wrapMasterKey(
      masterKey,
      recoveryKey,
    );
    // 直接原子写入（toJson 中 encrypted 时 pages 序列化为空，仅存密文载荷）。
    return _writeNotebook(notebook);
  }

  /// 用 U盘主密钥解锁 keyfile 模式加密笔记本（密钥错误抛 [FormatException]）。
  /// 成功后将页面填充回 [notebook.pages] 并返回 true。
  Future<bool> decryptNotebookWithKey(
    Notebook notebook,
    List<int> masterKey,
  ) async {
    final payload = notebook.encryptedPayload;
    if (payload == null) return false;
    final clear = await _encryption.decryptWithKey(payload, masterKey);
    final map = jsonDecode(clear) as Map<String, dynamic>;
    final pages = (map['pages'] as List? ?? const [])
        .map((e) => NotebookPage.fromJson(e as Map<String, dynamic>))
        .toList();
    notebook.pages
      ..clear()
      ..addAll(pages);
    return true;
  }

  /// 用 U盘主密钥 + 恢复密钥重加密保存（keyfile 编辑会话保存用）。
  ///
  /// 编辑会话中内存有明文页面；保存时用主密钥重加密最新内容，
  /// 并重新生成恢复信封（若提供了新的恢复密钥）。
  Future<String> saveWithKey(
    Notebook notebook,
    List<int> masterKey, {
    String? newRecoveryKey,
  }) async {
    final payloadJson = jsonEncode({
      'pages': notebook.pages.map((p) => p.toJson()).toList(),
    });
    notebook.encrypted = true;
    notebook.encryptionMode = EncryptionMode.keyfile;
    notebook.encryptedPayload = await _encryption.encryptWithKey(
      payloadJson,
      masterKey,
    );
    if (newRecoveryKey != null) {
      notebook.recoveryEnvelope = await _encryption.wrapMasterKey(
        masterKey,
        newRecoveryKey,
      );
    }
    return _writeNotebook(notebook);
  }

  /// 保存笔记本：加密笔记本不落盘明文 pages（评审发现 P1 修复）。
  ///
  /// - 非加密：直接原子写入；
  /// - 加密且未修改（pages 为空、密文仍在）：保留原密文写入，避免覆盖为空；
  /// - 加密且内存有明文页面：需要密钥才能重加密——若无密钥则拒绝保存
  ///   （防止静默清空磁盘内容），由调用方走 [encryptAndSave] /
  ///   [encryptAndSaveWithKey] / [saveWithKey]。
  @override
  Future<String> save(Notebook notebook) async {
    if (notebook.encrypted) {
      final payload = notebook.encryptedPayload;
      if (payload != null && notebook.pages.isEmpty) {
        // 解密后未修改：保留原密文，避免覆盖为空。
        return _writeNotebook(notebook);
      }
      throw StateError(
        '加密笔记本需要密钥才能保存，请使用 encryptAndSave / encryptAndSaveWithKey / saveWithKey',
      );
    }
    return _writeNotebook(notebook);
  }

  /// 生成唯一 ID。
  static String newId(String prefix) => LocalIdGenerator.next(prefix);
}
