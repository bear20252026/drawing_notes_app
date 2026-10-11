// BackupService —— 全量数据备份与恢复（2026-09-27 增量新增，批次 M）。
//
// 设计（用户可感知语义）：
// - 备份 = 整个数据根打包为单个 zip（含 manifest），由用户选位置保存。
//   数据根内已是「按用户加密设置落盘」的状态：保险库/文件密码开启时
//   密文 + security/ 密钥文件；未设 PIN 时为明文（与运行时落盘一致，
//   导出提示明确告知「含密钥文件，请妥善保管」）。
// - 恢复 = 校验 manifest → 解压到数据根旁的暂存目录（绝不动现网数据）
//   → 写待恢复标记 → 用户确认后退出应用；下次启动 main() 早期由
//   [AppDataRoot.applyPendingRestore] 原子交换目录——此刻无任何存储
//   打开，规避运行中覆盖的文件锁与内存缓存脏数据。
//
// 排除项：*.tmp / *.tmp.* / *.bak（崩溃保护的临时/备份文件不属于有效
// 数据面；口径见 [AppDataRoot.restoreExcludedPattern]）；恢复后现网即与
// 备份时点完全一致。
//
// ============ DN-004 / DN-006（P0 数据安全，2026-10-12）============
//
// DN-004 起因：恢复侧的准入判定只有「manifest 文件存在 + formatVersion
// ≤ 当前」两条，一个**只有一个清单文件的 zip**（或任何恰好带同名条目的
// 无关压缩包）就能被接受 → 写标记 → 危险操作二次确认 → exit(0) → 下次
// 启动真的换根并把旧根递归删除 ⇒ 整库丢失。原生选包框只按扩展名过滤
// `.zip`，接受任意本地文件，所以「用户挑错文件 + 确认覆盖」两步即可触发
// （不是远程可利用，但一旦发生是数据面灾难）。
// 修法：[stageRestore] 在**写暂存/落 marker 之前**用 [AppDataRoot] 的同一
// 组判定函数确认「这确实是一个可用的数据根」——必需子目录、笔记文件计数
// 下限、体积/条目预算、以及 v2 清单的自述与包内实际逐项一致；任一不满足
// 抛 [BackupIntegrityException]（类型化、携带缺失项统计），由调用方映射为
// 用户可见拒绝。换根侧 [AppDataRoot.applyPendingRestore] 复用同一口径复核
// 暂存目录（两道闸，防上次解压中断留下的半成品顶掉现网）。
//
// DN-006 起因：旧实现整包 `readAsBytes()` + `decodeBytes()`，还把**所有条
// 目的 content 一次性物化成 List** 跨 isolate 传递（峰值 ≈ 压缩字节 +
// 全量解压字节，isolate 侧再复制一份），无 stat、无条目数/总字节/压缩比
// 上限——一个大 zip 就能把进程顶爆。
// 修法：archive 4.0.9 的**头部先行 + 逐条流式**路径：`InputFileStream` 只
// 让 `ZipDirectory` 读中央目录（条目名/大小，不读内容）→ 预算与结构校验
// 全部基于头部 → 逐条 `ArchiveFile.writeContent(OutputFileStream)`，该调用
// 走 `ZipFile.decompress(output)` 的 inflate→文件流管道（内存峰值 ≈ inflate
// 窗口 + 一个写缓冲，与包大小无关）。跨 isolate 只回传「拒绝码 + 计数」这
// 类原始值，不再传条目内容。zip-slip 防护语义保留（[_safeRelPath]）。
//
// manifest 版本兼容性（重要，别踩）：`kBackupFormatVersion` 是**备份包自
// 描述版本**，与画布文档的 DNV 信封/迁移框架（core/documents/migration/）
// 不同域。本批 bump 到 2 加自述字段，判定口径是「> 当前即拒 / 落在
// [kBackupFormatVersionMin] 之上即收」，所以 **v1 旧包天然继续可恢复**；
// v1 无自述字段 → 跳过声明核对，但仍受结构与预算下限约束（v1 包必须自证
// 「有笔记内容」）。这条兼容性由 test/core/storage/backup_service_test.dart
// 的「v1 旧包仍可完整恢复」用例反向钉住，不许随版本演进漂走。
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';

import 'package:drawing_notes_app/core/storage/app_data_root.dart';

/// 备份包内清单文件名（zip 根部）。
const String kBackupManifestName = AppDataRoot.backupManifestName;

/// 备份包格式版本（结构变化时递增，恢复端拒绝更高版本）。
///
/// v2（DN-004）新增自述字段：`dataFileCount` / `dataBytes` / `dirFileCounts`。
/// **v1 包继续可恢复**——见 [kBackupFormatVersionMin] 与本文件头部说明。
const int kBackupFormatVersion = 2;

/// 恢复端接受的最旧格式版本（v1 是历史存量，必须继续能恢复）。
const int kBackupFormatVersionMin = 1;

// ==== DN-006 有界解压预算 ===================================================
//
// 这些数值是**上限**，不是调优参数；依据逐条给出（引仓内既有预算），不许
// 为了「让某个包过」而调大。为什么不 import `document_budgets.dart`：
// core/storage 全域受 architecture_test 规则 3b 的 Martin instability ≤ 0.4
// 约束，backup_service 再加一条出向依赖会当场撞红；改由
// test/core/storage/backup_service_test.dart 的「阈值与画布文档预算同源」
// 用例钉住等值关系，漂移即测试红。

/// 单个条目解压后字节上限：`DocumentBudgets.maxFileBytes`（100MiB）× 2。
///
/// 依据：画布编解码器对**单个文件**的既有硬上限就是 100MiB
/// （document_budgets.dart `maxFileBytes`，与 `StorageService._maxListMetaBytes`
/// 同源）；×2 给非画布产物（整幅图片/PDF 预览缓存）留一倍余量。流式落盘
/// 后该项不再是内存上限，只作「挑错文件」的结构哨兵。
const int kBackupMaxEntryBytes = 2 * 100 * 1024 * 1024; // 200MiB

/// 解压后总字节上限：2GiB。
///
/// 依据：本仓最重的**单次导入产物**总输出上限为 500MiB
/// （pdf_import_service.dart `_maxTotalOutputBytes`），×4 给多年积累的整库
/// 留余量；再大说明选中的不是本应用备份（如整盘归档），而恢复需要一份同
/// 尺寸的暂存拷贝，超限继续写盘只会把磁盘顶满。
const int kBackupMaxTotalBytes = 2 * 1024 * 1024 * 1024;

/// 备份包（压缩后）自身字节上限：与 [kBackupMaxTotalBytes] 同档。
const int kBackupMaxArchiveBytes = 2 * 1024 * 1024 * 1024;

/// 条目数上限：2 万。
///
/// 依据：本仓对「大库」的既有量级口径——PROPFIND 响应预算 4MiB
/// 「≈ 1.5 万个远端对象」（webdav_sync_client.dart `propfindBytes` 注释），
/// 取其 1.33 倍余量。单库笔记数远及不上这个量级。
const int kBackupMaxEntries = 20000;

/// 解压膨胀比上限（百分数）：10000 = 100:1。
///
/// 依据：真实数据（画布 JSON、图片、已加密的密文）deflate 实用膨胀比
/// ≤ ~10:1；仓内已把「小输入 → 巨大膨胀」列为威胁模型
/// （svg_preflight.dart 注释记录 811 字节 SVG 实体膨胀可崩掉解析器），
/// 留 10 倍余量拒纯膨胀包（zip bomb）。
const int kBackupMaxRatioPercent = 10000;

/// 清单文件自身字节上限：1MiB。
///
/// 依据：对齐 `AuditLogger._maxFileBytes`（audit_logger.dart:64，1MiB）。
/// v2 清单只含三个计数项，正常 <4KB；1MiB 是数百倍余量，超限即异常包。
const int kBackupMaxManifestBytes = 1024 * 1024;

/// 读侧流缓冲（archive 的 `FileBuffer` 默认 1KiB，逐条大文件会抖动）。
const int kBackupReadBufferSize = 256 * 1024;

/// 写侧流缓冲（archive `OutputFileStream.kDefaultBufferSize` 即 1MiB）。
const int kBackupWriteBufferSize = 1024 * 1024;

/// DN-006 预算的可注入包装（生产恒用 [kBackupRestoreLimitsDefault]）。
///
/// 注入口的存在是为了**可测**：超限路径不能用 2GiB 真文件去触发。
/// 先例见 `AuditLogger.maxFileBytesOverrideForTest`（audit_logger.dart:66）。
/// 注入只允许调小阈值做测试，不构成生产可调项。
final class BackupRestoreLimits {
  const BackupRestoreLimits({
    this.maxEntries = kBackupMaxEntries,
    this.maxEntryBytes = kBackupMaxEntryBytes,
    this.maxTotalBytes = kBackupMaxTotalBytes,
    this.maxArchiveBytes = kBackupMaxArchiveBytes,
    this.maxRatioPercent = kBackupMaxRatioPercent,
    this.maxManifestBytes = kBackupMaxManifestBytes,
  });

  final int maxEntries;
  final int maxEntryBytes;
  final int maxTotalBytes;
  final int maxArchiveBytes;
  final int maxRatioPercent;
  final int maxManifestBytes;
}

const BackupRestoreLimits kBackupRestoreLimitsDefault = BackupRestoreLimits();

/// DN-004：备份包「结构不完整 / 不可信」的类型化拒绝。
///
/// 继承 [FormatException] 是为了**不新增 UI 面也不漏网**：settings_page 的
/// 恢复动作既有 `on FormatException` 分支已经把它映射成用户可见的
/// 「无效的备份文件」；同时 [code] 与 [stats] 让调用方能审计到具体缺哪一项。
class BackupIntegrityException extends FormatException {
  const BackupIntegrityException({
    required this.code,
    required String message,
    this.stats = const <String, Object?>{},
  }) : super(message);

  /// 机器可读拒绝码（`notZip` / `noManifest` / `badManifest` /
  /// `versionTooNew` / `versionTooOld` / `archiveSizeOutlier` /
  /// `tooManyEntries` / `entryTooLarge` / `totalBytesExceeded` /
  /// `compressionRatioExceeded` / `manifestTooLarge` / `incompleteRoot` /
  /// `manifestMismatch` / `truncated` / `ioError` / `unreadable` /
  /// `unexpected`）。
  final String code;

  /// 缺失项/计数统计（条目数、字节数、缺哪些子目录……），供审计与诊断。
  final Map<String, Object?> stats;

  @override
  String toString() =>
      'BackupIntegrityException($code): $message'
      '${stats.isEmpty ? '' : ' stats=$stats'}';
}

/// 全量备份与恢复（纯 Dart，Isolate 化，可测）。
abstract final class BackupService {
  /// 打包 [dataRoot] 为 zip 写入 [destinationPath]。
  ///
  /// 遍历与压缩全部在后台 isolate 执行（大目录不卡 UI）。失败时删除
  /// 半成品目标文件后 rethrow。
  static Future<void> createBackup({
    required Directory dataRoot,
    required String destinationPath,
  }) async {
    if (!dataRoot.existsSync()) {
      throw FileSystemException('数据根不存在', dataRoot.path);
    }
    final rootPath = dataRoot.path;
    final dest = destinationPath;
    try {
      await Isolate.run(() => _packSync(rootPath, dest));
    } catch (_) {
      try {
        final f = File(dest);
        if (f.existsSync()) await f.delete();
      } catch (_) {
        // 清理失败不覆盖原始异常。
      }
      rethrow;
    }
  }

  /// 校验 [backupPath] 并解压到数据根父目录下的暂存目录，写入待恢复标记。
  ///
  /// S-02 方案 B 后 [dataParentDir] 通常为 ApplicationSupport（与现网数据根
  /// 同级）。本方法不触碰现网数据根；实际交换在下次启动时进行。
  ///
  /// 备份不可信时抛 [BackupIntegrityException]（是 [FormatException] 的子类，
  /// 故既有 `on FormatException` 调用方无需改动即可正确拒绝），且**保证**：
  /// 不写待恢复标记、不留半截暂存目录、现网数据根一字未动。
  ///
  /// [limits] 仅供测试注入更小的预算以覆盖超限分支（生产不传）。
  static Future<void> stageRestore({
    required String backupPath,
    required Directory dataParentDir,
    BackupRestoreLimits limits = kBackupRestoreLimitsDefault,
  }) async {
    final parentPath = dataParentDir.path;
    // 预算校验 + 逐条流式落盘都在后台 isolate；跨 isolate 边界只回传
    // 「拒绝码 + 计数」这类原始值（DN-006：不再把整包字节与全部条目内容
    // 同时物化成 List 过界）。
    final outcome = await Isolate.run(
      () => _stageSync(
        backupPath: backupPath,
        parentDirPath: parentPath,
        maxEntries: limits.maxEntries,
        maxEntryBytes: limits.maxEntryBytes,
        maxTotalBytes: limits.maxTotalBytes,
        maxArchiveBytes: limits.maxArchiveBytes,
        maxRatioPercent: limits.maxRatioPercent,
        maxManifestBytes: limits.maxManifestBytes,
      ),
    );
    if (outcome['ok'] != true) {
      throw BackupIntegrityException(
        code: outcome['code'] as String? ?? 'unexpected',
        message: outcome['message'] as String? ?? '备份包校验未通过',
        stats: outcome['stats'] is Map
            ? (outcome['stats'] as Map).cast<String, Object?>()
            : const <String, Object?>{},
      );
    }
    // 只有全部校验通过才落 marker —— 反序（先 marker 后校验）会让一次
    // 失败的恢复在下启动时把残缺暂存顶掉现网。
    await AppDataRoot.writePendingRestoreMarker(
      parentDir: dataParentDir,
      stagingPath: outcome['stagingPath'] as String,
    );
  }

  /// zip 条目名 → 根内相对路径（本机分隔符）；非法返回 null。
  static String? _safeRelPath(String name) =>
      _safeRelSlash(name)?.replaceAll('/', Platform.pathSeparator);

  /// [_safeRelPath] 的「/」分隔版（与打包侧的条目名口径一致）。
  ///
  /// zip slip 防护：拒绝绝对路径/盘符/「..」上跳——这些条目被**跳过**，
  /// 既不落在暂存之外，也不落在暂存之内（跳过计数进 stats，不静默放行
  /// 到正式根）。自产包条目名由 [_packSync] 规范化，永不含上跳，故这条
  /// 防护不会误伤合法备份。
  static String? _safeRelSlash(String name) {
    var n = name.replaceAll('\\', '/');
    if (n.startsWith('/') || RegExp(r'^[A-Za-z]:').hasMatch(n)) return null;
    final parts = <String>[];
    for (final seg in n.split('/')) {
      if (seg.isEmpty || seg == '.') continue;
      if (seg == '..') return null;
      parts.add(seg);
    }
    if (parts.isEmpty) return null;
    return parts.join('/');
  }

  /// 校验 + 解压主体（后台 isolate 同步执行）。
  ///
  /// 返回值只含原始值（`bool`/`String`/`int`/`List<String>`/`Map`），便于
  /// isolate 消息传递；失败不抛异常而是回传拒绝码——自定义异常对象跨
  /// isolate 传递会被序列化成无信息的错误，类型化判定只能在主 isolate 造。
  static Map<String, Object?> _stageSync({
    required String backupPath,
    required String parentDirPath,
    required int maxEntries,
    required int maxEntryBytes,
    required int maxTotalBytes,
    required int maxArchiveBytes,
    required int maxRatioPercent,
    required int maxManifestBytes,
  }) {
    InputFileStream? input;
    try {
      final int archiveBytes;
      try {
        archiveBytes = File(backupPath).lengthSync();
      } catch (e) {
        return _reject('unreadable', '无法读取备份文件：$e', const {});
      }
      if (archiveBytes <= 0 || archiveBytes > maxArchiveBytes) {
        return _reject(
          'archiveSizeOutlier',
          '备份文件体积异常（$archiveBytes 字节，上限 $maxArchiveBytes），'
          '不像是本应用的备份包',
          {'archiveBytes': archiveBytes, 'limit': maxArchiveBytes},
        );
      }

      // ① 只读中央目录（条目名/大小），不物化任何条目内容。
      input = InputFileStream(backupPath, bufferSize: kBackupReadBufferSize);
      final decoder = ZipDecoder();
      final Archive archive;
      try {
        archive = decoder.decodeStream(input);
      } catch (e) {
        return _reject(
          'notZip',
          '备份包不是可解析的 zip（文件损坏或根本不是备份包）：$e',
          {'archiveBytes': archiveBytes},
        );
      }

      final dataFiles = <ArchiveFile>[];
      ArchiveFile? manifestFile;
      var unsafeEntries = 0;
      var symlinkEntries = 0;
      var headerCount = 0;
      var headerBytes = 0;
      var headerMaxEntry = 0;
      for (final f in archive.files) {
        if (!f.isFile) continue;
        headerCount++;
        headerBytes += f.size;
        if (f.size > headerMaxEntry) headerMaxEntry = f.size;
        if (f.isSymbolicLink) {
          // 自产包只含普通文件；符号链接一律不落盘（防指到暂存之外）。
          symlinkEntries++;
          continue;
        }
        final slash = _safeRelSlash(f.name);
        if (slash == null) {
          unsafeEntries++;
          continue;
        }
        if (slash == kBackupManifestName) {
          manifestFile = f;
          continue;
        }
        dataFiles.add(f);
      }

      // ② 预算闸门（全部取自身声明的头部数值，超限即终止，一个字节都不写）。
      if (headerCount > maxEntries) {
        return _reject(
          'tooManyEntries',
          '备份包条目数超限（$headerCount > $maxEntries）',
          {'entries': headerCount, 'limit': maxEntries},
        );
      }
      if (headerMaxEntry > maxEntryBytes) {
        return _reject(
          'entryTooLarge',
          '备份包内单文件解压后超限（$headerMaxEntry > $maxEntryBytes 字节）',
          {'maxEntryBytes': headerMaxEntry, 'limit': maxEntryBytes},
        );
      }
      if (headerBytes > maxTotalBytes) {
        return _reject(
          'totalBytesExceeded',
          '备份包解压后总字节超限（$headerBytes > $maxTotalBytes）',
          {'totalBytes': headerBytes, 'limit': maxTotalBytes},
        );
      }
      final ratioPercent = headerBytes * 100 ~/ archiveBytes;
      if (ratioPercent > maxRatioPercent) {
        return _reject(
          'compressionRatioExceeded',
          '备份包膨胀比异常（$ratioPercent% > $maxRatioPercent%，'
          '疑似压缩炸弹或非备份文件）',
          {'totalBytes': headerBytes, 'archiveBytes': archiveBytes, 'ratioPercent': ratioPercent},
        );
      }

      // ③ 清单：必须存在、可解析、版本兼容。
      if (manifestFile == null) {
        return _reject(
          'noManifest',
          '备份缺少清单文件（$kBackupManifestName），无法确认为本应用备份',
          {'entries': headerCount, 'archiveBytes': archiveBytes},
        );
      }
      if (manifestFile.size > maxManifestBytes) {
        return _reject(
          'manifestTooLarge',
          '备份清单体积异常（${manifestFile.size} > $maxManifestBytes 字节）',
          {'manifestBytes': manifestFile.size},
        );
      }
      final Map<String, dynamic> manifest;
      try {
        manifest =
            jsonDecode(utf8.decode(manifestFile.content)) as Map<String, dynamic>;
      } catch (e) {
        return _reject(
          'badManifest',
          '备份清单无法解析（$kBackupManifestName 不是合法 JSON 对象）：$e',
          {'manifestBytes': manifestFile.size},
        );
      }
      final version = manifest['formatVersion'];
      if (version is! int) {
        return _reject(
          'badManifest',
          '备份清单缺少 formatVersion 版本号，无法确认包格式',
          const {},
        );
      }
      if (version > kBackupFormatVersion) {
        return _reject(
          'versionTooNew',
          '备份格式版本过新（v$version > 本应用支持的最高 v$kBackupFormatVersion），'
          '请升级应用后再恢复',
          {'formatVersion': version, 'supported': kBackupFormatVersion},
        );
      }
      if (version < kBackupFormatVersionMin) {
        return _reject(
          'versionTooOld',
          '备份格式版本过旧（v$version < v$kBackupFormatVersionMin），'
          '本应用不再支持该格式',
          {'formatVersion': version},
        );
      }

      // ④ 结构完整性 +（v2）清单自述与实际内容逐项一致。
      final actualDirCounts = <String, int>{};
      var actualBytes = 0;
      for (final f in dataFiles) {
        actualBytes += f.size;
        final sub = AppDataRoot.knownSubdirOf(_safeRelSlash(f.name)!);
        if (sub != null) actualDirCounts[sub] = (actualDirCounts[sub] ?? 0) + 1;
      }
      final gaps = AppDataRoot.restoreStructureGaps(
        dataFileCount: dataFiles.length,
        dirFileCounts: actualDirCounts,
        // v1 包不自述内容 → 必须靠结构证明它是「有笔记的库」（见文件头）。
        requireNoteBearing: version < kBackupFormatVersion,
      );
      if (gaps.isNotEmpty) {
        return _reject(
          'incompleteRoot',
          gaps.join('；'),
          {
            'dataFiles': dataFiles.length,
            'totalBytes': actualBytes,
            'gaps': gaps,
            'unsafeEntries': unsafeEntries,
            'symlinkEntries': symlinkEntries,
          },
        );
      }
      if (version >= kBackupFormatVersion) {
        final mismatches = AppDataRoot.manifestDeclarationGaps(
          manifest,
          dataFileCount: dataFiles.length,
          totalBytes: actualBytes,
          dirFileCounts: actualDirCounts,
        );
        if (mismatches.isNotEmpty) {
          return _reject(
            'manifestMismatch',
            '备份清单与包内内容不一致：${mismatches.join('；')}',
            {
              'dataFiles': dataFiles.length,
              'totalBytes': actualBytes,
              'mismatches': mismatches,
            },
          );
        }
      }

      // ⑤ 逐条流式落盘到暂存目录（现网根此时仍未被触碰）。
      final staging = Directory(
        '$parentDirPath${Platform.pathSeparator}'
        '${AppDataRoot.defaultRootName}.restore_'
        '${DateTime.now().millisecondsSinceEpoch}',
      );
      if (staging.existsSync()) {
        try {
          staging.deleteSync(recursive: true);
        } catch (_) {}
      }
      staging.createSync(recursive: true);
      try {
        for (final f in [manifestFile, ...dataFiles]) {
          final rel = _safeRelPath(f.name)!;
          final target = File('${staging.path}${Platform.pathSeparator}$rel');
          target.parent.createSync(recursive: true);
          final out = OutputFileStream(target.path, bufferSize: kBackupWriteBufferSize);
          try {
            // inflate → 文件流的管道；不是 f.content（那会整条物化进内存）。
            f.writeContent(out);
          } finally {
            out.closeSync();
          }
          final landed = target.lengthSync();
          if (landed != f.size) {
            // 静默截断是数据丢失的头号形态：宁可拒恢复也不留半截文件。
            return _purgeAndReject(
              staging,
              'truncated',
              '条目 ${f.name} 解压后字节数不符（声明 ${f.size}，实落 $landed）',
              {'entry': f.name, 'declared': f.size, 'landed': landed},
            );
          }
        }
      } catch (e) {
        return _purgeAndReject(
          staging,
          'ioError',
          '解压落盘失败（磁盘/权限）：$e',
          const {},
        );
      }

      // ⑥ 落盘后用**磁盘侧**再判一次同一口径（头部合规但内容落不全、
      // 或包内条目名规范化后与声明对不上时，这里兜住）。
      final postGaps = AppDataRoot.directoryRestoreGaps(staging);
      if (postGaps.isNotEmpty) {
        return _purgeAndReject(
          staging,
          'incompleteRoot',
          '解压后暂存结构不完整：${postGaps.join('；')}',
          {'gaps': postGaps, 'unsafeEntries': unsafeEntries},
        );
      }

      return <String, Object?>{
        'ok': true,
        'stagingPath': staging.path,
        'dataFiles': dataFiles.length,
        'totalBytes': actualBytes,
        'unsafeEntries': unsafeEntries,
        'symlinkEntries': symlinkEntries,
      };
    } catch (e) {
      return _reject('unexpected', '备份包校验异常：$e', const {});
    } finally {
      // 条目子流共享同一个 FileBuffer，只在最后关顶层流（提前关会让后续
      // 条目读不到内容）。
      try {
        input?.closeSync();
      } catch (_) {}
    }
  }

  static Map<String, Object?> _reject(
    String code,
    String message,
    Map<String, Object?> stats,
  ) =>
      <String, Object?>{
        'ok': false,
        'code': code,
        'message': message,
        'stats': stats,
      };

  /// 失败清理：删掉本次刚建的暂存目录再拒绝（不留半截暂存、不写标记）。
  static Map<String, Object?> _purgeAndReject(
    Directory staging,
    String code,
    String message,
    Map<String, Object?> stats,
  ) {
    try {
      if (staging.existsSync()) staging.deleteSync(recursive: true);
    } catch (_) {
      // 清理尽力而为：无标记的残留暂存不会被 applyPendingRestore 消费。
    }
    return _reject(code, message, stats);
  }

  /// 打包主体（在 isolate 内执行）：遍历数据根 → 过滤临时文件 → zip 落盘。
  static void _packSync(String rootPath, String destinationPath) {
    final root = Directory(rootPath);

    // 先读内容、后算声明：清单里的 dataBytes/dataFileCount/dirFileCounts 一律
    // 按**实际入档的字节**统计。若改用遍历时的 lengthSync 记账，备份期间一次
    // 自动保存改了文件大小，清单就会与包内内容对不上，于是自产合法包被恢复侧
    // 自己判成 manifestMismatch —— 那是守卫最不能接受的误伤形态。
    final members = <ArchiveFile>[];
    final dirCounts = <String, int>{};
    var dataBytes = 0;
    for (final entity in root.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final norm = AppDataRoot.relativePathOf(rootPath, entity.path);
      if (norm == null ||
          norm == kBackupManifestName ||
          AppDataRoot.restoreExcludedPattern.hasMatch(norm)) {
        continue;
      }
      final bytes = entity.readAsBytesSync();
      members.add(ArchiveFile(norm, bytes.length, bytes));
      dataBytes += bytes.length;
      final sub = AppDataRoot.knownSubdirOf(norm);
      if (sub != null) dirCounts[sub] = (dirCounts[sub] ?? 0) + 1;
    }

    final archive = Archive();
    // 清单先行（恢复端第一道校验）。v2 的三项自述字段是 DN-004 的结构闸门
    // 依据：恢复侧据此核对「包里到底是不是我打的那些文件」。
    final manifest = utf8.encode(
      jsonEncode(<String, dynamic>{
        'formatVersion': kBackupFormatVersion,
        'createdAt': DateTime.now().toIso8601String(),
        'dataFileCount': members.length,
        'dataBytes': dataBytes,
        'dirFileCounts': dirCounts,
      }),
    );
    archive.addFile(
      ArchiveFile(kBackupManifestName, manifest.length, manifest),
    );
    for (final m in members) {
      archive.addFile(m);
    }

    final encoded = ZipEncoder().encode(archive);
    if (encoded.isEmpty) {
      throw StateError('备份打包结果为空');
    }
    File(destinationPath)
      ..createSync(recursive: true)
      ..writeAsBytesSync(encoded, flush: true);
  }
}
