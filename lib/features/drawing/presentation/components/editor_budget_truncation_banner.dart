import 'package:flutter/material.dart';

import 'package:drawing_notes_app/core/storage/document_budgets.dart';
import 'package:drawing_notes_app/core/theme/apple_design.dart';
import 'package:drawing_notes_app/l10n/app_localizations.dart';
import 'package:drawing_notes_app/shared/widgets/apple_pressable.dart';
import 'package:drawing_notes_app/shared/widgets/glass_dialog.dart';

/// 画布「预算截断态」的**常驻**说明条 + 唯一破坏性处置入口（DN-003 处置，
/// 2026-10-11）。
///
/// 为什么必须有它：解码有防御预算而写入没有 ⇒ 单层画过 1 万笔的用户重开自己的
/// 画布时会被静默截断，而 5s 自动保存会把截断结果覆盖回原件（真丢数据）。
/// 上一批已经让 `StorageService.save` 在这种状态下**同步拒绝覆盖**，但
/// `acknowledgeBudgetTruncation` 生产零调用方——用户看得见「保存失败」却没有任何
/// 出口，等于被关死。本组件就是那个出口。
///
/// 三条设计约束（docs/DESIGN_SYSTEM.md）：
/// - 画布是**内容层**：一个像素的玻璃都不许加，这里用扁平实色 `errorContainer`
///   （形态取自设置页明文横幅 `lockPlaintextNotice` 与 `CloudSyncNoticeHost`——
///   本仓「常驻状态说明」的既有先例，而不是新造一层）；
/// - 处置是**显式**的：只有二次确认通过才调 `acknowledgeBudgetTruncation`，
///   它不是任何自动路径的副产物，也刻意没有「以后不再提示」；
/// - 三输入可达：按钮走主题层 `FilledButton`（命中区 44×44，键盘 Enter/Space
///   原生可达），外层 `ApplePressable` 补 0.95 按压态。
class EditorBudgetTruncationBanner extends StatelessWidget {
  const EditorBudgetTruncationBanner({
    super.key,
    required this.report,
    required this.onOverride,
  });

  /// 那次解码的完整性统计（「已恢复 / 预算丢弃 / 损坏剔除」三类计数的来源）。
  final DocumentDecodeReport report;

  /// 用户点了「用当前内容覆盖原文件」——**确认与放行由调用方负责**，
  /// 本组件不碰存储与闸门。
  final VoidCallback onOverride;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final tone = AppleColor.errorTextOf(scheme);
    final droppedObjects = report.objectsDroppedByBudget;
    final droppedPoints = report.pointsDroppedByBudget;
    return Material(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppleSpacing.sm,
          vertical: AppleSpacing.xs,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(Icons.difference_rounded, size: 18, color: tone),
            const SizedBox(width: AppleSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n?.budgetTruncatedTitle ?? '画布内容比磁盘上的原文件少',
                    style: AppleType.controlStyle(tone).copyWith(
                      fontWeight: AppleType.semibold,
                    ),
                  ),
                  const SizedBox(height: AppleSpacing.xxs),
                  Text(
                    l10n?.budgetTruncatedBody(
                          report.strokesRestored,
                          report.strokesDroppedByBudget,
                        ) ??
                        '本次只载入了 ${report.strokesRestored} 笔，另有 '
                        '${report.strokesDroppedByBudget} 笔被读取预算丢弃。'
                        '磁盘上的原文件没有被改动，自动保存与手动保存都已停止覆盖它。',
                    style: AppleType.bodyStyle(scheme.onErrorContainer),
                  ),
                  if (droppedObjects > 0 || droppedPoints > 0) ...[
                    const SizedBox(height: AppleSpacing.xxs),
                    Text(
                      l10n?.budgetTruncatedMore(
                            droppedObjects,
                            droppedPoints,
                          ) ??
                          '此外还有 $droppedObjects 个图形/图片/文字、'
                          '$droppedPoints 个采样点未载入。',
                      style: AppleType.captionStyle(scheme.onErrorContainer),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppleSpacing.xs),
            ApplePressable(
              // onTap 为 null：手势交给 FilledButton 本体（键盘通道由 Material
              // 按钮自己处理），本层只负责 0.95 按压缩放。
              child: FilledButton(
                onPressed: onOverride,
                style: FilledButton.styleFrom(
                  backgroundColor: tone,
                  foregroundColor: scheme.errorContainer,
                ),
                child: Text(l10n?.budgetTruncatedOverride ?? '用当前内容覆盖原文件'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 「用当前内容覆盖原文件」的**二次确认**（唯一的破坏性处置，DN-003）。
///
/// 确认文案重复会被丢弃的数量并写明不可恢复；返回 true 才允许调用
/// `StorageService.acknowledgeBudgetTruncation`。危险档下初始焦点落在安全的
/// 取消一侧（`AppleDialog.confirm(dangerous: true)`），误触 Enter 不会覆盖原件。
Future<bool> confirmBudgetTruncationOverride(
  BuildContext context,
  DocumentDecodeReport report,
) {
  final l10n = AppLocalizations.of(context);
  return GlassDialog.confirm(
    context,
    dangerous: true,
    title:
        l10n?.budgetTruncatedConfirmTitle ?? '确认用当前内容覆盖原文件？',
    content:
        l10n?.budgetTruncatedConfirmBody(
              report.strokesRestored,
              report.strokesDroppedByBudget,
            ) ??
            '覆盖后，文件里只剩当前这份内容：共 ${report.strokesRestored} 笔，'
            '被丢弃的 ${report.strokesDroppedByBudget} 笔将无法找回。'
            '原文件不会被备份到别处，此操作不可恢复。',
    confirmText: l10n?.budgetTruncatedOverrideConfirm ?? '覆盖原文件',
  );
}

/// 退出点的「还有改动没落盘」裁决（DN-005）。
///
/// 强制保存正常返回**不等于**已落盘：失败策略退避/放弃时保存链同样收敛。
/// 因此两个 pop 点必须先把这一态交给用户裁决，返回 true = 「仍要离开」。
/// 默认焦点在「留下继续编辑」（危险档），不默认放行丢失。
Future<bool> confirmLeaveWithUnsavedChanges(
  BuildContext context, {
  required bool blockedByBudgetTruncation,
}) {
  final l10n = AppLocalizations.of(context);
  return GlassDialog.confirm(
    context,
    dangerous: true,
    title: l10n?.unsavedExitTitle ?? '还有改动没有保存到磁盘',
    content: blockedByBudgetTruncation
        ? (l10n?.unsavedExitBodyTruncated ??
              '这份画布是以截断态打开的，为避免覆盖原文件，保存按设计被拒绝。'
              '现在离开，本次会话里的改动不会出现在文件里。'
              '确实要用当前内容替换原文件，请先在页面上方的说明里点「用当前内容覆盖原文件」。')
        : (l10n?.unsavedExitBody ??
              '这次保存失败了，现在离开，本次会话里的改动不会出现在文件里。'
              '可以留下继续编辑（稍后会再试一次），也可以带着未保存的改动离开。'),
    confirmText: l10n?.unsavedExitLeave ?? '仍要离开',
    cancelText: l10n?.unsavedExitStay ?? '留下继续编辑',
  );
}
