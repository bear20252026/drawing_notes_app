// M12 笔记页大纲面板（AFFiNE Outline）。
// 展示标题块层级列表；点击滚动到对应块。参照 AFFiNE（MIT）交互。
//
// ### 两种形态（AFFiNE 式设备级分流）
// - 桌面（≥ [kDesktopBreakpoint]）：[DocOutlineRail] 右缘停靠窄栏（240）
// - 移动（< [kDesktopBreakpoint]）：[showDocOutlineSheet] 底部半屏面板
//
// 两种形态共享同一个 [DocOutlinePanel] 内容体——视图分家、业务不重复
// （即 AFFiNE 的 desktop/ 与 mobile/ 两棵视图树共享同一批 services 的思路）。
// 若沿用统一的停靠窄栏，手机上 240 会吃掉约 60% 屏宽，编辑器只剩 160。
import 'package:flutter/material.dart';

/// 大纲条目（由宿主从编辑器抽取）。
class OutlineEntry {
  const OutlineEntry({
    required this.id,
    required this.level,
    required this.text,
  });

  final String id;
  final int level;
  final String text;
}

/// 桌面右缘停靠大纲面板：窄栏 + 层级缩进 + 点击跳转。
class DocOutlineRail extends StatelessWidget {
  const DocOutlineRail({
    super.key,
    required this.entries,
    required this.onTapEntry,
    required this.onClose,
  });

  final List<OutlineEntry> entries;
  final void Function(String blockId) onTapEntry;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          left: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: DocOutlinePanel(
        entries: entries,
        onTapEntry: onTapEntry,
        onClose: onClose,
      ),
    );
  }
}

/// 大纲内容体：标题栏 + 层级条目列表，不含宽度与边框。
///
/// 桌面停靠栏与移动底部面板共用，避免两份列表实现漂移。
class DocOutlinePanel extends StatelessWidget {
  const DocOutlinePanel({
    super.key,
    required this.entries,
    required this.onTapEntry,
    this.onClose,
    this.showCloseButton = true,
  });

  final List<OutlineEntry> entries;
  final void Function(String blockId) onTapEntry;
  final VoidCallback? onClose;

  /// 底部面板自带拖拽把手与下滑关闭，无需关闭按钮。
  final bool showCloseButton;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '大纲',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (showCloseButton && onClose != null)
                  IconButton(
                    tooltip: '关闭',
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: onClose,
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: entries.isEmpty
                ? Center(
                    child: Text(
                      '暂无标题块\n用 / 菜单插入「标题」',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: entries.length,
                    itemBuilder: (context, i) {
                      final e = entries[i];
                      return InkWell(
                        onTap: () => onTapEntry(e.id),
                        child: Padding(
                          padding: EdgeInsets.only(
                            left: 16 + (e.level - 1) * 14.0,
                            right: 12,
                            top: 7,
                            bottom: 7,
                          ),
                          child: Text(
                            e.text.isEmpty ? '（空标题）' : e.text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  fontWeight: e.level <= 2
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: e.level <= 2
                                      ? scheme.onSurface
                                      : scheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// 移动端大纲入口：底部半屏面板（AFFiNE mobile 的 sheet 语义）。
///
/// 占满屏宽、高度 60%；点击条目后先关闭面板再跳转，避免面板遮挡目标块。
Future<void> showDocOutlineSheet({
  required BuildContext context,
  required List<OutlineEntry> entries,
  required void Function(String blockId) onTapEntry,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => SizedBox(
      height: MediaQuery.sizeOf(ctx).height * 0.6,
      child: DocOutlinePanel(
        entries: entries,
        showCloseButton: false,
        onTapEntry: (id) {
          Navigator.of(ctx).pop();
          onTapEntry(id);
        },
      ),
    ),
  );
}
