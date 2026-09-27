// app_data_root.dart —— 统一数据根目录（存储收口改造 2026-09-02）
//
// 背景：历史演进中业务数据分散在 Documents 下 7+ 个位置（documents/
// documents_trash/thumbnails/document_images/notebooks/notebook_images/
// blockdocs/blockdocs_trash + 3 个散 JSON），保险库与锁屏守卫密钥又在
// AppData 支持目录——导致"卸载/重置删不干净、数据看似存在多处"。
//
// 本类提供**单一数据根**：所有业务数据文件统一收进
//   `<系统文档目录>/绘图笔记数据/`
//   ├─ documents/            画布工程
//   ├─ documents_trash/      画布回收站
//   ├─ thumbnails/           画布缩略图
//   ├─ document_images/      画布导入图片副本
//   ├─ notebooks/            笔记本工程
//   ├─ notebook_images/      笔记本图片副本
//   ├─ blockdocs/            打字笔记
//   ├─ blockdocs_trash/      打字笔记回收站
//   ├─ security/             保险库密钥 + 锁屏守卫密钥
//   ├─ all_docs_favorites.json
//   ├─ all_docs_tags.json
//   └─ schedule_events.json
//
// 各存储层仍保留各自的子目录命名与 directoryProvider 注入点——装配层
// 统一注入 [root]，存储层内部追加子目录名，行为不变、落点收拢。
//
// 旧位置一次性迁移：首次访问根目录时把上述旧位置整体搬入新根
// （目标已存在则不覆盖——保守策略，绝不丢数据）。搬移完成后旧位置
// 不再有任何读写。
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 统一数据根目录。
class AppDataRoot {
  AppDataRoot({
    this.documentsDirProvider,
    this.supportDirProvider,
    this.rootName = defaultRootName,
  });

  /// 文档目录提供者（测试注入；默认系统文档目录）。
  final Future<Directory> Function()? documentsDirProvider;

  /// 文档目录（备份恢复的暂存定位用；公开只读出口，批次 M）。
  Future<Directory> documentsDirectory() => _documentsDir();

  /// 支持目录提供者（测试注入；默认系统应用支持目录）。
  final Future<Directory> Function()? supportDirProvider;

  /// 根目录名（默认 [defaultRootName]）。
  final String rootName;

  /// 默认根目录名（系统文档目录下的可见文件夹）。
  static const String defaultRootName = '绘图笔记数据';

  /// 待恢复标记文件名（与数据根同级，位于文档目录直下；批次 M 2026-09-27）。
  /// 内容为暂存目录绝对路径，由 [writePendingRestoreMarker] 写入、
  /// [applyPendingRestore] 在下次启动早期消费。
  static const String pendingRestoreMarkerName =
      '$defaultRootName.restore_pending';

  /// 写入待恢复标记（恢复流第三步：暂存解压完成后、退出应用前调用）。
  static Future<void> writePendingRestoreMarker({
    required Directory documentsDir,
    required String stagingPath,
  }) async {
    final marker = File(
      '${documentsDir.path}${Platform.pathSeparator}$pendingRestoreMarkerName',
    );
    await marker.writeAsString(stagingPath, flush: true);
  }

  /// 应用待恢复标记（批次 M）：main() 早期调用——此刻无任何存储打开，
  /// 目录交换原子且无文件锁。返回是否执行了恢复。
  ///
  /// fail-safe：标记存在但暂存目录/清单缺失（上次恢复中断）时，仅清除
  /// 标记并放弃恢复——绝不用残缺暂存覆盖现网数据。
  static Future<bool> applyPendingRestore({
    String? Function()? documentsPathProvider,
  }) async {
    final String docsPath;
    try {
      docsPath =
          documentsPathProvider?.call() ??
          (await getApplicationDocumentsDirectory()).path;
    } catch (_) {
      return false; // 文档目录不可得，跳过恢复检查
    }
    final marker = File('$docsPath${Platform.pathSeparator}$pendingRestoreMarkerName');
    if (!marker.existsSync()) return false;
    final stagingPath = (await marker.readAsString()).trim();
    try {
      final staging = Directory(stagingPath);
      final manifest = File(
        '${staging.path}${Platform.pathSeparator}backup_manifest.json',
      );
      if (stagingPath.isEmpty ||
          !staging.existsSync() ||
          !manifest.existsSync()) {
        try {
          await marker.delete();
        } catch (_) {}
        return false;
      }
      final root = Directory('$docsPath${Platform.pathSeparator}$defaultRootName');
      Directory? oldRoot;
      if (root.existsSync()) {
        oldRoot = Directory(
          '$docsPath${Platform.pathSeparator}'
          '$defaultRootName.old_${DateTime.now().millisecondsSinceEpoch}',
        );
        await root.rename(oldRoot.path);
      }
      await staging.rename(root.path);
      try {
        await marker.delete();
      } catch (_) {}
      if (oldRoot != null) {
        try {
          await oldRoot.delete(recursive: true);
        } catch (_) {
          // 旧数据删除尽力而为：失败仅留下 .old_<ts> 目录，不阻塞启动。
        }
      }
      return true;
    } catch (_) {
      // 交换失败（磁盘/权限）：放弃本次恢复，保留标记供下次再试。
      return false;
    }
  }


  /// 旧版分散的子目录名（迁移源，位于系统文档目录直下）。
  static const List<String> legacyDirNames = [
    'documents',
    'documents_trash',
    'thumbnails',
    'document_images',
    'notebooks',
    'notebook_images',
    'blockdocs',
    'blockdocs_trash',
  ];

  /// 旧版分散的散文件名（迁移源）。
  static const List<String> legacyFileNames = [
    'all_docs_favorites.json',
    'all_docs_tags.json',
    'schedule_events.json',
  ];

  /// 旧版保险库/锁屏守卫密钥文件名（迁移源：系统支持目录）。
  static const List<String> legacySecurityFileNames = [
    'vault.key.json',
    'app_lock_guard.key',
  ];

  Directory? _rootCache;
  Future<void>? _migrateFuture;

  Future<Directory> _documentsDir() async {
    final provider = documentsDirProvider;
    if (provider != null) return provider();
    return getApplicationDocumentsDirectory();
  }

  /// 统一数据根目录（首次调用时执行旧位置一次性迁移）。
  Future<Directory> root() async {
    await _ensureMigrated();
    final cached = _rootCache;
    if (cached != null) return cached;
    final docs = await _documentsDir();
    final dir = Directory('${docs.path}${Platform.pathSeparator}$rootName');
    if (!dir.existsSync()) await dir.create(recursive: true);
    _rootCache = dir;
    return dir;
  }

  /// 安全目录（保险库密钥 / 锁屏守卫密钥），位于数据根下 `security/`。
  Future<Directory> securityDir() async {
    final rootDir = await root();
    final dir = Directory('${rootDir.path}${Platform.pathSeparator}security');
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  /// 安全目录下的密钥文件（保险库/锁屏守卫统一入口）。
  Future<File> securityFile(String name) async {
    final dir = await securityDir();
    return File('${dir.path}${Platform.pathSeparator}$name');
  }

  Future<void> _ensureMigrated() => _migrateFuture ??= _migrateLegacy();

  /// 旧位置一次性迁移（幂等：源不存在即跳过；目标已存在不覆盖）。
  Future<void> _migrateLegacy() async {
    final docs = await _documentsDir();
    final rootDir = Directory('${docs.path}${Platform.pathSeparator}$rootName');
    if (!rootDir.existsSync()) await rootDir.create(recursive: true);
    _rootCache = rootDir;

    // 1) 旧业务子目录整体搬入根目录。
    for (final name in legacyDirNames) {
      await _moveDir(
        Directory('${docs.path}${Platform.pathSeparator}$name'),
        Directory('${rootDir.path}${Platform.pathSeparator}$name'),
      );
    }

    // 2) 旧散文件搬入根目录。
    for (final name in legacyFileNames) {
      await _moveFile(
        File('${docs.path}${Platform.pathSeparator}$name'),
        File('${rootDir.path}${Platform.pathSeparator}$name'),
      );
    }

    // 3) 旧密钥文件搬入根目录 security/。
    final support = await (supportDirProvider != null
        ? supportDirProvider!()
        : getApplicationSupportDirectory());
    for (final name in legacySecurityFileNames) {
      await _moveFile(
        File('${support.path}${Platform.pathSeparator}$name'),
        File(
          '${rootDir.path}${Platform.pathSeparator}security'
          '${Platform.pathSeparator}$name',
        ),
      );
    }
    final secDir = Directory(
      '${rootDir.path}${Platform.pathSeparator}security',
    );
    if (!secDir.existsSync()) await secDir.create(recursive: true);
  }

  Future<void> _moveDir(Directory src, Directory dst) async {
    if (!src.existsSync() || dst.existsSync()) return;
    try {
      await src.rename(dst.path);
    } on FileSystemException {
      // 跨盘 rename 失败：复制 + 删除兜底（绝不丢数据）。
      await dst.create(recursive: true);
      await for (final entity in src.list(recursive: true)) {
        final rel = entity.path.substring(src.path.length);
        final target = '${dst.path}$rel';
        if (entity is Directory) {
          await Directory(target).create(recursive: true);
        } else if (entity is File) {
          await Directory(target).parent.create(recursive: true);
          await entity.copy(target);
        }
      }
      await src.delete(recursive: true);
    }
  }

  Future<void> _moveFile(File src, File dst) async {
    if (!src.existsSync() || dst.existsSync()) return;
    await dst.parent.create(recursive: true);
    try {
      await src.rename(dst.path);
    } on FileSystemException {
      await src.copy(dst.path);
      await src.delete();
    }
  }

  /// 静态安全目录解析（无实例场景：AppLockGuard.defaultSecretLoader 等）。
  ///
  /// 与实例 [securityDir] 解析同一物理路径；不触发迁移（迁移由组合根
  /// 持有的实例在启动早期完成，静态读取只做目录确保存在）。
  static Future<Directory> defaultSecurityDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(
      '${docs.path}'
      '${Platform.pathSeparator}$defaultRootName'
      '${Platform.pathSeparator}security',
    );
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  /// 默认共享实例（存储层未注入 provider 时的兜底——保证任何构造路径
  /// 都落进统一根，收口不依赖装配层逐点接线）。
  static final AppDataRoot _default = AppDataRoot();

  /// 统一根目录静态解析（存储层默认基目录的单一事实来源）。
  static Future<Directory> defaultRootDir() => _default.root();
}
