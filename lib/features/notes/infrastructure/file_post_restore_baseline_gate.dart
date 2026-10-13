// DN-204（第三轮专家审计 2026-10-13）：文件版「基线是否落后于最近一次换根」判据。
//
// 判据的两个事实都写在磁盘上，不需要任何一方「记得」额外登记一件事：
// - 换根时间戳：`applyPendingRestore` 把现网根改名成 `.old_<毫秒>` 快照（DN-208
//   起这份快照会被保留），目录名里的毫秒就是换根发生的时刻；
// - 基线时间戳：`sync_state.json` 的修改时间 = 上一轮成功同步回写基线的时刻。
// 基线不晚于快照 ⇒ 这次换根之后一轮同步都没走完 ⇒ 基线描述的不是当前数据根。
//
// 为什么不用「恢复时写一条隔离标记」：那条标记是换根之后的**第二步**，
// 「换根成功但标记没写上」的崩溃窗口正好把最危险的状态（旧基线 + 新数据根）
// 暴露给下一轮同步。改成从事实反推，窗口不存在；且成功同步一次之后基线
// 自动推进，隔离**自动解除**，不需要任何清理代码。

import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:drawing_notes_app/core/storage/app_data_root.dart';
import 'package:drawing_notes_app/core/sync/post_restore_baseline.dart';

import 'file_sync_baseline_store.dart';

/// 文件版 [PostRestoreBaselineGate]。
class FilePostRestoreBaselineGate implements PostRestoreBaselineGate {
  FilePostRestoreBaselineGate({
    this.baselineDirProvider,
    this.restoreSnapshotDirProvider,
  });

  /// 基线所在目录（默认与 `FileSyncBaselineStore` 同一出口，见
  /// [defaultSyncBaselineDirectory]）。
  final Future<Directory> Function()? baselineDirProvider;

  /// `.old_<毫秒>` 恢复前快照所在目录（默认 ApplicationSupport——
  /// `applyPendingRestore` 的快照就落在这里，两侧默认值必须一致）。
  final Future<Directory> Function()? restoreSnapshotDirProvider;

  @override
  Future<bool> isBaselineStaleAfterRestore() async {
    final String snapshotPath;
    final String baselinePath;
    try {
      final provider = restoreSnapshotDirProvider;
      final dir = provider != null
          ? await provider()
          : await getApplicationSupportDirectory();
      snapshotPath = dir.path;
      final dirProvider = baselineDirProvider;
      final baseDir = dirProvider != null
          ? await dirProvider()
          : await defaultSyncBaselineDirectory();
      baselinePath =
          '${baseDir.path}${Platform.pathSeparator}'
          '${FileSyncBaselineStore.baselineFileName}';
    } catch (_) {
      // 连目录都定位不了：本轮不隔离（与「磁盘上没有换根证据」同口径）。
      // 这里造不出恢复事件，凭空隔离会让同步永久停在「等待裁决」且用户
      // 没有任何信息可以裁决。
      return false;
    }
    final swapMs = AppDataRoot.latestRestoreSnapshotMs(snapshotPath);
    if (swapMs == null) return false;
    final file = File(baselinePath);
    final DateTime written;
    try {
      // Windows 上畸形路径的 existsSync()/stat 会直接抛（errno 123 一族），
      // 与「基线存在但读不到时间戳」合并处理：宁可多隔离一次。
      if (!file.existsSync()) return false; // 无基线 = 真正的首次同步，没有可误用的旧状态
      written = file.lastModifiedSync();
    } catch (_) {
      return true;
    }
    return written.millisecondsSinceEpoch <= swapMs;
  }
}
