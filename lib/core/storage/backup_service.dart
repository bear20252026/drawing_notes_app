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
// 数据面）；恢复后现网即与备份时点完全一致。
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';

import 'package:drawing_notes_app/core/storage/app_data_root.dart';

/// 备份包内清单文件名（zip 根部）。
const String kBackupManifestName = 'backup_manifest.json';

/// 备份包格式版本（结构变化时递增，恢复端拒绝更高版本）。
const int kBackupFormatVersion = 1;

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

  /// 校验 [backupPath] 并解压到文档目录下的暂存目录，写入待恢复标记。
  ///
  /// 本方法不触碰现网数据根；实际交换在下次启动时进行。
  /// 备份无效（缺 manifest / 版本更高 / zip 损坏）抛 [FormatException]。
  static Future<void> stageRestore({
    required String backupPath,
    required Directory documentsDir,
  }) async {
    final bytes = await File(backupPath).readAsBytes();
    final entries = await Isolate.run(() {
      final archive = ZipDecoder().decodeBytes(bytes);
      return <(String, List<int>)>[
        for (final f in archive.files)
          if (f.isFile) (f.name, f.content as List<int>),
      ];
    });

    // manifest 校验：必须存在且 formatVersion 兼容。
    final manifestEntry = entries.where((e) => e.$1 == kBackupManifestName);
    if (manifestEntry.isEmpty) {
      throw const FormatException('备份缺少清单文件，无法确认为本应用备份');
    }
    final manifest =
        jsonDecode(utf8.decode(manifestEntry.first.$2)) as Map<String, dynamic>;
    if (manifest['formatVersion'] is! int ||
        (manifest['formatVersion'] as int) > kBackupFormatVersion) {
      throw const FormatException('备份格式版本过新，请升级应用后再恢复');
    }

    final staging = Directory(
      '${documentsDir.path}${Platform.pathSeparator}'
      '${AppDataRoot.defaultRootName}.restore_${DateTime.now().millisecondsSinceEpoch}',
    );
    if (staging.existsSync()) {
      await staging.delete(recursive: true);
    }
    await staging.create(recursive: true);

    // 逐条解压：zip slip 防护——拒绝绝对路径/盘符/「..」上跳。
    for (final (name, content) in entries) {
      final rel = _safeRelPath(name);
      if (rel == null) continue; // 非法条目静默跳过（不阻断整体恢复）
      final target = File('${staging.path}${Platform.pathSeparator}$rel');
      await target.parent.create(recursive: true);
      await target.writeAsBytes(content, flush: true);
    }

    // 写待恢复标记（含暂存目录绝对路径）——下次启动由
    // [AppDataRoot.applyPendingRestore] 消费。
    await AppDataRoot.writePendingRestoreMarker(
      documentsDir: documentsDir,
      stagingPath: staging.path,
    );
  }

  /// zip 条目名 → 根内相对路径；非法（绝对/盘符/上跳/空）返回 null。
  static String? _safeRelPath(String name) {
    var n = name.replaceAll('\\', '/');
    if (n.startsWith('/') || RegExp(r'^[A-Za-z]:').hasMatch(n)) return null;
    final parts = <String>[];
    for (final seg in n.split('/')) {
      if (seg.isEmpty || seg == '.') continue;
      if (seg == '..') return null;
      parts.add(seg);
    }
    if (parts.isEmpty) return null;
    return parts.join(Platform.pathSeparator);
  }

  /// 打包主体（在 isolate 内执行）：遍历数据根 → 过滤临时文件 → zip 落盘。
  static void _packSync(String rootPath, String destinationPath) {
    final root = Directory(rootPath);
    final archive = Archive();
    // 清单先行（恢复端第一道校验）。
    final manifest = utf8.encode(
      jsonEncode(<String, dynamic>{
        'formatVersion': kBackupFormatVersion,
        'createdAt': DateTime.now().toIso8601String(),
      }),
    );
    archive.addFile(
      ArchiveFile(kBackupManifestName, manifest.length, manifest),
    );

    final excludePattern = RegExp(r'\.(tmp|bak)(\..*)?$');
    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File) continue;
      final rel = entity.path.substring(rootPath.length);
      final norm = rel.replaceAll('\\', '/').replaceFirst(RegExp(r'^/+'), '');
      if (norm.isEmpty || excludePattern.hasMatch(norm)) continue;
      final bytes = entity.readAsBytesSync();
      archive.addFile(ArchiveFile(norm, bytes.length, bytes));
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
