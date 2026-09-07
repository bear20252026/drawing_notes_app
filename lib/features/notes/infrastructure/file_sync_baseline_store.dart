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

/// 文件版 [SyncBaselineStore]。
class FileSyncBaselineStore implements SyncBaselineStore {
  FileSyncBaselineStore({this.directoryProvider});

  final Future<Directory> Function()? directoryProvider;
  static const _fileName = 'sync_state.json';

  Future<Directory> _baseDir() async {
    final provider = directoryProvider;
    if (provider != null) return provider();
    return getApplicationDocumentsDirectory();
  }

  Future<File> _file() async {
    final base = await _baseDir();
    return File('${base.path}${Platform.pathSeparator}$_fileName');
  }

  @override
  Future<SyncManifest?> load() async {
    final file = await _file();
    if (!await file.exists()) return null;
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
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {
        // 清理失败不覆盖原始存储异常。
      }
      rethrow;
    }
  }
}
