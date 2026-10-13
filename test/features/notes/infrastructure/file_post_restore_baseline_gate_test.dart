// DN-204：恢复换根后「基线是否已被甩在身后」的文件判据（gate 侧）。
//
// 判据只用磁盘上本来就有的两个事实：`.old_<毫秒>` 恢复前快照目录名里的换根时刻
// 与 `sync_state.json` 的修改时间。这里钉的是判据本身的六个分支——尤其
// 「成功同步过一轮之后隔离自动解除」这条，它是整套设计不需要清理代码的原因。

import 'dart:io';

import 'package:drawing_notes_app/core/storage/app_data_root.dart';
import 'package:drawing_notes_app/core/sync/sync_planner.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/file_post_restore_baseline_gate.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/file_sync_baseline_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/temp_dir_cleanup.dart';

void main() {
  late Directory baselineDir;
  late Directory supportDir;

  setUp(() async {
    baselineDir = await Directory.systemTemp.createTemp('pr_gate_docs_');
    supportDir = await Directory.systemTemp.createTemp('pr_gate_support_');
  });

  tearDown(() async {
    for (final dir in [baselineDir, supportDir]) {
      if (dir.existsSync()) await deleteTempDirWithRetry(dir);
    }
  });

  FilePostRestoreBaselineGate gate() => FilePostRestoreBaselineGate(
    baselineDirProvider: () async => baselineDir,
    restoreSnapshotDirProvider: () async => supportDir,
  );

  /// 写一条基线，并把它的修改时间钉在 [writtenAtMs]（真实恢复场景里
  /// 「基线何时写成」正是判据的另一半）。
  Future<void> writeBaselineAt(int writtenAtMs) async {
    await FileSyncBaselineStore(
      directoryProvider: () async => baselineDir,
    ).save(
      SyncManifest(
        entries: {
          'c': const SyncSnapshot(id: 'c', updatedAt: 1, size: 8),
        },
      ),
    );
    final file = File(
      '${baselineDir.path}${Platform.pathSeparator}'
      '${FileSyncBaselineStore.baselineFileName}',
    );
    await file.setLastModified(
      DateTime.fromMillisecondsSinceEpoch(writtenAtMs),
    );
  }

  void seedSnapshot(int swapMs) {
    Directory(
      '${supportDir.path}${Platform.pathSeparator}'
      '${AppDataRoot.defaultRootName}.old_$swapMs',
    ).createSync(recursive: true);
  }

  group('隔离判据', () {
    test('换根晚于基线写盘 ⇒ 基线不可信，同步进入恢复后首次模式', () async {
      await writeBaselineAt(1_000);
      seedSnapshot(2_000);
      expect(await gate().isBaselineStaleAfterRestore(), isTrue);
    });

    test('恢复后又成功同步过（基线晚于换根）⇒ 隔离自动解除', () async {
      seedSnapshot(1_000);
      await writeBaselineAt(2_000);
      expect(
        await gate().isBaselineStaleAfterRestore(),
        isFalse,
        reason: '基线已经描述现网，不该继续拦着同步——否则用户永远看着一个没有出口的暂停',
      );
    });

    test('同一毫秒内写成的基线按「未同步」处理（宁可多隔离一次）', () async {
      seedSnapshot(1_500);
      await writeBaselineAt(1_500);
      expect(await gate().isBaselineStaleAfterRestore(), isTrue);
    });

    test('没有任何恢复前快照 ⇒ 没发生过换根，判据不凭空造隔离态', () async {
      await writeBaselineAt(1_000);
      expect(await gate().isBaselineStaleAfterRestore(), isFalse);
    });

    test('有快照但还没有基线文件 ⇒ 真正的首次同步，没有可误用的旧状态', () async {
      seedSnapshot(2_000);
      expect(await gate().isBaselineStaleAfterRestore(), isFalse);
    });

    test('取最近一次换根：更早的快照不参与判定', () async {
      seedSnapshot(1_000);
      seedSnapshot(9_000);
      await writeBaselineAt(5_000);
      expect(
        await gate().isBaselineStaleAfterRestore(),
        isTrue,
        reason: '9_000 那次换根才是分界线',
      );
      expect(AppDataRoot.latestRestoreSnapshotMs(supportDir.path), 9_000);
    });

    test('解析不出时间戳的目录不参与判定（不猜它是什么）', () async {
      Directory(
        '${supportDir.path}${Platform.pathSeparator}'
        '${AppDataRoot.defaultRootName}.old_待清理',
      ).createSync(recursive: true);
      await writeBaselineAt(1_000);
      expect(await gate().isBaselineStaleAfterRestore(), isFalse);
      expect(AppDataRoot.latestRestoreSnapshotMs(supportDir.path), isNull);
    });

    test('快照目录不存在时 latestRestoreSnapshotMs 返回 null（不抛）', () {
      expect(
        AppDataRoot.latestRestoreSnapshotMs(
          '${supportDir.path}${Platform.pathSeparator}nope',
        ),
        isNull,
      );
    });
  });
}
