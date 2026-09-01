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

  /// 支持目录提供者（测试注入；默认系统应用支持目录）。
  final Future<Directory> Function()? supportDirProvider;

  /// 根目录名（默认 [defaultRootName]）。
  final String rootName;

  /// 默认根目录名（系统文档目录下的可见文件夹）。
  static const String defaultRootName = '绘图笔记数据';

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
    if (!await dir.exists()) await dir.create(recursive: true);
    _rootCache = dir;
    return dir;
  }

  /// 安全目录（保险库密钥 / 锁屏守卫密钥），位于数据根下 `security/`。
  Future<Directory> securityDir() async {
    final rootDir = await root();
    final dir = Directory('${rootDir.path}${Platform.pathSeparator}security');
    if (!await dir.exists()) await dir.create(recursive: true);
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
    if (!await rootDir.exists()) await rootDir.create(recursive: true);
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
    if (!await secDir.exists()) await secDir.create(recursive: true);
  }

  Future<void> _moveDir(Directory src, Directory dst) async {
    if (!await src.exists() || await dst.exists()) return;
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
    if (!await src.exists() || await dst.exists()) return;
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
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// 默认共享实例（存储层未注入 provider 时的兜底——保证任何构造路径
  /// 都落进统一根，收口不依赖装配层逐点接线）。
  static final AppDataRoot _default = AppDataRoot();

  /// 统一根目录静态解析（存储层默认基目录的单一事实来源）。
  static Future<Directory> defaultRootDir() => _default.root();
}
