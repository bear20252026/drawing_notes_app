// DN-204（第三轮专家审计 2026-10-13）：恢复换根后的同步方向选择条。
//
// 存在的理由：`sync_state.json` 写在数据根**之外**，恢复备份只换了数据根，
// 基线还停留在恢复之前。此时同步若照旧推理，会把「基线有、本地无」的笔记
// 当成用户删除并真的删掉云端副本。审计要求的处置不是清空基线，而是先告诉
// 用户「这次恢复让基线失效了」，把两端差异摆出来，由用户选一个调和方向。
//
// 本组件是纯展示 + 单次回调：**不自己判定隔离**（判据在 core 的闸门里，
// 由 SyncController 透出），也不保存用户的选择——选择只活在被点下去的那一轮
// 同步里，那一轮成功后基线推进，隔离自然解除（见 `FilePostRestoreBaselineGate`）。

import 'package:flutter/material.dart';

import 'package:drawing_notes_app/core/sync/post_restore_baseline.dart';
import 'package:drawing_notes_app/core/theme/apple_design.dart';
import 'package:drawing_notes_app/l10n/app_localizations.dart';

/// 恢复后同步隔离提示条。`visible` 由持有 [SyncController] 的页面查询后传入。
class PostRestoreSyncBanner extends StatelessWidget {
  const PostRestoreSyncBanner({
    required this.visible,
    required this.enabled,
    required this.onReconcile,
    this.diff,
    super.key,
  });

  final bool visible;

  /// 有一轮同步正在跑时禁用按钮（DN-002a 单飞互斥的 UI 侧同口径）。
  final bool enabled;

  /// 用户在恢复后选定的调和方向（父页面据此发起那一轮同步）。
  final ValueChanged<PostRestoreReconcile> onReconcile;

  /// 上一轮只读比对算出的差异；还没比过为 null（此时不给数字，只给说明）。
  final PostRestoreDiff? diff;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final d = diff;
    return Container(
      // 卡片式：与设置页其余提示同族，但刻意用错误红描边——这是一条
      // 「不处理就会丢数据」的状态，不该长得像普通说明。
      padding: const EdgeInsets.all(AppleSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppleRadius.lg),
        border: Border.all(color: AppleColor.errorRed.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.link_off_rounded,
                color: AppleColor.errorRed,
                size: 20,
              ),
              const SizedBox(width: AppleSpacing.sm),
              Expanded(
                child: Text(
                  l10n?.postRestoreHoldTitle ?? '刚恢复过备份：同步已暂停',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppleSpacing.sm),
          Text(
            l10n?.postRestoreHoldBody ??
                '恢复只替换了本机的数据目录，同步基线还在原地。此时「本地没有的笔记」'
                '更可能是恢复的副作用，而不是你删掉的，所以在你选出一个方向之前：'
                '不删云端、不擅自上传。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (d != null) ...[
            const SizedBox(height: AppleSpacing.sm),
            Text(
              l10n?.postRestoreDiffSummary(
                    d.localOnlyIds.length,
                    d.remoteOnlyIds.length,
                    d.divergedIds.length,
                    d.suppressedTombstoneIds.length,
                  ) ??
                  '本地 ${d.localOnlyIds.length} 篇云端没有 · 云端 '
                  '${d.remoteOnlyIds.length} 篇本地没有 · 两端内容不同 '
                  '${d.divergedIds.length} 篇 · 已拦住「删除云端」'
                  '${d.suppressedTombstoneIds.length} 篇',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppleColor.errorTextOf(scheme),
              ),
            ),
          ],
          const SizedBox(height: AppleSpacing.sm),
          Wrap(
            spacing: AppleSpacing.sm,
            runSpacing: AppleSpacing.xs,
            alignment: WrapAlignment.start,
            children: [
              TextButton(
                key: const ValueKey('postRestoreShowDiff'),
                onPressed: enabled
                    ? () => onReconcile(PostRestoreReconcile.reportOnly)
                    : null,
                child: Text(l10n?.postRestoreHoldShowDiff ?? '先看差异'),
              ),
              TextButton(
                key: const ValueKey('postRestoreMerge'),
                onPressed: enabled
                    ? () => onReconcile(PostRestoreReconcile.merge)
                    : null,
                child: Text(l10n?.postRestoreHoldMerge ?? '合并两端'),
              ),
              TextButton(
                key: const ValueKey('postRestoreKeepRemote'),
                onPressed: enabled
                    ? () => onReconcile(PostRestoreReconcile.keepRemote)
                    : null,
                child: Text(l10n?.postRestoreHoldKeepRemote ?? '以云端为准'),
              ),
              TextButton(
                key: const ValueKey('postRestoreOverwriteRemote'),
                onPressed: enabled
                    ? () => onReconcile(PostRestoreReconcile.overwriteRemote)
                    : null,
                child: Text(
                  l10n?.postRestoreHoldOverwriteRemote ?? '用本机数据覆盖云端',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
