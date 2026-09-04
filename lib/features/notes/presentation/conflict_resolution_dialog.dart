// WebDAV 冲突解析对话框：用户逐条裁决「保留本地/远端/两者皆留」。
//
// 纯展示层：输入一个或多个 SyncConflict，返回 Map<docId, ConflictResolution>。
// 通过 showDialog<Map<String, ConflictResolution>> 使用；取消返回 null（走默认 LWW）。

import 'package:flutter/material.dart';

import 'package:drawing_notes_app/core/sync/sync_conflict.dart';
import 'package:drawing_notes_app/core/theme/apple_design.dart';

class ConflictResolutionDialog extends StatefulWidget {
  const ConflictResolutionDialog({super.key, required this.conflicts});

  final List<SyncConflict> conflicts;

  @override
  State<ConflictResolutionDialog> createState() =>
      _ConflictResolutionDialogState();
}

class _ConflictResolutionDialogState extends State<ConflictResolutionDialog> {
  late final Map<String, ConflictResolution> _choices;

  @override
  void initState() {
    super.initState();
    _choices = {
      for (final c in widget.conflicts) c.docId: c.suggestedResolution,
    };
  }

  Future<void> _apply() async {
    Navigator.of(context).pop(Map<String, ConflictResolution>.from(_choices));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('同步冲突（${widget.conflicts.length} 个文档）'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '这些文档在本地与云端都被修改过，无法自动决定以哪边为准。',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            for (final c in widget.conflicts) _buildConflict(theme, c),
          ],
        ),
      ),
      actions: AppleDialog.actions([
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _apply, child: const Text('应用全部')),
      ]),
    );
  }

  Widget _buildConflict(ThemeData theme, SyncConflict c) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(c.docId, style: theme.textTheme.titleSmall),
          Text(
            '本地 ${_fmt(c.localUpdatedAt)} · ${c.localSize}B   |   云端 ${_fmt(c.remoteUpdatedAt)} · ${c.remoteSize}B'
            '${c.localNewer
                ? '（本地较新）'
                : c.remoteNewer
                ? '（云端较新）'
                : '（相同）'}',
            style: theme.textTheme.bodySmall,
          ),
          RadioGroup<ConflictResolution>(
            groupValue: _choices[c.docId],
            onChanged: (v) => setState(() => _choices[c.docId] = v!),
            child: Wrap(
              spacing: 4,
              children: [
                for (final r in ConflictResolution.values)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Radio<ConflictResolution>(value: r),
                      Text(_label(r), style: theme.textTheme.bodySmall),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _label(ConflictResolution r) {
    switch (r) {
      case ConflictResolution.keepLocal:
        return '保留本地';
      case ConflictResolution.keepRemote:
        return '保留云端';
      case ConflictResolution.keepBoth:
        return '两者皆留';
    }
  }

  static String _fmt(int epochMs) {
    final dt = DateTime.fromMillisecondsSinceEpoch(epochMs);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }
}
