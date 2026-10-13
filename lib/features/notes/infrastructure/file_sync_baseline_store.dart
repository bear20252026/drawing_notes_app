// 由 Claude 团队生成 | Drawing Notes App
// 同步基线持久化：把本地最后一次成功同步的 manifest 存成 JSON 文件
// （<docs>/sync_state.json），用于检测删除墓碑与脏标记。

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';

import 'package:drawing_notes_app/core/sync/sync_planner.dart';
import 'package:drawing_notes_app/core/utils/hex_encode.dart';
import 'package:drawing_notes_app/core/sync/sync_service.dart';

/// 同步基线的默认落点（系统文档目录）。
///
/// 抽成函数而不是写死在两处：DN-204 的隔离判据 `FilePostRestoreBaselineGate`
/// 必须查**同一个文件**的修改时间，两处各调一次 `getApplicationDocumentsDirectory()`
/// 的话，将来改落点只改一边就会让隔离判据静默失效（查一个不存在的文件 ⇒
/// 永远「基线可信」⇒ 恢复后的误删照旧发生）。
Future<Directory> defaultSyncBaselineDirectory() =>
    getApplicationDocumentsDirectory();

/// 文件版 [SyncBaselineStore]。
class FileSyncBaselineStore implements SyncBaselineStore {
  FileSyncBaselineStore({this.directoryProvider});

  final Future<Directory> Function()? directoryProvider;

  /// 基线文件名。公开是因为 DN-204 的隔离判据要在**不复制这份路径拼接逻辑**
  /// 的前提下摸到同一个文件（见 `FilePostRestoreBaselineGate`）——两处各写一份
  /// 文件名的话，改名会让隔离判据静默地永远查一个不存在的文件。
  static const String baselineFileName = 'sync_state.json';

  Future<Directory> _baseDir() async {
    final provider = directoryProvider;
    if (provider != null) return provider();
    return defaultSyncBaselineDirectory();
  }

  Future<File> _file() async {
    final base = await _baseDir();
    return File('${base.path}${Platform.pathSeparator}$baselineFileName');

  }

  @override
  Future<SyncManifest?> load() async {
    final file = await _file();
    if (!file.existsSync()) return null;
    try {
      final raw = await file.readAsString();
      return SyncManifest.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null; // 损坏的基线按空处理（下次全量重新同步）。
    }
  }

  @override
  Future<void> save(SyncManifest manifest) async {
    final file = await _file();
    // A7 修复（审计 2026-09-07）：直写非原子——写入中断会留下半写基线，
    // 下轮同步误判（如把未确认的条目当墓碑源）。改随机后缀 tmp + rename +
    // 失败清理（favorite_store 同款纪律：随机名防固定 tmp 劫持，崩溃不留半写）。
    final r = Random.secure();
    final suffix = hexEncode(List<int>.generate(8, (_) => r.nextInt(256)));
    final tmp = File(
      '${file.path}.tmp.${DateTime.now().microsecondsSinceEpoch}.$suffix',
    );
    try {
      await tmp.writeAsString(jsonEncode(manifest.toJson()), flush: true);
      await tmp.rename(file.path);
    } catch (_) {
      try {
        if (tmp.existsSync()) await tmp.delete();
      } catch (_) {
        // 清理失败不覆盖原始存储异常。
      }
      rethrow;
    }
  }
}
