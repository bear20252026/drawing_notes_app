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
import 'dart:convert';
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
  ///
  /// **DN-203（第三轮专家审计 2026-10-13）**：这个标记现在**只有用户明确确认
  /// 之后**才会被写出（见 [confirmRestoreStage]），内容也从「裸暂存路径」升级为
  /// 带确认字段的 JSON。此前它是 `stageRestore` 在校验完备份包、**还没弹确认框
  /// 之前**就写下的——于是「暂存完成后崩溃 / 用户直接杀进程 / 页面已卸载
  /// (`if (!context.mounted) return;`) / 取消时清标记失败」这四条路径都会留下一
  /// 个下次启动即换根并删旧根的标记，把「用户确认后才能覆盖现网」这条约束变成
  /// 一句愿望。暂存事实改由 [restoreStageMarkerName] 承载，启动侧绝不消费它。
  static const String pendingRestoreMarkerName =
      '$defaultRootName.restore_pending';

  /// 「已暂存、未确认」标记（DN-203）。内容 = 暂存目录绝对路径。
  ///
  /// 刻意是 **inert** 的：[applyPendingRestore] 不看它，只有设置页读到它并让用户
  /// 点下「确认恢复」（→ [confirmRestoreStage]）才会转成可触发换根的
  /// [pendingRestoreMarkerName]。所以任何崩溃/重启都不可能让一次未确认的暂存生效。
  static const String restoreStageMarkerName =
      '$defaultRootName.restore_staged';

  /// 备份包清单文件名（zip 根部；[BackupService] 与本类的恢复校验共用这一
  /// 唯一口径，避免两处字符串各写一份而漂移）。
  static const String backupManifestName = 'backup_manifest.json';

  /// 恢复失败留痕文件名（与数据根同级）。DN-103。
  static const String restoreFailureLogName =
      '$defaultRootName.restore_failure.log';

  /// 记录一次恢复失败（DN-103）。
  ///
  /// 刻意**不用 `AuditLogger`**，两个原因：
  /// 1. `core/security/audit_logger.dart` 本身就 import 本文件，反向依赖会形成
  ///    import 环——架构门禁「零循环依赖」会红。
  /// 2. `AuditLogger` 是**进程内内存链、重启即失**；而「恢复失败」恰恰是跨重启
  ///    才需要看的事件。落在数据根父目录的日志文件才真正可诊断。
  ///
  /// 尽力而为：日志写不进去绝不影响恢复主流程。
  static Future<void> _recordRestoreFailure(
    String parentPath,
    String detail,
  ) async {
    try {
      final log = File(
        '$parentPath${Platform.pathSeparator}$restoreFailureLogName',
      );
      await log.writeAsString(
        '${DateTime.now().toIso8601String()}  $detail\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      // 留痕失败可忽略：本次恢复已按失败返回，标记仍保留供下次重试
    }
  }

  /// 写「已暂存」标记（[BackupService.stageRestore] 用）。
  ///
  /// 这一步**不产生任何破坏性后果**：暂存解压完成后只留下这条 inert 记录，
  /// 换根必须等 [confirmRestoreStage]（DN-203）。
  static Future<void> writeRestoreStageMarker({
    required Directory parentDir,
    required String stagingPath,
  }) => _writeMarker(
    parentDir: parentDir,
    name: restoreStageMarkerName,
    content: stagingPath,
  );

  /// 读「已暂存、未确认」的恢复（设置页横幅用）。
  ///
  /// 暂存目录已经不在了（被手工清理 / 磁盘回收）就连 inert 标记一起清掉，
  /// 免得 UI 一直提示一件无法确认的事。
  static Future<String?> readRestoreStagePath({
    required Directory parentDir,
  }) async {
    final marker = _markerFile(parentDir, restoreStageMarkerName);
    if (!marker.existsSync()) return null;
    final String stagingPath;
    try {
      stagingPath = (await marker.readAsString()).trim();
    } catch (_) {
      return null;
    }
    if (!_stagingAlive(stagingPath)) {
      try {
        await marker.delete();
      } catch (_) {}
      return null;
    }
    return stagingPath;
  }

  /// 用户点下「确认恢复」之后才产生可触发换根的标记（DN-203 的 CONFIRMED 态）。
  ///
  /// 确认时就复核一次暂存结构（[directoryRestoreGaps] 与换根侧同一口径）：
  /// 暂存在「弹出确认框」这段时间里被外部破坏掉的话，宁可拒绝确认，
  /// 也不能让一个坏暂存拿到可触发标记。
  static Future<RestoreStageDecision> confirmRestoreStage({
    required Directory parentDir,
  }) async {
    final stagingPath = await readRestoreStagePath(parentDir: parentDir);
    if (stagingPath == null) return RestoreStageDecision.noStagedRestore;
    final gaps = directoryRestoreGaps(Directory(stagingPath));
    if (gaps.isNotEmpty) {
      try {
        await _markerFile(parentDir, restoreStageMarkerName).delete();
      } catch (_) {}
      await _recordRestoreFailure(
        parentDir.path,
        'confirm_rejected  暂存结构不合格：${gaps.join('；')}',
      );
      return RestoreStageDecision.stagingInvalid;
    }
    await writePendingRestoreMarker(
      parentDir: parentDir,
      stagingPath: stagingPath,
    );
    try {
      await _markerFile(parentDir, restoreStageMarkerName).delete();
    } catch (_) {}
    return RestoreStageDecision.confirmed;
  }

  /// 放弃一次未确认的暂存恢复：清 inert 标记 + 尽力清暂存目录。
  static Future<void> discardRestoreStage({
    required Directory parentDir,
  }) async {
    final stagingPath = await readRestoreStagePath(parentDir: parentDir);
    try {
      await _markerFile(parentDir, restoreStageMarkerName).delete();
    } catch (_) {}
    if (stagingPath == null || stagingPath.isEmpty) return;
    try {
      final staging = Directory(stagingPath);
      if (staging.existsSync()) await staging.delete(recursive: true);
    } catch (_) {
      // 残留暂存不影响数据安全（没有标记就没有换根），下次暂存会覆盖同名目录。
    }
  }

  static File _markerFile(Directory parentDir, String name) =>
      File('${parentDir.path}${Platform.pathSeparator}$name');

  static Future<void> _writeMarker({
    required Directory parentDir,
    required String name,
    required String content,
  }) => _markerFile(parentDir, name).writeAsString(content, flush: true);

  /// 写入**已确认**的待恢复标记（只由 [confirmRestoreStage] 调用）。
  ///
  /// 载荷从裸路径升级为带确认字段的 JSON——换根侧据此区分「用户确认过的恢复」
  /// 与「上一次暂存到一半」（后者绝不能自动换根）。签名保持不变，避免旧调用点
  /// 各写一份载荷格式。
  static Future<void> writePendingRestoreMarker({
    required Directory parentDir,
    required String stagingPath,
  }) => _writeMarker(
    parentDir: parentDir,
    name: pendingRestoreMarkerName,
    content: jsonEncode({
      'markerVersion': 2,
      'stagingPath': stagingPath,
      // 没有这个字段就视为未确认（旧格式或不完整写入都落在这里）。
      'confirmedAtMs': DateTime.now().millisecondsSinceEpoch,
    }),
  );

  /// 解析待恢复标记，返回暂存目录路径；**未确认的一律返回 null**。
  ///
  /// 旧版本（≤1.17.65）写的是裸路径文本，且它可能压根没被用户确认过
  /// ——那种标记在本版启动时会被降级成 inert 暂存（见
  /// [applyPendingRestore]），由设置页请用户重新确认，绝不自动换根。
  static String? _confirmedStagingPathOf(String raw) {
    if (!raw.startsWith('{')) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final staging = decoded['stagingPath'];
      final confirmedAt = decoded['confirmedAtMs'];
      if (staging is! String || staging.trim().isEmpty) return null;
      if (confirmedAt is! int) return null;
      return staging.trim();
    } catch (_) {
      return null;
    }
  }

  /// 暂存目录是否还在。路径内容不可信（旧标记可能被截断成半截 JSON），
  /// Windows 上对非法路径直接 `existsSync()` 会抛 errno 123 ——一律按「不在」处理。
  static bool _stagingAlive(String path) {
    try {
      return path.isNotEmpty && Directory(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  /// 把「未确认格式」的旧待恢复标记降级成 inert 暂存（DN-203 的升级路径）。
  ///
  /// 只动标记，不动暂存内容：暂存目录留着，用户还能在设置页点「确认恢复」
  /// 继续这次恢复；点「放弃」或下次暂存会覆盖它。全过程失败也不影响现网。
  static Future<void> _demoteUnconfirmedRestoreMarker(
    File marker,
    String rawMarker,
  ) async {
    final stagingPath = rawMarker.trim();
    final stagingAlive = _stagingAlive(stagingPath);
    if (stagingAlive) {
      try {
        // 挪到同级的暂存标记文件，pending 标记随之消失。
        final staged = File(
          '${marker.parent.path}${Platform.pathSeparator}$restoreStageMarkerName',
        );
        await staged.writeAsString(stagingPath, flush: true);
        await marker.delete();
      } catch (_) {
        // 降级失败：宁可这次不恢复，也不带着不可信标记换根（下次启动再试一次）。
      }
    } else {
      try {
        await marker.delete();
      } catch (_) {}
    }
    await _recordRestoreFailure(
      marker.parent.path,
      stagingAlive
          ? 'unconfirmed_marker  旧格式待恢复标记已降级为待确认暂存（需在设置页重新确认）'
          : 'unconfirmed_marker_missing_staging  旧格式标记指向的暂存已不存在，已清除标记',
    );
  }

  /// 应用待恢复标记（批次 M + S-02 B）：main() 早期调用——此刻无任何
  /// 存储打开，目录交换原子且无文件锁。返回是否执行了恢复。
  ///
  /// 兼容：标记可能在 ApplicationSupport（新）或 Documents（方案 B 升级
  /// 前写入的在途恢复）。交换目标恒为 **ApplicationSupport/根目录名**。
  ///
  /// fail-safe：标记存在但暂存目录/清单缺失（上次恢复中断）时，仅清除
  /// 标记并放弃恢复——绝不用残缺暂存覆盖现网数据。
  ///
  /// DN-203：标记还必须是**用户确认过**的载荷；旧格式（裸路径，可能在确认
  /// 之前写好）降级成 inert 暂存，交设置页重新确认。
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
    final rawMarker = (await marker.readAsString()).trim();
    final stagingPath = _confirmedStagingPathOf(rawMarker);
    if (stagingPath == null) {
      // DN-203：拿到的是旧格式（裸路径）或不带确认字段的标记——它在旧版本里
      // 可能是**用户还没确认就写好**的，而换根的净效果是删掉现网根。
      // 这里不猜意图：降级成 inert 暂存 + 落一条留痕，由设置页请用户重新确认。
      await _demoteUnconfirmedRestoreMarker(marker, rawMarker);
      return false;
    }
    try {
      final staging = Directory(stagingPath);
      final manifest = File(
        '${staging.path}${Platform.pathSeparator}$backupManifestName',
      );
      if (stagingPath.isEmpty ||
          !staging.existsSync() ||
          !manifest.existsSync()) {
        try {
          await marker.delete();
        } catch (_) {}
        return false;
      }
      // DN-004（P0 数据安全）：换根前的第二道闸——暂存目录必须是「一个
      // 可用的数据根」。此前只看清单文件是否存在，一旦上次解压被中断/
      // 暂存被外部破坏（防软、磁盘满、人工删档），残缺暂存会直接顶掉
      // 现网根，而现网根随后被递归删除 ⇒ 整库丢失。
      // 判定与 BackupService.stageRestore 走同一组函数（单一事实来源）。
      final gaps = directoryRestoreGaps(staging);
      if (gaps.isNotEmpty) {
        // 只清标记、不动暂存内容（保留取证余地）。是否顺手清理残留暂存
        // 与下面的 .old_ 保留策略同属**业主未裁决项**，本批不开这个口子。
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
      try {
        await staging.rename(root.path);
      } catch (e) {
        // DN-103（专家审计 2026-10-12）：换根失败必须**回滚**旧根。
        //
        // 此前这里直接落到外层 `catch (_) { return false; }`——旧数据其实
        // 还在 `.old_<ts>` 下没丢，但应用按默认根名再也找不到它，下一次启动
        // 会新建一个空根，用户看到的是「笔记全部消失」。目录交换不是原子的
        // 两次 rename，中途失败必须自己收拾，不能把状态留给下一次启动猜。
        //
        // 回滚成功则旧根恢复原名，本次恢复作废但现网数据照常可用；外层
        // catch 仍会保留标记，下次启动可重试。
        if (oldRoot != null) {
          try {
            await oldRoot.rename(root.path);
          } catch (_) {
            await _recordRestoreFailure(
              supportPath,
              'rollback_failed  旧根回滚失败，数据完整保留在 ${oldRoot.path}',
            );
          }
        }
        await _recordRestoreFailure(
          supportPath,
          'promote_failed  ${e.runtimeType}'
          '${oldRoot == null ? '' : '（已尝试回滚旧根）'}',
        );
        rethrow; // 外层 catch：保留标记 + 返回 false，下次启动重试
      }
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
        // ⚠️ 已知缺口（DN-004 关联项，**业主尚未裁决，本批不动策略**）：
        // 换根成功后旧根**立即**递归删除，且全仓没有 `.old_` 巡检/找回代码。
        // 改成像模像样的「保留 N 份 / 保留 T 天 / 显式清理入口」会长期占用
        // 一整份数据根的磁盘，还要决定何时清理与如何提示用户，属产品裁决——
        // 本批只在代码注释与本批报告里登记，不改删除时机，也不加启动巡检。
        // 本批做的是：把破坏性一步往前挪一道闸——上面的 directoryRestoreGaps
        // 保证只有结构完整的暂存才会顶掉现网（残缺暂存不再换根）。
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

  // ==== 恢复侧「这是一个可用的数据根」最小结构口径（DN-004，P0 数据安全）====
  //
  // 缺陷起因：`BackupService.stageRestore` 与 [applyPendingRestore] 此前只判
  // 「manifest 文件存在 + formatVersion ≤ 当前」，一个**只有一个清单文件的
  // zip** 就被当成合法备份：写标记 → 用户确认 → 换根 → 旧根立即递归删除
  // ⇒ 整库丢失。原生选包框只过滤扩展名 `.zip`，接受任意本地文件，所以
  // 「用户挑错文件 + 确认覆盖」两步即可触发。
  //
  // 本段是**单一事实来源**：zip 条目侧（BackupService 读中央目录）与暂存
  // 目录侧（[applyPendingRestore] 换根前）走同一组判定函数，杜绝两处漂移。
  // 只做**读**目录结构的事——删除/保留策略一字未动。

  /// 数据根内的已知顶层子目录（备份包必须能对上这套布局，否则它根本不是
  /// 本应用的备份）。与 [legacyDirNames] 同源 + `security/`。
  static const List<String> knownSubdirNames = [...legacyDirNames, 'security'];

  /// 笔记承载目录——恢复的下限判据（见 [restoreStructureGaps]）。
  static const List<String> noteBearingSubdirNames = ['documents', 'blockdocs'];

  /// 非空根的最小数据文件数。依据：真实数据根哪怕只有一条笔记，也必然
  /// 至少含「1 个文档/块文档 + 1 个 security 密钥」；`< 1` 只可能是空包或
  /// 用户误挑的无关 zip，恢复它的净效果是**清空现网且无任何可恢复内容**。
  static const int minRestoreDataFiles = 1;

  /// 崩溃保护的临时/备份文件（不属于有效数据面；打包与校验同一口径，
  /// 否则 [manifestDeclarationGaps] 会把这些文件算进实际计数而误判）。
  static final RegExp restoreExcludedPattern = RegExp(r'\.(tmp|bak)(\..*)?$');

  /// 根内相对路径（「/」分隔、无首分隔符）；不在该根下 / 为空返回 null。
  static String? relativePathOf(String rootPath, String entityPath) {
    if (!entityPath.startsWith(rootPath)) return null;
    final rel = entityPath
        .substring(rootPath.length)
        .replaceAll('\\', '/')
        .replaceFirst(RegExp(r'^/+'), '');
    return rel.isEmpty ? null : rel;
  }

  /// 相对路径所属的已知顶层子目录名；不属于任何已知子目录返回 null。
  static String? knownSubdirOf(String relPath) {
    final normalized = relPath.replaceAll('\\', '/');
    final slash = normalized.indexOf('/');
    if (slash <= 0) return null; // 根下散文件（无目录段）或非法前缀
    final head = normalized.substring(0, slash);
    return knownSubdirNames.contains(head) ? head : null;
  }

  /// 结构完整性判定（纯计数版，供 zip 头部预检与磁盘扫描共用）。
  ///
  /// 返回人可读的缺失项列表，**空列表 = 可信**；调用方据此拒绝并映射成
  /// 用户可见文案——不静默、不误伤：
  /// - [requireNoteBearing] 为 true 时（v1 包**无自述**，只能靠结构证明它
  ///   确实是「有内容的库」）额外要求 documents/blockdocs 至少有一个文件；
  /// - v2 包自带清单声明并由 [manifestDeclarationGaps] 逐项目核对，故不再
  ///   受笔记下限约束（自产的空库备份是真实存在的状态，拒它就是误伤）。
  static List<String> restoreStructureGaps({
    required int dataFileCount,
    required Map<String, int> dirFileCounts,
    required bool requireNoteBearing,
  }) {
    final gaps = <String>[];
    if (dataFileCount < minRestoreDataFiles) {
      gaps.add('备份包不含任何数据文件（仅 $backupManifestName，疑似选错文件）');
    }
    if (!dirFileCounts.keys.any(knownSubdirNames.contains)) {
      gaps.add(
        '备份包内没有本应用的数据子目录（已知子目录：'
        '${knownSubdirNames.take(4).join('/')}…），它不是本应用的数据根布局',
      );
    }
    if (requireNoteBearing) {
      final noteFiles = noteBearingSubdirNames.fold<int>(
        0,
        (sum, d) => sum + (dirFileCounts[d] ?? 0),
      );
      if (noteFiles < minRestoreDataFiles) {
        gaps.add(
          '笔记目录为空（${noteBearingSubdirNames.join('/')} 合计 '
          '$noteFiles 个文件，至少需 $minRestoreDataFiles 个）——恢复它只会清空现网',
        );
      }
    }
    return gaps;
  }

  /// v2 清单自述 vs 实际内容的一致性判定（空列表 = 一致）。
  ///
  /// 「manifest 声明与实际内容一致」这一条只有在备份包**自报**了计数之后
  /// 才可判；v1 包没有这些字段，调用方不应把缺字段当成缺陷（见
  /// [BackupService] 的版本兼容说明）。
  static List<String> manifestDeclarationGaps(
    Map<String, dynamic> manifest, {
    required int dataFileCount,
    required int totalBytes,
    required Map<String, int> dirFileCounts,
  }) {
    final gaps = <String>[];
    final declaredCount = manifest['dataFileCount'];
    final declaredBytes = manifest['dataBytes'];
    final declaredDirs = manifest['dirFileCounts'];
    if (declaredCount is! int ||
        declaredBytes is! int ||
        declaredDirs is! Map) {
      gaps.add(
        'v2 备份清单自述不完整（需 dataFileCount/dataBytes/dirFileCounts 三项，'
        '实测 ${declaredCount is int ? 'ok' : '缺 dataFileCount'}/'
        '${declaredBytes is int ? 'ok' : '缺 dataBytes'}/'
        '${declaredDirs is Map ? 'ok' : '缺 dirFileCounts'}）',
      );
      return gaps;
    }
    if (declaredCount != dataFileCount) {
      gaps.add('清单声明 $declaredCount 个数据文件，包内实际 $dataFileCount 个');
    }
    if (declaredBytes != totalBytes) {
      gaps.add('清单声明 $declaredBytes 字节，实际 $totalBytes 字节');
    }
    final declared = <String, int>{};
    for (final e in declaredDirs.entries) {
      final k = e.key;
      final v = e.value;
      if (k is! String || v is! int) {
        gaps.add('清单目录计数格式非法（${e.key}=${e.value}）');
        continue;
      }
      declared[k] = v;
    }
    for (final name in {
      ...declared.keys,
      ...dirFileCounts.keys.where(knownSubdirNames.contains),
    }) {
      final want = declared[name] ?? 0;
      final got = dirFileCounts[name] ?? 0;
      if (want != got) {
        gaps.add('子目录 $name 声明 $want 个文件，实际 $got 个');
      }
    }
    return gaps;
  }

  /// 读取一个目录里的备份清单（不存在/不可解析返回 null——调用方据此判缺）。
  static Map<String, dynamic>? readManifestOf(Directory dir) {
    try {
      final f = File('${dir.path}${Platform.pathSeparator}$backupManifestName');
      if (!f.existsSync()) return null;
      final decoded = jsonDecode(f.readAsStringSync());
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  /// 磁盘版恢复校验（暂存目录/现网根）。与 zip 侧同口径：
  /// 结构下限 + （v2）清单声明一致性。
  static List<String> directoryRestoreGaps(Directory dir) {
    var dataFiles = 0;
    var dataBytes = 0;
    final dirCounts = <String, int>{};
    try {
      for (final entity in dir.listSync(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final norm = relativePathOf(dir.path, entity.path);
        if (norm == null || norm == backupManifestName) continue;
        if (restoreExcludedPattern.hasMatch(norm)) continue;
        dataFiles++;
        dataBytes += entity.lengthSync();
        final sub = knownSubdirOf(norm);
        if (sub != null) dirCounts[sub] = (dirCounts[sub] ?? 0) + 1;
      }
    } catch (_) {
      return const ['暂存目录无法列出（磁盘或权限异常）'];
    }
    final manifest = readManifestOf(dir);
    if (manifest == null) {
      return const ['暂存目录缺少可解析的备份清单']; // 兜底：外层已判存在，这里覆盖「内容坏了」
    }
    final version = manifest['formatVersion'];
    final gaps = restoreStructureGaps(
      dataFileCount: dataFiles,
      dirFileCounts: dirCounts,
      // v1 暂存（升级前写入的在途恢复）无自述 → 沿用笔记下限。
      requireNoteBearing: version is! int || version < 2,
    );
    if (version is int && version >= 2) {
      gaps.addAll(
        manifestDeclarationGaps(
          manifest,
          dataFileCount: dataFiles,
          totalBytes: dataBytes,
          dirFileCounts: dirCounts,
        ),
      );
    }
    return gaps;
  }

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

/// [AppDataRoot.confirmRestoreStage] 的结果（DN-203 三态里的确认一步）。
enum RestoreStageDecision {
  /// 已写出可触发换根的确认标记——调用方可以退出应用，下次启动生效。
  confirmed,

  /// 没有（或已失效的）暂存记录：无操作。
  noStagedRestore,

  /// 暂存目录结构不合格：已清掉暂存标记并留痕，绝不产生可触发标记。
  stagingInvalid,
}
