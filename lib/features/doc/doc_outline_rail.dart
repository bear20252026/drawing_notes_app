// M12 笔记页右缘大纲条（AFFiNE Outline Rail）。
// 展示标题块层级列表；点击滚动到对应块。参照 AFFiNE（MIT）交互。
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

/// 右缘停靠大纲面板：窄栏 + 层级缩进 + 点击跳转。
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
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          left: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: SafeArea(
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
      ),
    );
  }
}
