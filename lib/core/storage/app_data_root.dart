// app_data_root.dart —— 统一数据根目录（存储收口 2026-09-02 + S-02 方案 B）
//
// S-02 方案 B（2026-09-29）：数据根默认落在系统 **ApplicationSupport**
// （Windows: %APPDATA%\<app>\，通常不受 OneDrive Known Folder Move 管理），
// 而非 Documents/绘图笔记数据/。迁移为启动期一次性目录搬迁，保守不覆盖。
//
// 旧位置：
//   A) 收口前分散：Documents/{documents,notebooks,...} + 散 JSON
//   B) 收口后（v1.10.x~v1.17.45）：Documents/绘图笔记数据/
// 新位置（唯一现网根）：
//   <ApplicationSupport>/绘图笔记数据/
//   ├─ documents/ documents_trash/ thumbnails/ document_images/
//   ├─ notebooks/ notebook_images/ blockdocs/ blockdocs_trash/
//   ├─ security/   保险库密钥 + 锁屏守卫密钥
//   └─ all_docs_favorites.json / all_docs_tags.json / schedule_events.json
//
// 各存储层仍保留子目录命名与 directoryProvider 注入点——装配层统一
// 注入 [root]，存储层内部追加子目录名。
import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode, visibleForTesting;
import 'package:path_provider/path_provider.dart';

/// 统一数据根目录。
class AppDataRoot {
  AppDataRoot({
    this.documentsDirProvider,
    this.supportDirProvider,
    this.rootName = defaultRootName,
  });

  /// 构建期**数据根隔离口**（真机集成测试用，2026-10-08）。
  ///
  /// 用法（把 `--dart-define` 指向一个临时目录）：
  /// `flutter test integration_test/cuj_01_test.dart -d windows`
  /// `--dart-define=DRAWING_NOTES_DATA_ROOT=/tmp/adr_iso`
  ///
  /// 三条不可妥协的语义：
  /// ① **仅 debug 构建生效**——release/profile 即使误带 define 也走真实根，
  ///    生产行为与既往逐字节一致（`--dart-define` 是编译期常量，构建产物里
  ///    根本不该出现本机路径，这条是兜底）；
  /// ② 生效时**跳过旧位置一次性迁移**——`_migrateLegacy()` 见目标根不存在就会
  ///    把 `Documents/绘图笔记数据/` 里的**用户真数据搬进临时目录**，
  ///    那是灾难级副作用，隔离口绝不能顺手打开这条腿；
  /// ③ define 的值就是**根本身**（不再追加 [rootName] 子目录），测试可以直接
  ///    断言落点，不必猜拼接规则。
  ///
  /// 缘起：`integration_test` 跑的是真实 profile——2026-10-08 一次真机验证
  /// 在用户真实画布库里留下了 3 幅测试画作，并把 debug 窗口弹到了使用者屏幕上。
  static const String testDataRootOverride = String.fromEnvironment(
    'DRAWING_NOTES_DATA_ROOT',
  );

  /// 纯函数版判定（可单测：`String.fromEnvironment` 编译期固定，
  /// 单测里没法改它，只能把「取值 + 是否 debug」这两件事抽出来验）。
  @visibleForTesting
  static String? effectiveTestDataRoot(String override, {required bool debug}) {
    if (!debug) return null;
    final trimmed = override.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// 当前是否处于隔离根模式（生产恒 false）。
  static bool get usesTestDataRoot =>
      effectiveTestDataRoot(testDataRootOverride, debug: kDebugMode) != null;

  /// 文档目录提供者（测试注入；默认系统文档目录）。
  /// 仅用于定位旧位置 / 检测 Known Folder，不再作为新根基底。
  final Future<Directory> Function()? documentsDirProvider;

  /// 文档目录（备份恢复的暂存定位用；公开只读出口，批次 M）。
  Future<Directory> documentsDirectory() => _documentsDir();

  /// 支持目录提供者（测试注入；默认系统应用支持目录）。
  final Future<Directory> Function()? supportDirProvider;

  /// 根目录名（默认 [defaultRootName]）。
  final String rootName;

  /// S-02（审计 2026-09-27）：文档 Known Folder 被云客户端接管
  /// （OneDrive KFM 等）的路径特征——任一路径段含 OneDrive（大小写
  /// 不敏感）。方案 B 后数据根默认不在 Documents；仍保留检测能力
  /// （自定义根/极端配置下路径仍可能落进云同步盘）。
  static bool isCloudSyncedKnownFolderPath(String documentsPath) =>
      documentsPath
          .toLowerCase()
          .split(Platform.pathSeparator)
          .any((segment) => segment.contains('onedrive'));

  /// 默认根目录名（ApplicationSupport 下的可见数据根）。
  static const String defaultRootName = '绘图笔记数据';

  /// 待恢复标记文件名（与数据根同级，位于根目录父路径直下；批次 M + S-02 B）。
  static const String pendingRestoreMarkerName =
      '$defaultRootName.restore_pending';

  /// 写入待恢复标记（恢复流第三步：暂存解压完成后、退出应用前调用）。
  static Future<void> writePendingRestoreMarker({
    required Directory parentDir,
    required String stagingPath,
  }) async {
    final marker = File(
      '${parentDir.path}${Platform.pathSeparator}$pendingRestoreMarkerName',
    );
    await marker.writeAsString(stagingPath, flush: true);
  }

  /// 应用待恢复标记（批次 M + S-02 B）：main() 早期调用——此刻无任何
  /// 存储打开，目录交换原子且无文件锁。返回是否执行了恢复。
  ///
  /// 兼容：标记可能在 ApplicationSupport（新）或 Documents（方案 B 升级
  /// 前写入的在途恢复）。交换目标恒为 **ApplicationSupport/根目录名**。
  ///
  /// fail-safe：标记存在但暂存目录/清单缺失（上次恢复中断）时，仅清除
  /// 标记并放弃恢复——绝不用残缺暂存覆盖现网数据。
  static Future<bool> applyPendingRestore({
    String? Function()? documentsPathProvider,
    String? Function()? supportPathProvider,
  }) async {
    final String docsPath;
    try {
      docsPath =
          documentsPathProvider?.call() ??
          (await getApplicationDocumentsDirectory()).path;
    } catch (_) {
      return false; // 文档目录不可得，跳过恢复检查
    }
    String supportPath;
    try {
      supportPath =
          supportPathProvider?.call() ??
          (await getApplicationSupportDirectory()).path;
    } catch (_) {
      supportPath = docsPath; // 支持目录不可得时仍检查 Documents 标记
    }

    // 1) 优先新位置（ApplicationSupport）；2) 回退 Documents（升级在途）。
    final markerCandidates = [
      File('$supportPath${Platform.pathSeparator}$pendingRestoreMarkerName'),
      File('$docsPath${Platform.pathSeparator}$pendingRestoreMarkerName'),
    ];
    File? marker;
    for (final m in markerCandidates) {
      if (m.existsSync()) {
        marker = m;
        break;
      }
    }
    if (marker == null) return false;
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
      // 现网根恒在 ApplicationSupport（S-02 B）。
      final root = Directory(
        '$supportPath${Platform.pathSeparator}$defaultRootName',
      );
      Directory? oldRoot;
      if (root.existsSync()) {
        oldRoot = Directory(
          '$supportPath${Platform.pathSeparator}'
          '$defaultRootName.old_${DateTime.now().millisecondsSinceEpoch}',
        );
        await root.rename(oldRoot.path);
      }
      await staging.rename(root.path);
      try {
        await marker.delete();
      } catch (_) {}
      // 清理另一位置的同名残留标记（避免下次启动误触发）。
      for (final m in markerCandidates) {
        if (m.path != marker.path && m.existsSync()) {
          try {
            await m.delete();
          } catch (_) {}
        }
      }
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

  Future<Directory> _supportDir() async {
    final provider = supportDirProvider;
    if (provider != null) return provider();
    return getApplicationSupportDirectory();
  }

  /// 统一数据根目录（首次调用时执行旧位置一次性迁移）。
  /// S-02 方案 B：根目录位于 ApplicationSupport。
  Future<Directory> root() async {
    await _ensureMigrated();
    final cached = _rootCache;
    if (cached != null) return cached;
    final dir = await resolveRootWithoutMigrate();
    if (!dir.existsSync()) await dir.create(recursive: true);
    _rootCache = dir;
    return dir;
  }

  /// 不触发迁移的根路径解析（云同步特征检测 / 启动早期只读探测）。
  Future<Directory> resolveRootWithoutMigrate() async {
    // 隔离根模式下 define 值就是根本身（语义 ③），且不追加 rootName。
    final isolated = effectiveTestDataRoot(
      testDataRootOverride,
      debug: kDebugMode,
    );
    if (isolated != null) return Directory(isolated);
    final support = await _supportDir();
    return Directory('${support.path}${Platform.pathSeparator}$rootName');
  }

  /// 数据根的父目录（备份暂存/待恢复标记定位；S-02 B 后通常为 ApplicationSupport）。
  Future<Directory> dataParentDirectory() async {
    final r = await root();
    return r.parent;
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

  /// 隔离根模式下**不迁移**（语义 ②）：迁移会把用户真实旧数据搬进临时目录。
  /// ⚠️ 这里是**条件分支**——写成 `??= Future<void>.value()` 会把生产迁移整体关掉，
  /// 老用户数据就再也搬不进新根（2026-10-08 自查时差点这么写）。
  Future<void> _ensureMigrated() => _migrateFuture ??= (usesTestDataRoot
      ? Future<void>.value()
      : _migrateLegacy());

  /// 旧位置一次性迁移（幂等；目标已存在不覆盖）。
  Future<void> _migrateLegacy() async {
    if (usesTestDataRoot) return;
    final docs = await _documentsDir();
    final support = await _supportDir();
    final newRoot = Directory(
      '${support.path}${Platform.pathSeparator}$rootName',
    );

    // S-02 方案 B：Documents/绘图笔记数据/ → ApplicationSupport/绘图笔记数据/
    // 注意：不可在搬迁前 create newRoot——_moveDir 见 dst.existsSync 即跳过。
    final oldDocsRoot = Directory(
      '${docs.path}${Platform.pathSeparator}$rootName',
    );
    if (oldDocsRoot.existsSync()) {
      if (!newRoot.existsSync()) {
        try {
          await oldDocsRoot.rename(newRoot.path);
        } on FileSystemException {
          await _moveDir(oldDocsRoot, newRoot);
        }
      } else if (!_dirHasEntries(newRoot)) {
        // 新根已存在但为空：搬入子项后删除空壳旧根。
        await _moveDirContents(oldDocsRoot, newRoot);
        try {
          await oldDocsRoot.delete(recursive: true);
        } catch (_) {}
      }
      // 新根非空：保守不覆盖旧 Documents 根。
    }
    if (!newRoot.existsSync()) await newRoot.create(recursive: true);
    _rootCache = newRoot;

    // 收口前分散子目录 → 新根。
    for (final name in legacyDirNames) {
      await _moveDir(
        Directory('${docs.path}${Platform.pathSeparator}$name'),
        Directory('${newRoot.path}${Platform.pathSeparator}$name'),
      );
    }

    // 收口前散文件 → 新根。
    for (final name in legacyFileNames) {
      await _moveFile(
        File('${docs.path}${Platform.pathSeparator}$name'),
        File('${newRoot.path}${Platform.pathSeparator}$name'),
      );
    }

    // 旧密钥文件（支持目录直下）→ 新根 security/。
    for (final name in legacySecurityFileNames) {
      await _moveFile(
        File('${support.path}${Platform.pathSeparator}$name'),
        File(
          '${newRoot.path}${Platform.pathSeparator}security'
          '${Platform.pathSeparator}$name',
        ),
      );
    }
    final secDir = Directory(
      '${newRoot.path}${Platform.pathSeparator}security',
    );
    if (!secDir.existsSync()) await secDir.create(recursive: true);
  }

  bool _dirHasEntries(Directory dir) {
    if (!dir.existsSync()) return false;
    try {
      return dir.listSync(followLinks: false).isNotEmpty;
    } catch (_) {
      return true; // 不可列时保守视为有数据
    }
  }

  Future<void> _moveDir(Directory src, Directory dst) async {
    if (!src.existsSync() || dst.existsSync()) return;
    try {
      await src.rename(dst.path);
    } on FileSystemException {
      // 跨盘 rename 失败：复制 + 删除兜底（绝不丢数据）。
      await _moveDirContents(src, dst);
    }
  }

  Future<void> _moveDirContents(Directory src, Directory dst) async {
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
  /// 与实例 [securityDir] 解析同一物理路径（S-02 B：ApplicationSupport）。
  static Future<Directory> defaultSecurityDir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(
      '${support.path}'
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
