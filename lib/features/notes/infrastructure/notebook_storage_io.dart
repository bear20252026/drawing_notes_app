part of 'notebook_storage.dart';

// IO 域（O1 拆分自 notebook_storage.dart）：目录确保、路径、文件 mtime、
// 独占锁、删除与受管图片收集。public API、字段与静态成员留在本体。行为零变化。

/// 目录/路径/独占/删除域私有助手（拆分自 notebook_storage.dart）。
extension _NotebookStorageIo on NotebookStorage {

  Future<Directory> _baseDir() async {
    final provider = directoryProvider;
    if (provider != null) return provider();
    return AppDataRoot.defaultRootDir();
  }


  Future<Directory> _ensureNotebooksDir() async {
    if (_notebooksDir != null) return _notebooksDir!;
    final base = await _baseDir();
    final dir = Directory('${base.path}${Platform.pathSeparator}notebooks');
    if (!dir.existsSync()) await dir.create(recursive: true);
    _notebooksDir = dir;
    return dir;
  }


  Future<Directory> _ensureImagesDir() async {
    if (_imagesDir != null) return _imagesDir!;
    final base = await _baseDir();
    final dir = Directory(
      '${base.path}${Platform.pathSeparator}notebook_images',
    );
    if (!dir.existsSync()) await dir.create(recursive: true);
    _imagesDir = dir;
    return dir;
  }


  Future<String> _pathFor(String id) async {
    // C-02 修复（专家审计 2026-08-15）：assert-only 校验在 release 失效——
    // 运行时强制校验（load/save/delete 均经此统一防护路径遍历）。
    if (!NotebookStorage.isValidId(id)) {
      throw ArgumentError.value(id, 'id', '非法 ID（路径遍历防护）');
    }
    return '${(await _ensureNotebooksDir()).path}${Platform.pathSeparator}$id.json';
  }


  /// 文件修改时间（读取失败回退当前时间——占位排序兜底）。
  Future<DateTime> _fileMtime(File f) async {
    try {
      return f.lastModifiedSync();
    } on FileSystemException {
      return DateTime.now();
    }
  }


  /// E-18 修复（审计 2026-09-07）：把 [op] 挂到 [id] 的写尾队列（与
  /// save/_enqueueRawRewrite 共用 [_writeTails]——StorageService 的
  /// _runDocExclusive 同款）。链上某步失败不影响后续步骤。
  Future<T> _runExclusive<T>(String id, Future<T> Function() op) {
    final previous = _writeTails[id] ?? Future<void>.value();
    final task = previous.catchError((_) {}).then((_) => op());
    late final Future<void> chain;
    chain = task.then(
      (_) {
        if (identical(_writeTails[id], chain)) _writeTails.remove(id);
      },
      onError: (_) {
        if (identical(_writeTails[id], chain)) _writeTails.remove(id);
      },
    );
    _writeTails[id] = chain;
    return task;
  }


  Future<bool> _deleteLocked(String id) async {
    await _ensureNotebooksDir();
    final file = File(await _pathFor(id));
    final backup = File('${file.path}.bak');
    final mainExists = file.existsSync();
    final backupExists = backup.existsSync();
    // 主文件与备份都不存在才算「无此笔记本」。仅剩 .bak（rename 期崩溃等）
    // 时笔记本仍可从备份加载——删除必须连备份一起处理。
    if (!mainExists && !backupExists) return false;
    // 先收集图片路径再删除文件：文件删除后无法再读取其内容。
    // _collectImagePaths 走 load()——主文件缺失时自动读 .bak。
    final imagePaths = await _collectImagePaths(id);
    if (mainExists) await file.delete();
    // 三-5 修复（审计第 4 轮）：.bak 随主文件一并删除——否则删除后旧内容
    // 仍留在磁盘（隐私），且下次 load 会凭备份「复活」已删除的笔记本。
    if (backupExists) {
      try {
        await backup.delete();
      } catch (_) {
        // 主文件已删、加载路径只认主文件优先，旧备份不再参与加载；
        // 残留含旧内容（隐私），落审计日志供排查。
        AuditLogger.log('notebook.delete.bak_left', success: false);
      }
    }
    forgetNotebookPassword(id); // 会话密码随文档删除一并清理
    // 清理该笔记本所有页面引用的图片副本（尽力而为）。
    for (final p in imagePaths) {
      try {
        // C-01 修复（专家审计 2026-08-15）：图片路径来自笔记 JSON（不可信
        // 数据）——删除前验证受管目录 + 非符号链接（CVE-2026-55667 同源：
        // 符号链接跟随可删除越界文件）。仅删除受管目录内的普通文件。
        final managed = await _managedImagePathOrNull(p);
        if (managed == null) continue;
        final type = FileSystemEntity.typeSync(managed, followLinks: false);
        if (type != FileSystemEntityType.file) continue;
        final f = File(managed);
        if (f.existsSync()) await f.delete();
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
}
