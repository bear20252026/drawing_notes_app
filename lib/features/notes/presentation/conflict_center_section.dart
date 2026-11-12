// 冲突中心（SYNC-003 前半句）：同步设置页里的一块常驻区域，展示持久化的冲突台账，
// 并提供「改判」入口。
//
// 与 `RemoteDeleteDispositionBanner` 的分工：那块处理的是「云端已删、本机还留着」
// 的**未决**不对称（本轮刚算出来的，要给动作）；这块处理的是**历史**——冲突发生在
// 那轮同步，用户现在才回来看。共同纪律是「程序不自己挑动作」：这里所有按钮都只把
// 用户的决定记进台账，程序不会替用户选。
//
// 纯展示 + 单次回调：判定在 core（台账条目自带全部事实），动作在 SyncController
// （写台账 / 读台账），「改判」的二次确认也在父页面——这里不持状态、不自己写盘。
//
// ⚠ 一条必须对用户说清的边界（写在这里是因为 UI 文案全靠这个文件兜底）：
// 改判只影响**下一次**这篇再冲突时的方向，**不撤销**已经发生的那次覆盖。
// keepLocal/keepRemote 执行之后，输掉那一侧的字节就已经不存在了（只有 keepBoth
// 会留副本），没有任何存储层操作能把它们找回来。文案不许暗示可以「恢复」。

import 'package:flutter/material.dart';

import 'package:drawing_notes_app/core/sync/sync_conflict.dart';
import 'package:drawing_notes_app/core/sync/sync_conflict_ledger.dart';
import 'package:drawing_notes_app/core/theme/apple_design.dart';
import 'package:drawing_notes_app/features/notes/presentation/conflict_resolution_dialog.dart';
import 'package:drawing_notes_app/l10n/app_localizations.dart';
import 'package:drawing_notes_app/shared/utils/time_format.dart';

/// 冲突台账区。空台账时整块不渲染（与远端删除处置条同一处理）。
class ConflictCenterSection extends StatelessWidget {
  const ConflictCenterSection({
    required this.entries,
    required this.enabled,
    required this.onOverride,
    required this.onClearOverride,
    super.key,
  });

  /// 台账条目（父页面从 SyncController 读出后原样传入，按最近冲突时刻倒序）。
  final List<ConflictLedgerEntry> entries;

  /// 有一轮同步正在跑时禁用按钮（DN-002a 单飞互斥的 UI 侧同口径）。
  final bool enabled;

  /// 用户为某条记录选定了一个新的处理方向（父页面写入台账）。
  final void Function(ConflictLedgerEntry entry, ConflictResolution resolution)
  onOverride;

  /// 用户清除了某条记录的改判（回到「下次重新问」）。
  final void Function(ConflictLedgerEntry entry) onClearOverride;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppleSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.history_rounded,
                // 中性灰：台账是历史记录，不是错误。用 history 图标而不是
                // warning/同步图标——这里没有任何东西等着被修。
                color: AppleColor.mutedOf(Theme.of(context).colorScheme),
                size: 20,
              ),
              const SizedBox(width: AppleSpacing.sm),
              Expanded(
                child: Text(
                  l10n?.conflictCenterTitle ?? '冲突记录',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppleSpacing.xs),
          Text(
            l10n?.conflictCenterBody ??
                '这里记着每次同步时本地与云端都被改过的文档，以及当时按什么处理了。'
                '记录不会因为同步成功就消失。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          for (final e in entries)
            _row(context, e, enabled: enabled),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context,
    ConflictLedgerEntry e, {
    required bool enabled,
  }) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final c = e.lastConflict;
    final resolution = c.resolvedResolution;
    return Container(
      margin: const EdgeInsets.only(top: AppleSpacing.sm),
      padding: const EdgeInsets.all(AppleSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppleRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  e.docId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              if (e.hasOverride)
                Padding(
                  padding: const EdgeInsets.only(left: AppleSpacing.xs),
                  child: Text(
                    l10n?.conflictCenterOverridden ?? '已改判',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppleSpacing.xs),
          Text(
            l10n?.conflictCenterCount(e.count) ?? '冲突过 ${e.count} 次',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: AppleSpacing.xs),
          Text(
            _reason(l10n, c),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: AppleSpacing.xs),
          Text(
            '${l10n?.conflictLocalMeta(_fmt(c.localUpdatedAt), '${c.localSize}') ?? '本地 ${_fmt(c.localUpdatedAt)} · ${c.localSize}B'}'
            '   |   '
            '${l10n?.conflictRemoteMeta(_fmt(c.remoteUpdatedAt), '${c.remoteSize}') ?? '云端 ${_fmt(c.remoteUpdatedAt)} · ${c.remoteSize}B'}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: AppleSpacing.xs),
          Text(
            resolution == null
                ? (l10n?.conflictCenterAutoResolved ?? '当时未选择，按默认规则处理')
                : (l10n?.conflictCenterThen(
                        conflictResolutionLabel(resolution, l10n),
                      ) ??
                      '当时按「${conflictResolutionLabel(resolution, l10n)}」处理'),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: AppleSpacing.sm),
          Wrap(
            spacing: AppleSpacing.sm,
            runSpacing: AppleSpacing.xs,
            children: [
              TextButton(
                key: ValueKey('ccOverride-${e.docId}'),
                onPressed: enabled ? () => _askOverride(context, e) : null,
                child: Text(
                  l10n?.conflictCenterOverrideAction ?? '改判',
                ),
              ),
              if (e.hasOverride)
                TextButton(
                  key: ValueKey('ccClearOverride-${e.docId}'),
                  onPressed: enabled ? () => onClearOverride(e) : null,
                  child: Text(
                    l10n?.conflictCenterClearOverrideAction ?? '清除改判',
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// 弹出三选一的改判窗（取消 = 不改）。
  Future<void> _askOverride(
    BuildContext context,
    ConflictLedgerEntry entry,
  ) async {
    final l10n = AppLocalizations.of(context);
    final picked = await showDialog<ConflictResolution>(
      context: context,
      builder: (_) => _OverrideDialog(entry: entry),
    );
    if (picked == null) return;
    onOverride(entry, picked);
    // 只在仍挂载时取 l10n：await 之后 context 可能已失效。
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          l10n?.conflictCenterOverrideSet(
                conflictResolutionLabel(picked, l10n),
              ) ??
              '已记录：下次这篇冲突时按「${conflictResolutionLabel(picked, l10n)}」处理',
        ),
      ),
    );
  }

  /// 命中了哪条判据（优先级从高到低，只显示最主要的一条——多条同时成立时
  /// 全列出来会让这一行长到不可读，而用户真正需要的是「为什么会被报冲突」）。
  static String _reason(AppLocalizations? l10n, SyncConflict c) {
    if (c.remoteTimestampUntrusted) {
      return l10n?.conflictCenterReasonRemoteUntrusted ??
          '原因是云端时间戳不可信（可能来自偏快的时钟）';
    }
    if (c.localUnchangedSinceBaseline) {
      return l10n?.conflictCenterReasonLocalUnchanged ??
          '原因是本地没改过，只有云端改过';
    }
    if (c.contentUnverifiable) {
      return l10n?.conflictCenterReasonUnverifiable ??
          '原因是无法确认两端内容是否相同';
    }
    if (c.fingerprintTie) {
      return l10n?.conflictCenterReasonFingerprintTie ??
          '原因是时间戳与字节数完全相同、但内容不同';
    }
    return l10n?.conflictCenterReasonBothEdited ??
        '原因是本地与云端都改过，且内容不同';
  }

  /// 与裁决窗同一条读数口径（L-20：月-日复用 time_format，不手拼）。
  static String _fmt(int epochMs) {
    final dt = DateTime.fromMillisecondsSinceEpoch(epochMs);
    return '${formatMonthDay(dt)} ${formatClock(dt)}';
  }
}

/// 改判窗：为一篇文档选定「下次冲突时」的处理方向。
///
/// 与 [ConflictResolutionDialog] 的区别：那个是**当下**就要执行的决定（本轮同步
/// 正等着它），这个是**长期**方向（写进台账，下次才用）。所以措辞必须点明
/// 「下次」，且明说不能撤销上次——否则用户会以为点完就能把上次的选择改回来。
class _OverrideDialog extends StatefulWidget {
  const _OverrideDialog({required this.entry});

  final ConflictLedgerEntry entry;

  @override
  State<_OverrideDialog> createState() => _OverrideDialogState();
}

class _OverrideDialogState extends State<_OverrideDialog> {
  late ConflictResolution _choice;

  @override
  void initState() {
    super.initState();
    // 默认落在现有改判上（有则沿用，无则用程序建议）——打开就能看到当前状态，
    // 而不是每次都从建议值开始，让人误以为还没设过。
    _choice =
        widget.entry.resolutionOverride ??
        widget.entry.lastConflict.suggestedResolution;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(
        l10n?.conflictCenterOverrideDialogTitle ?? '这篇下次冲突时怎么处理？',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.entry.docId,
            style: theme.textTheme.titleSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppleSpacing.sm),
          Text(
            l10n?.conflictCenterOverrideDialogBody ??
                '改判只影响下一次这篇再冲突时的处理方向，不会撤销已经发生的那次覆盖——'
                '输掉的那一侧内容在当时就已经不存在了。',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: AppleSpacing.sm),
          RadioGroup<ConflictResolution>(
            groupValue: _choice,
            onChanged: (v) => setState(() => _choice = v!),
            child: Column(
              children: [
                for (final r in ConflictResolution.values)
                  // 整行可点：触屏上点文字标签是最自然的姿势，而 Radio 自己的
                  // 触控区只有它周围那一圈。命中行为 opaque 保证空白处也归本行。
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _choice = r),
                    child: Row(
                      children: [
                        Radio<ConflictResolution>(value: r),
                        Text(
                          conflictResolutionLabel(r, l10n),
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n?.cancel ?? '取消'),
        ),
        FilledButton(
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(_choice),
          child: Text(l10n?.conflictCenterOverrideAction ?? '改判'),
        ),
      ],
    );
  }
}
