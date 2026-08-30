// M9-3 全部文档工作台：单行文档条目（AllDocRow）。
//
// 纯展示：数据全部注入，不 import 存储/服务。

import 'package:flutter/material.dart';
import 'package:drawing_notes_app/features/all_docs/domain/all_doc.dart';

/// 单行文档条目。
///
/// 布局（从左到右）：
/// - kind 图标（canvas/note/blockdoc 各自 Material 图标 + 主题色）
/// - 主列：title + 可选 description（1-2 行灰色）
/// - 左侧次级信息：相对时间（如"16小时前/上周"）
/// - 右侧：D 头像圆点 + 星标（isFavorite 高亮可点）+ ⋮ 菜单
///
/// 整行可点 → [onOpenDoc]。
class AllDocRow extends StatelessWidget {
  const AllDocRow({
    super.key,
    required this.doc,
    required this.onOpenDoc,
    this.onToggleFavorite,
    this.onMenu,
  });

  final AllDoc doc;
  final VoidCallback onOpenDoc;
  final VoidCallback? onToggleFavorite;
  final VoidCallback? onMenu;

  /// 按 kind 返回图标与主题色。
  KindVisual visualFor(AllDocKind kind, ColorScheme scheme) =>
      visualForKind(kind, scheme);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final onSurface = scheme.onSurface;
    final muted = onSurface.withValues(alpha: 0.55);
    final subtle = onSurface.withValues(alpha: 0.35);
    final visual = visualFor(doc.kind, scheme);
    // M11.2：显示明确日期（今天带时分，昨天/今年带月日，跨年带年份）
    // ——承接原日历「文档动态」时间线的"哪天动了哪个文档"语义。
    final timeLabel = _dateLabel(doc.updatedAt, DateTime.now());

    return InkWell(
      onTap: onOpenDoc,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // kind 图标
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: visual.color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Icon(visual.icon, size: 20, color: visual.color),
            ),
            const SizedBox(width: 12),
            // 主列：title + description
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    doc.title.isEmpty ? '未命名' : doc.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (doc.description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      doc.description,
                      style: TextStyle(fontSize: 12, color: muted),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            // 相对时间
            Text(timeLabel, style: TextStyle(fontSize: 11.5, color: subtle)),
            const SizedBox(width: 12),
            // D 头像圆点
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: visual.color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                'D',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: visual.color,
                ),
              ),
            ),
            const SizedBox(width: 6),
            // 星标
            InkWell(
              onTap: onToggleFavorite,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  doc.isFavorite
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  size: 18,
                  color: doc.isFavorite ? const Color(0xFFFF9F0A) : subtle,
                ),
              ),
            ),
            const SizedBox(width: 2),
            // ⋮ 菜单
            InkWell(
              onTap: onMenu,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.more_horiz_rounded, size: 18, color: subtle),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class KindVisual {
  const KindVisual(this.icon, this.color);
  final IconData icon;
  final Color color;
}

/// 明确日期标签：今天 → HH:mm；昨天 → 昨天；今年 → M月d日；跨年 → yyyy/M/d。
String _dateLabel(DateTime t, DateTime now) {
  final sameDay =
      t.year == now.year && t.month == now.month && t.day == now.day;
  if (sameDay) {
    return '今天 '
        '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
  }
  final yesterday = now.subtract(const Duration(days: 1));
  final isYesterday =
      t.year == yesterday.year &&
      t.month == yesterday.month &&
      t.day == yesterday.day;
  if (isYesterday) return '昨天';
  if (t.year == now.year) {
    return '${t.month} 月 ${t.day} 日';
  }
  return '${t.year}/${t.month}/${t.day}';
}

/// 按 kind 返回图标与主题色（顶层，供行组件与侧栏文档树共用）。
KindVisual visualForKind(AllDocKind kind, ColorScheme scheme) {
  switch (kind) {
    case AllDocKind.canvas:
      return KindVisual(Icons.crop_portrait_rounded, const Color(0xFF0066CC));
    case AllDocKind.note:
      return KindVisual(Icons.sticky_note_2_rounded, const Color(0xFF30D158));
    case AllDocKind.blockdoc:
      return KindVisual(Icons.dashboard_rounded, const Color(0xFFBF5AF2));
  }
}
