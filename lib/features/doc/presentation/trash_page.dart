// 由 Claude 团队生成 | Drawing Notes App
// 回收站页（M12.6，AFFiNE Trash 对齐）：打字笔记软删除后的恢复/彻底删除。
//
// 结构：纯展示 + 注入的 store 操作回调（onRestore/onPurge），
// 数据经 loadTrash loader 提供——与列表页同模式，shell 统一装配。
library;

import 'package:flutter/material.dart';
import 'package:drawing_notes_app/core/theme/apple_design.dart';

import 'package:drawing_notes_app/features/doc/domain/note_block_doc.dart';

/// 回收站条目（store.listTrash 的记录类型）。
typedef TrashEntry = ({NoteBlockDoc doc, DateTime deletedAt});

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

  Future<void> _confirmPurge(TrashEntry entry) async {
    // R2-M4：改用公共 AppleDialog.confirm（原样板 24 行收敛为 7 行）。
    final ok = await AppleDialog.confirm(
      context,
      title: '彻底删除',
      content:
          '「${entry.doc.title.isEmpty ? '未命名' : entry.doc.title}」'
          '将被永久删除，无法恢复。确定继续吗？',
      confirmText: '彻底删除',
      dangerous: true,
    );
    if (ok) {
      await widget.onPurge(entry.doc.id);
      await _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('回收站')),
      body: entries == null
          ? const Center(child: CircularProgressIndicator())
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
                  const Text('回收站是空的'),
                  const SizedBox(height: 4),
                  Text(
                    '删除的笔记在此保留 30 天，可随时恢复',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: scheme.onSurfaceVariant,
                    ),
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
                    entry.doc.title.isEmpty ? '未命名' : entry.doc.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '删除于 '
                    '${deleted.year}-${deleted.month.toString().padLeft(2, '0')}-'
                    '${deleted.day.toString().padLeft(2, '0')}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: '恢复',
                        icon: const Icon(Icons.restore_rounded),
                        onPressed: () async {
                          await widget.onRestore(entry.doc.id);
                          await _reload();
                        },
                      ),
                      IconButton(
                        tooltip: '彻底删除',
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
