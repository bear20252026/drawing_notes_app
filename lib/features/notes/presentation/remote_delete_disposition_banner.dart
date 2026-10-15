// A3-2 甲的手动处置入口（UI 层）。
//
// 为什么需要它：甲做到「不再复活 + 每轮可见」为止，剩下的不对称一直悬着——用户
// 看得见问题，却没有任何地方能处理它。本组件把那条缝闭上，同时守住批准的那条线：
// **程序不自己挑动作**，三个动作都由用户点。让删除自动赢是乙，会删用户的画布，没做。
//
// 只渲染 `staleCopy` 那一类：`localHasEdits`（本机有只此一份的内容）与
// `unknowable`（没证据）都照常上传，给它们摆按钮等于诱导用户在无损的场景里
// 做一次有代价的选择。
//
// 纯展示 + 单次回调：判定在 core（`detectRemoteDeletes`），动作在 SyncController，
// 「认云端删除」的二次确认也在父页面——这里不弹窗、不持状态、不自己删任何东西。

import 'package:flutter/material.dart';

import 'package:drawing_notes_app/core/sync/remote_deletes.dart';
import 'package:drawing_notes_app/core/theme/apple_design.dart';
import 'package:drawing_notes_app/l10n/app_localizations.dart';

/// 「云端已删、本机仍留着」的处置条。
class RemoteDeleteDispositionBanner extends StatelessWidget {
  const RemoteDeleteDispositionBanner({
    required this.issues,
    required this.enabled,
    required this.onDispose,
    super.key,
  });

  /// 上一轮同步算出的远端删除项（父页面原样传入，本组件自己筛 `staleCopy`）。
  final List<RemoteDeleteIssue> issues;

  /// 有一轮同步正在跑时禁用按钮（DN-002a 单飞互斥的 UI 侧同口径）。
  final bool enabled;

  /// 用户对某一篇选定的处置动作（父页面据此执行，并对「认云端删除」二次确认）。
  final void Function(String docId, RemoteDeleteDisposition disposition)
  onDispose;

  @override
  Widget build(BuildContext context) {
    final stale = issues
        .where((i) => i.kind == RemoteDeleteKind.staleCopy)
        .toList(growable: false);
    if (stale.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      // 与「刚恢复过备份」那条刻意区分：那不是错误（没有任何东西被损坏），
      // 而是一件需要用户决定的未决事项 ⇒ 中性底色 + 一次一行的列表。
      padding: const EdgeInsets.only(bottom: AppleSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.cloud_off_rounded,
                // 中性灰而不是错误红：这里没有任何东西被损坏，只是一个等用户
                // 决定的未决事项（跟「刚恢复过备份，同步已暂停」那条刻意不同）。
                color: AppleColor.mutedOf(scheme),
                size: 20,
              ),
              const SizedBox(width: AppleSpacing.sm),
              Expanded(
                child: Text(
                  l10n?.remoteDeleteHoldTitle(stale.length) ??
                      '云端已删除 ${stale.length} 篇，本机还留着同样的内容',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppleSpacing.xs),
          Text(
            l10n?.remoteDeleteHoldBody ??
                '同步已经把这几篇按住了（不会再推上云端），但本机这一份还在。'
                '下面三个动作都要你点：程序不会自己替你决定要不要删本机内容。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          for (final issue in stale)
            _row(context, issue, enabled: enabled, onDispose: onDispose),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context,
    RemoteDeleteIssue issue, {
    required bool enabled,
    required void Function(String docId, RemoteDeleteDisposition disposition)
    onDispose,
  }) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: AppleSpacing.sm),
      padding: const EdgeInsets.all(AppleSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppleRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            issue.docId,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: AppleSpacing.xs),
          Text(
            l10n?.remoteDeleteHoldReason ??
                '依据：本机这一版与云端删掉的正是同一版（同步后两端同一个版本号）。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppleSpacing.sm),
          Wrap(
            spacing: AppleSpacing.sm,
            runSpacing: AppleSpacing.xs,
            children: [
              TextButton(
                key: ValueKey('rdKeepAsCopy-${issue.docId}'),
                onPressed: enabled
                    ? () =>
                          onDispose(issue.docId, RemoteDeleteDisposition.keepAsCopy)
                    : null,
                child: Text(
                  l10n?.remoteDeleteKeepAsCopy ?? '本机这份另存为新笔记',
                ),
              ),
              TextButton(
                key: ValueKey('rdPushAnyway-${issue.docId}'),
                onPressed: enabled
                    ? () =>
                          onDispose(issue.docId, RemoteDeleteDisposition.pushAnyway)
                    : null,
                child: Text(l10n?.remoteDeletePushAnyway ?? '仍要上传到云端'),
              ),
              TextButton(
                // 三个动作里唯一会移走本机文件的：危险色 + 父页面二次确认。
                key: ValueKey('rdHonorDelete-${issue.docId}'),
                onPressed: enabled
                    ? () => onDispose(
                        issue.docId,
                        RemoteDeleteDisposition.honorCloudDelete,
                      )
                    : null,
                style: TextButton.styleFrom(foregroundColor: AppleColor.errorRed),
                child: Text(
                  l10n?.remoteDeleteHonorCloud ?? '认云端删除（本机移入回收站）',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
