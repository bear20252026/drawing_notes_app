/// 数据库块单元格编辑器（P3-2 拆分）。
///
/// 纯展示型工具：弹文本编辑框 / 弹「选项」底部选择，把结果通过回调解耦出去。
/// 调用方（数据库块协调者）拿到值后再做领域写入，本文件不碰持久化。
library;

import 'package:flutter/material.dart';
import '../../../../core/theme/apple_design.dart';
import 'package:drawing_notes_app/shared/widgets/glass_dialog.dart';

/// 弹出单元格文本编辑框（文本/数字/日期共用）。
/// [numeric] 为 true 时用数字键盘并尝试转成 num。
Future<void> showTextCellEditor(
  BuildContext context, {
  required String fieldName,
  required String initial,
  required bool numeric,
  required ValueChanged<Object?> onSave,
}) async {
  final controller = TextEditingController(text: initial);
  final result = await GlassDialog.show<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('编辑$fieldName'),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(decimal: true)
            : null,
        decoration: const InputDecoration(hintText: '输入值'),
      ),
      actions: AppleDialog.actions([
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text),
          child: const Text('确定'),
        ),
      ]),
    ),
  );
  if (result == null) return;

  final raw = result.trim();
  Object? value;
  if (raw.isEmpty) {
    value = null;
  } else if (raw case final s when numeric) {
    value = num.tryParse(s) ?? s;
  } else {
    value = raw;
  }
  onSave(value);
}

/// 弹出「选项」底部选择器。
/// [options] 为候选项（不含「未选择」）；选择「未选择」时回传 null 表示清空。
Future<void> showSelectPicker(
  BuildContext context, {
  required List<String> options,
  required ValueChanged<String?> onPick,
}) async {
  final picked = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final o in options)
            ListTile(title: Text(o), onTap: () => Navigator.pop(ctx, o)),
          ListTile(
            title: const Text('未选择'),
            onTap: () => Navigator.pop(ctx, ''),
          ),
        ],
      ),
    ),
  );
  if (picked == null) return;
  onPick(picked == '' ? null : picked);
}

/// 记录数量胶囊（表/看板/列表共用）。
class DatabaseCountPill extends StatelessWidget {
  const DatabaseCountPill({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(AppleRadius.md),
      ),
      child: Text(
        '$count 条记录',
        style: TextStyle(fontSize: 12, color: scheme.primary),
      ),
    );
  }
}
