// 由 Claude 团队生成 | Drawing Notes App
// 同步基线持久化：把本地最后一次成功同步的 manifest 存成 JSON 文件
// （<docs>/sync_state.json），用于检测删除墓碑与脏标记。

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:drawing_notes_app/core/sync/sync_planner.dart';
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
    await file.writeAsString(jsonEncode(manifest.toJson()));
  }
}
