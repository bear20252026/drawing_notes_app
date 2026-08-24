// editor_v2——HistoryPanel 历史面板（AFFiNE/Excalidraw 借鉴—�?026-08-21）�?//
// AFFiNE/Excalidraw 历史记录可视化本地化——积木式独立 Widget�?// 显示撤销/重做历史列表 + 当前位置高亮 + 快速跳转�?// 不修改现有功能——保证现有功能正常——不搞崩�?library;

import 'package:flutter/material.dart';

import '../../../core/theme/text_scale_helper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:editor_core/editor_core.dart';
import '../application/editor_v2_viewmodel.dart';

/// AFFiNE/Excalidraw 历史面板（积木式独立 Widget——撤销/重做历史可视化）�?///
/// 功能�?/// - 历史记录列表（每条显示命令类�?+ 时间�?/// - 当前位置高亮（蓝色标记）
/// - 撤销/重做快速按�?/// - 历史清空按钮
///
/// 设计：积木式——独�?Widget——不耦合其他组件——可插拔�?class HistoryPanel extends ConsumerWidget {
  const HistoryPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(editorV2NotifierProvider);
    final notifier = ref.read(editorV2NotifierProvider.notifier);
    // �?DocumentReducer 获取历史栈（公开 getter）�?    final undoStack = notifier.undoStack;
    final redoStack = notifier.redoStack;
    final totalCount = undoStack.length + redoStack.length;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 标题栏（AFFiNE 风格）�?          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Text('历史记录', style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                Text('$totalCount �?,
                    style: TextStyle(fontSize: TextScaleHelper.scaled(context, 12), color: Colors.grey)),
              ],
            ),
          ),
          // 撤销/重做按钮栏�?          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.undo, size: 16),
                    label: const Text('撤销'),
                    onPressed: state.canUndo ? () => notifier.undo() : null,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.redo, size: 16),
                    label: const Text('重做'),
                    onPressed: state.canRedo ? () => notifier.redo() : null,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // 历史记录列表（限制高度——可滚动）�?          if (totalCount > 0)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: totalCount,
                itemBuilder: (context, index) {
                  // 重做栈在前（未来），撤销栈在后（过去）�?                  final isRedo = index < redoStack.length;
                  final entry = isRedo
                      ? redoStack[index]
                      : undoStack[index - redoStack.length];
                  final isCurrent = index == redoStack.length; // 当前位置�?
                  return _HistoryTile(
                    entry: entry,
                    isCurrent: isCurrent,
                    isRedo: isRedo,
                    onTap: () {
                      // 点击跳转（Excalidraw 模式——快速导航）�?                      if (isRedo) {
                        for (var i = 0; i <= index - redoStack.length; i++) {
                          notifier.redo();
                        }
                      } else {
                        for (var i = 0; i < undoStack.length - index; i++) {
                          notifier.undo();
                        }
                      }
                    },
                  );
                },
              ),
            ),
          // 空状态�?          if (totalCount == 0)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: Text('无历史记�?, style: TextStyle(color: Colors.grey, fontSize: TextScaleHelper.scaled(context, 13))),
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// 单条历史记录条目（积木式——不耦合）�?class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.entry,
    required this.isCurrent,
    required this.isRedo,
    required this.onTap,
  });

  final HistoryEntry entry;
  final bool isCurrent;
  final bool isRedo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 命令类型名称（从 runtimeType 提取简短名）�?    final commandName = entry.command.runtimeType.toString();
    final shortName = commandName
        .replaceAll('Command', '')
        .replaceAll('Add', '+')
        .replaceAll('Remove', '-')
        .replaceAll('Create', '+')
        .replaceAll('Update', '~');

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        constraints: const BoxConstraints(minHeight: 48),
        decoration: BoxDecoration(
          color: isCurrent
              ? Colors.blue.withValues(alpha: 0.1)
              : isRedo
                  ? Colors.grey.withValues(alpha: 0.05)
                  : null,
          borderRadius: BorderRadius.circular(6),
          border: isCurrent
              ? Border.all(color: Colors.blue.withValues(alpha: 0.3))
              : null,
        ),
        child: Row(
          children: [
            // 图标（当�?蓝色圆点/重做=灰色/撤销=黑色）�?            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isCurrent
                    ? Colors.blue
                    : isRedo
                        ? Colors.grey.shade400
                        : Colors.black54,
              ),
            ),
            const SizedBox(width: 8),
            // 命令名称�?            Expanded(
              child: Text(
                shortName,
                style: TextStyle(
                  fontSize: TextScaleHelper.scaled(context, 12),
                  color: isCurrent ? Colors.blue.shade700 : Colors.black87,
                  fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            // revision�?            Text(
              'v${entry.revisionBefore}',
              style: TextStyle(fontSize: TextScaleHelper.scaled(context, 10), color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }
}
