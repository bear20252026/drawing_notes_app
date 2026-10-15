// 文件版 [SyncPushWaiverStore]：与同步基线同目录（数据根**之外**），同样一份
// 随机后缀 tmp + rename 的原子写纪律（A7 修复那条），失败只清理自己建的临时文件。
//
// 为什么和基线放一起而不是数据根内：见 `lib/core/sync/sync_push_waivers.dart` 头部
// 那段——恢复旧数据根之后不该继承上次的豁免，否则一次恢复会悄悄把云端改回旧版。

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drawing_notes_app/core/storage/storage_directories.dart';
import 'package:drawing_notes_app/core/sync/sync_push_waivers.dart';
import 'package:drawing_notes_app/core/utils/hex_encode.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/file_sync_baseline_store.dart'
    show defaultSyncBaselineDirectory;

class FileSyncPushWaiverStore implements SyncPushWaiverStore {
  FileSyncPushWaiverStore({this.directoryProvider});

  final Future<Directory> Function()? directoryProvider;

  /// 与 `FileSyncBaselineStore.baselineFileName` 同一条纪律：文件名只有这一处定义，
  /// 测试与将来的诊断都从这里取，避免两处各拼一份、改名后静默读到不存在的文件。
  static const String fileName = 'sync_push_waivers.json';

  Future<File> _file() async {
    final provider = directoryProvider;
    final base = provider != null
        ? await provider()
        : await defaultSyncBaselineDirectory();
    return File('${base.path}${Platform.pathSeparator}$fileName');
  }

  @override
  Future<Set<String>> load() async {
    final file = await _file();
    if (!file.existsSync()) return <String>{};
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return <String>{};
      final ids = decoded['waived'];
      if (ids is! List) return <String>{};
      // 只收合法文档 id：这个集合会被拼进路径与请求，畸形条目按**丢弃**处理
      // （丢弃的后果是继续按住，保守方向）。
      return <String>{
        for (final id in ids.whereType<String>())
          if (StorageDirectories.validIdPattern.hasMatch(id)) id,
      };
    } catch (_) {
      return <String>{}; // 损坏 ⇒ 空集（继续按住），见上面 load() 的契约。
    }
  }

  @override
  Future<void> save(Set<String> ids) async {
    final file = await _file();
    final r = Random.secure();
    final suffix = hexEncode(List<int>.generate(8, (_) => r.nextInt(256)));
    final tmp = File(
      '${file.path}.tmp.${DateTime.now().microsecondsSinceEpoch}.$suffix',
    );
    final sorted = [...ids]..sort(); // 稳定序：同一集合两次写出逐字节一致
    try {
      await tmp.writeAsString(
        jsonEncode({'waived': sorted}),
        flush: true,
      );
      await tmp.rename(file.path);
    } catch (_) {
      try {
        if (tmp.existsSync()) await tmp.delete();
      } catch (_) {
        // 清理失败不覆盖原始异常。
      }
      rethrow;
    }
  }
}
