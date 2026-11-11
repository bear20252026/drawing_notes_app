// app_data_root_restore.dart —— AppDataRoot 的恢复/暂存职责域（物理拆分）。
//
// 本文件是 app_data_root.dart 的**同库 part**：拆的是物理位置，不是逻辑——
// 所有方法仍是 AppDataRoot 的静态 API（主文件保留同名转发），lib/ 与 test/
// 的调用点零改动。
//
// 为什么是 part 而不是「独立库 + export」：
//   ① Dart 不支持把一个 class 的成员拆到两个 library。若把恢复方法改成独立类并
//      独立成库，`AppDataRoot.writeRestoreStageMarker(...)` 这类既有调用点会全部
//      编译失败——除非主文件再写一批转发；而转发要引用 `defaultRootName` /
//      `legacyDirNames` / `backupManifestName` 等常量，两个库之间就会形成 import 环，
//      撞 architecture_test「规则2：零循环依赖」。
//   ② part 同库：常量、私有 helper、结构校验工具（`directoryRestoreGaps` 等）都
//      原地可见，拆分前后行为逐字节一致。
part of 'app_data_root.dart';

/// 恢复暂存工具域（物理拆分自 app_data_root.dart，2026-11）。
///
/// 承载 DN-203（确认后才可换根）、DN-204（换根时间戳隔离判据）、DN-208（恢复前
/// 快照保留一份）的暂存标记、确认、放弃、换根与快照保留策略。全部为静态方法；
/// 主库 [AppDataRoot] 保留同名转发以维持既有调用点。
class AppDataRootRestore {
  /// 保留最近一份恢复前快照，清掉更老的 `.old_<毫秒>` 兄弟目录（DN-208）。
  ///
  /// 判据刻意用**目录名里的时间戳**而不是路径字符串相等：Windows 上
  /// `listSync()` 回来的路径写法可能与拼出来的 `keep` 不完全一致，一旦比较
  /// 失败就会把刚留下的那份快照删掉——正是要避免的事反过来发生。时间戳
  /// 严格小于本次的才清，等值的永远留下。解析不出时间戳的目录一律不动
  /// （宁可多占磁盘，也不猜它是什么）。
  static Future<void> _pruneRestoreSnapshots(
    String supportPath, {
    required String keep,
  }) async {
    final keepStamp = _snapshotStampOf(keep);
    if (keepStamp == null) return;
    try {
      for (final entity in Directory(supportPath).listSync()) {
        if (entity is! Directory) continue;
        // 判据只认目录名尾部的 `.old_<毫秒>`（_snapshotStampOf 解析不出即不动），
        // 不再叠加一次路径前缀比较——URI 路径段的写法差异不该参与删除决策。
        final stamp = _snapshotStampOf(entity.path);
        if (stamp == null || stamp >= keepStamp) continue;
        try {
          await entity.delete(recursive: true);
        } catch (e) {
          // 删不掉只多占一份磁盘，不影响本次恢复结果。
          // L2（2026-11）：删除失败留痕（best-effort 路径，失败不改变控制流）。
          await _recordRestoreFailure(
            supportPath,
            'prune_snapshots  旧快照删除失败：${errorCode(e)}',
          );
        }
      }
    } catch (_) {
      // 列目录失败：一份都不清。
    }
  }

  /// 从 `.old_<毫秒>` 目录名尾部取毫秒时间戳；解析不出返回 null。
  ///
  /// 分隔符走 `Platform.pathSeparator` 而不是字面量反斜杠：源码里写转义反斜杠
  /// 极易被工具链吃掉变成空字符串，那时 `replaceAll('', '/')` 会在每个字符前
  /// 插一个斜杠，本函数就永远解析不出时间戳——保留策略会**静默退化成不清理**
  /// （第一版正是这样，靠 `只清严格更早的快照` 用例才暴露）。
  static int? _snapshotStampOf(String path) {
    final normalized = path.replaceAll(Platform.pathSeparator, '/');
    final tail = normalized.substring(normalized.lastIndexOf('/') + 1);
    final underscore = tail.lastIndexOf('.old_');
    if (underscore < 0) return null;
    return int.tryParse(tail.substring(underscore + 5));
  }

  /// 磁盘上最近一次「恢复换根」的毫秒时间戳（`.old_<毫秒>` 快照目录名里的最大者），
  /// 没有快照或解析不出时间戳时返回 null（DN-204 的隔离判据用）。
  ///
  /// 取最大者而不是「存在任何一个」：快照可能被 [_pruneRestoreSnapshots] 换掉、
  /// 也可能同时留着一次更早的；只有最近那次换根才是「基线是否落后于现网」的
  /// 分界线。列目录失败按「无换根证据」返回 null——与恢复主流程同口径，
  /// 读不出事实时绝不凭空造出一个隔离态。
  static int? latestRestoreSnapshotMs(String supportPath) {
    int? newest;
    try {
      for (final entity in Directory(supportPath).listSync()) {
        if (entity is! Directory) continue;
        final stamp = _snapshotStampOf(entity.path);
        if (stamp == null) continue;
        if (newest == null || stamp > newest) newest = stamp;
      }
    } catch (_) {
      return null;
    }
    return newest;
  }

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
        '$parentPath${Platform.pathSeparator}${AppDataRoot.restoreFailureLogName}',
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

  /// 写「已暂存」标记（`BackupService.stageRestore` 用）。
  ///
  /// 这一步**不产生任何破坏性后果**：暂存解压完成后只留下这条 inert 记录，
  /// 换根必须等 [confirmRestoreStage]（DN-203）。
  static Future<void> writeRestoreStageMarker({
    required Directory parentDir,
    required String stagingPath,
  }) =>
      _writeMarker(
        parentDir: parentDir,
        name: AppDataRoot.restoreStageMarkerName,
        content: stagingPath,
      );

  /// 读「已暂存、未确认」的恢复（设置页横幅用）。
  ///
  /// 暂存目录已经不在了（被手工清理 / 磁盘回收）就连 inert 标记一起清掉，
  /// 免得 UI 一直提示一件无法确认的事。
  static Future<String?> readRestoreStagePath({
    required Directory parentDir,
  }) async {
    final marker = _markerFile(parentDir, AppDataRoot.restoreStageMarkerName);
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
      } catch (e) {
        // L2（2026-11）：删除失败留痕——此前完全无记录，与同文件
        // _recordRestoreFailure 的口径对齐（AuditLogger 会成循环依赖，
        // 故走同一文件日志例接口）。
        await _recordRestoreFailure(
          parentDir.path,
          'read_stage  过期标记删除失败：${errorCode(e)}',
        );
      }
      return null;
    }
    return stagingPath;
  }

  /// 路径版 [readRestoreStagePath]（H1 架构修复 2026-11）：表现层
  /// 不持 `Directory`，只传父路径字符串。语义与 Directory 版逐字一致。
  static Future<String?> readRestoreStagePathFromPath({
    required String parentPath,
  }) =>
      readRestoreStagePath(parentDir: Directory(parentPath));

  /// 用户点下「确认恢复」之后才产生可触发换根的标记（DN-203 的 CONFIRMED 态）。
  ///
  /// 确认时就复核一次暂存结构（[AppDataRoot.directoryRestoreGaps] 与换根侧同一口径）：
  /// 暂存在「弹出确认框」这段时间里被外部破坏掉的话，宁可拒绝确认，
  /// 也不能让一个坏暂存拿到可触发标记。
  static Future<RestoreStageDecision> confirmRestoreStage({
    required Directory parentDir,
  }) async {
    final stagingPath = await readRestoreStagePath(parentDir: parentDir);
    if (stagingPath == null) return RestoreStageDecision.noStagedRestore;
    final gaps = AppDataRoot.directoryRestoreGaps(Directory(stagingPath));
    if (gaps.isNotEmpty) {
      try {
        await _markerFile(parentDir, AppDataRoot.restoreStageMarkerName).delete();
      } catch (e) {
        // L2（2026-11）：删除失败留痕（与本函数既有的 _recordRestoreFailure 同口径）。
        await _recordRestoreFailure(
          parentDir.path,
          'confirm_rejected  标记删除失败：${errorCode(e)}',
        );
      }
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
      await _markerFile(parentDir, AppDataRoot.restoreStageMarkerName).delete();
    } catch (e) {
      // L2（2026-11）：删除失败留痕（确认路径）。
      await _recordRestoreFailure(
        parentDir.path,
        'confirm_confirmed  标记删除失败：${errorCode(e)}',
      );
    }
    return RestoreStageDecision.confirmed;
  }

  /// 路径版 [confirmRestoreStage]（H1 架构修复 2026-11）：表现层不持
  /// `Directory`，只传父路径字符串。语义与 Directory 版逐字一致。
  static Future<RestoreStageDecision> confirmRestoreStageFromPath({
    required String parentPath,
  }) =>
      confirmRestoreStage(parentDir: Directory(parentPath));

  /// 放弃一次未确认的暂存恢复：清 inert 标记 + 尽力清暂存目录。
  static Future<void> discardRestoreStage({
    required Directory parentDir,
  }) async {
    final stagingPath = await readRestoreStagePath(parentDir: parentDir);
    try {
      await _markerFile(parentDir, AppDataRoot.restoreStageMarkerName).delete();
    } catch (e) {
      // L2（2026-11）：删除失败留痕（放弃暂存路径）。
      await _recordRestoreFailure(
        parentDir.path,
        'discard  标记删除失败：${errorCode(e)}',
      );
    }
    if (stagingPath == null || stagingPath.isEmpty) return;
    try {
      final staging = Directory(stagingPath);
      if (staging.existsSync()) await staging.delete(recursive: true);
    } catch (e) {
      // 残留暂存不影响数据安全（没有标记就没有换根），下次暂存会覆盖同名目录。
      // L2（2026-11）：删除失败留痕（尽力清理路径，失败不改变控制流）。
      await _recordRestoreFailure(
        parentDir.path,
        'discard  暂存目录删除失败：${errorCode(e)}',
      );
    }
  }

  /// 路径版 [discardRestoreStage]（H1 架构修复 2026-11）：表现层不持
  /// `Directory`，只传父路径字符串。语义与 Directory 版逐字一致。
  static Future<void> discardRestoreStageFromPath({
    required String parentPath,
  }) =>
      discardRestoreStage(parentDir: Directory(parentPath));

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
    name: AppDataRoot.pendingRestoreMarkerName,
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
          '${marker.parent.path}${Platform.pathSeparator}'
          '${AppDataRoot.restoreStageMarkerName}',
        );
        await staged.writeAsString(stagingPath, flush: true);
        await marker.delete();
      } catch (_) {
        // 降级失败：宁可这次不恢复，也不带着不可信标记换根（下次启动再试一次）。
      }
    } else {
      try {
        await marker.delete();
      } catch (e) {
        // L2（2026-11）：删除失败留痕（降级路径的标记清除）。
        await _recordRestoreFailure(
          marker.parent.path,
          'demote  旧格式标记删除失败：${errorCode(e)}',
        );
      }
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
      File(
        '$supportPath${Platform.pathSeparator}'
        '${AppDataRoot.pendingRestoreMarkerName}',
      ),
      File(
        '$docsPath${Platform.pathSeparator}'
        '${AppDataRoot.pendingRestoreMarkerName}',
      ),
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
        '${staging.path}${Platform.pathSeparator}'
        '${AppDataRoot.backupManifestName}',
      );
      if (stagingPath.isEmpty ||
          !staging.existsSync() ||
          !manifest.existsSync()) {
        try {
          await marker.delete();
        } catch (e) {
          // L2（2026-11）：删除失败留痕。
          await _recordRestoreFailure(
            supportPath,
            'apply  残缺暂存标记删除失败：${errorCode(e)}',
          );
        }
        return false;
      }
      // DN-004（P0 数据安全）：换根前的第二道闸——暂存目录必须是「一个
      // 可用的数据根」。此前只看清单文件是否存在，一旦上次解压被中断/
      // 暂存被外部破坏（防软、磁盘满、人工删档），残缺暂存会直接顶掉
      // 现网根，而现网根随后被递归删除 ⇒ 整库丢失。
      // 判定与 BackupService.stageRestore 走同一组函数（单一事实来源）。
      final gaps = AppDataRoot.directoryRestoreGaps(staging);
      if (gaps.isNotEmpty) {
        // 只清标记、不动暂存内容（保留取证余地）。
        try {
          await marker.delete();
        } catch (e) {
          // L2（2026-11）：删除失败留痕。
          await _recordRestoreFailure(
            supportPath,
            'apply  结构不合格标记删除失败：${errorCode(e)}',
          );
        }
        return false;
      }
      // 现网根恒在 ApplicationSupport（S-02 B）。
      final root = Directory(
        '$supportPath${Platform.pathSeparator}${AppDataRoot.defaultRootName}',
      );
      Directory? oldRoot;
      if (root.existsSync()) {
        oldRoot = Directory(
          '$supportPath${Platform.pathSeparator}'
          '${AppDataRoot.defaultRootName}.old_${DateTime.now().millisecondsSinceEpoch}',
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
          'promote_failed  ${errorCode(e)}'
          '${oldRoot == null ? '' : '（已尝试回滚旧根）'}',
        );
        rethrow; // 外层 catch：保留标记 + 返回 false，下次启动重试
      }
      try {
        await marker.delete();
      } catch (e) {
        // L2（2026-11）：删除失败留痕（换根成功后清标记）。
        await _recordRestoreFailure(
          supportPath,
          'apply  已确认标记删除失败：${errorCode(e)}',
        );
      }
      // 清理另一位置的同名残留标记（避免下次启动误触发）。
      for (final m in markerCandidates) {
        if (m.path != marker.path && m.existsSync()) {
          try {
            await m.delete();
          } catch (e) {
            // L2（2026-11）：删除失败留痕（残留标记清理）。
            await _recordRestoreFailure(
              supportPath,
              'apply  残留标记删除失败：${errorCode(e)}',
            );
          }
        }
      }
      if (oldRoot != null) {
        // DN-208（第三轮专家审计 2026-10-13）：换根成功后**保留最近一份**恢复前快照，
        // 不再当场递归删除。此前旧根在 `staging.rename(root)` 成功后立即被清，
        // 而这条是「成功」路径——DN-103 的回滚根本不会触发，用户选错备份包时
        // 应用内没有任何退回手段。
        //
        // 保留口径（本批裁决为「1 份」，不无限增长）：
        // - 本次换下的 `.old_<ts>` 留下，比它更老的 `.old_*` 兄弟目录此刻清掉；
        // - 于是任何时刻磁盘上最多一份恢复前快照，且它至少经过了一次
        //   「新根正常启动并跑到这里」的验证才可能被替换——符合审计建议的
        //   「验证新根正常后再按保留期限清理」。
        // - 清理尽力而为：删不掉只多占磁盘，绝不影响本次恢复结果。
        await _pruneRestoreSnapshots(supportPath, keep: oldRoot.path);
      }
      return true;
    } catch (_) {
      // 交换失败（磁盘/权限）：放弃本次恢复，保留标记供下次再试。
      return false;
    }
  }
}
