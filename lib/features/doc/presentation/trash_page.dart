// 由 Claude 团队生成 | Drawing Notes App
// 回收站页（M12.6，AFFiNE Trash 对齐）：打字笔记软删除后的恢复/彻底删除。
//
// 结构：纯展示 + 注入的 store 操作回调（onRestore/onPurge），
// 数据经 loadTrash loader 提供——与列表页同模式，shell 统一装配。
library;

import 'package:flutter/material.dart';
import 'package:drawing_notes_app/l10n/app_localizations.dart';

import 'package:drawing_notes_app/core/storage/storage_service.dart';
import 'package:drawing_notes_app/core/utils/domain_display_labels.dart';
import 'package:drawing_notes_app/shared/utils/time_format.dart';
import 'package:drawing_notes_app/shared/widgets/glass_dialog.dart';
import 'package:drawing_notes_app/shared/widgets/skeleton.dart';

import '../../../core/theme/apple_design.dart';

/// 回收站条目（store.listTrash 的轻量记录类型，审计 2026-09-26 #32：
/// 整棵文档树不跨 isolate/不进列表，UI 只消费 id/title/locked/deletedAt）。
typedef TrashEntry = ({String id, String title, bool locked, DateTime deletedAt});

/// 回收站页。
class TrashPage extends StatefulWidget {
  const TrashPage({
    super.key,
    required this.loadTrash,
    required this.onRestore,
    required this.onPurge,
  });

  final Future<List<TrashEntry>> Function() loadTrash;
  final Future<bool> Function(String docId) onRestore;
  final Future<bool> Function(String docId) onPurge;

  @override
  State<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends State<TrashPage> {
  List<TrashEntry>? _entries;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final entries = await widget.loadTrash();
    if (!mounted) return;
    setState(() => _entries = entries);
  }

  /// M6：这一条还能恢复几天。已过期但尚未被惰性清理带走的条目显示
  /// 「今天到期」——负数对用户没有意义，而它确实还躺在回收站里。
  String _retentionLabel(DateTime deletedAt) {
    final l10n = AppLocalizations.of(context);
    final daysLeft =
        StorageService.trashRetentionDays -
        DateTime.now().difference(deletedAt).inDays;
    if (daysLeft <= 0) {
      return l10n?.homeTrashExpiresToday ?? '剩余保留期：今天到期';
    }
    return l10n?.homeTrashRemainingDays(daysLeft) ?? '剩余保留期：$daysLeft 天';
  }

  Future<void> _confirmPurge(TrashEntry entry) async {
    // R2-M4：改用公共 AppleDialog.confirm（原样板 24 行收敛为 7 行）。
    final ok = await GlassDialog.confirm(
      context,
      title: AppLocalizations.of(context)?.trashDeleteForeverTitle ?? '彻底删除',
      content:
          '「${DomainDisplayLabels.docTitleWithLock(AppLocalizations.of(context), entry.title, locked: entry.locked)}」'
          '将被永久删除，无法恢复。确定继续吗？',
      confirmText:
          AppLocalizations.of(context)?.trashDeleteForeverTitle ?? '彻底删除',
      dangerous: true,
    );
    if (ok) {
      await widget.onPurge(entry.id);
      await _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)?.trashTitleBar ?? '回收站'),
      ),
      body: entries == null
          // 审计二-6：列表加载骨架屏（形态先行）。
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: SkeletonList(rows: 6),
            )
          : entries.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.delete_outline_rounded,
                    size: 56,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    AppLocalizations.of(context)?.trashEmptyTitle ?? '回收站是空的',
                  ),
                  const SizedBox(height: 4),
                  Text(
                    AppLocalizations.of(context)?.trashEmptyTip ??
                        '删除的笔记在此保留 30 天，可随时恢复',
                    style: AppleType.captionStyle(scheme.onSurfaceVariant),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: entries.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: scheme.outlineVariant),
              itemBuilder: (context, i) {
                final entry = entries[i];
                final deleted = entry.deletedAt;
                return ListTile(
                  leading: const Icon(Icons.edit_note_rounded),
                  title: Text(
                    DomainDisplayLabels.docTitleWithLock(
                      AppLocalizations.of(context),
                      entry.title,
                      locked: entry.locked,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.of(context)?.homeDeletedAt(
                              formatShortDate(deleted),
                            ) ??
                            '删除于 ${formatShortDate(deleted)}',
                      ),
                      // M6：保留期必须让条目自己说，而不是只写在空状态提示里
                      // （空状态只在回收站**没有东西**时可见）。剩余天数与 purge
                      // 的过期判据同源，不引入第二处口径。
                      Text(
                        _retentionLabel(deleted),
                        style: AppleType.captionStyle(
                          scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip:
                            AppLocalizations.of(context)?.trashRestore ?? '恢复',
                        icon: const Icon(Icons.restore_rounded),
                        onPressed: () async {
                          await widget.onRestore(entry.id);
                          await _reload();
                        },
                      ),
                      IconButton(
                        tooltip:
                            AppLocalizations.of(
                              context,
                            )?.trashDeleteForeverTitle ??
                            '彻底删除',
                        icon: Icon(
                          Icons.delete_forever_rounded,
                          color: scheme.error,
                        ),
                        onPressed: () => _confirmPurge(entry),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
