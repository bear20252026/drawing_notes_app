// M9-3 全部文档工作台：单行文档条目（AllDocRow）。
//
// 纯展示：数据全部注入，不 import 存储/服务。

import 'package:flutter/material.dart';
import 'package:drawing_notes_app/core/theme/apple_design.dart';
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

  /// 标题文字的起始缩进 = 16（行内边距）+ 36（kind 图标）+ 12（间距）。
  ///
  /// 列表分隔线从这里起线，而不是从屏幕边缘拉通（shadcn 的信息层级做法）。
  /// 定义为常量是为了让「分隔线对齐文字」这件事只有一个事实来源——
  /// 行内布局改了，改这里一处即可。
  static const double textIndent = 64;

  final AllDoc doc;
  final VoidCallback onOpenDoc;
  final VoidCallback? onToggleFavorite;
  final VoidCallback? onMenu;

  /// 按 kind 返回图标与主题色。
  KindVisual visualFor(AllDocKind kind) => visualForKind(kind);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final onSurface = scheme.onSurface;
    // 信息层级三级（shadcn 的信息层级做法 + DESIGN.md 排版梯子）：
    //   标题（强）→ 描述（中）→ 元信息（弱）
    // 用**语义色 + 字重**分级，而不是一味压低透明度——原先元信息用
    // 0.35 的 onSurface，浅色模式下对比度仅约 2.3:1，远低于 WCAG 对
    // 文本 4.5:1 的要求（元信息也是信息，不能淡到看不清）。
    //  - 描述：主题的 onSurfaceVariant（语义化，深浅模式自动适配）；
    //  - 元信息：55% onSurface（对比度约 4.6:1，刚好过线）。
    final muted = scheme.onSurfaceVariant;
    final subtle = onSurface.withValues(alpha: 0.55);
    final visual = visualFor(doc.kind);
    // M11.2：显示明确日期（今天带时分，昨天/今年带月日，跨年带年份）
    // ——承接原日历「文档动态」时间线的"哪天动了哪个文档"语义。
    final timeLabel = _dateLabel(doc.updatedAt, DateTime.now());

    // U4a：右键 / 长按 → 上下文菜单（聚合既有功能入口：打开 + 收藏切换）。
    void showMenuAt(Offset globalPosition) {
      showAllDocContextMenu(
        context,
        position: globalPosition,
        doc: doc,
        onOpenDoc: onOpenDoc,
        onToggleFavorite: onToggleFavorite,
      );
    }

    // InkWell 不带 onLongPressStart（需位置），长按经 GestureDetector 承接。
    return GestureDetector(
      onLongPressStart: (details) => showMenuAt(details.globalPosition),
      child: InkWell(
        onTap: onOpenDoc,
        onSecondaryTapUp: (details) => showMenuAt(details.globalPosition),
        child: Padding(
          // 纵向 10 → 12：DESIGN.md:376「structural layout snaps to
          // 8/12/16/20/24」，10 不在栅格上；12 也让 15px 标题 + 13px
          // 描述的两行结构呼吸更均匀。
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // kind 图标
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: visual.color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppleRadius.sm),
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
                        // 14 → 15：列表标题是触屏主用设备上的主要点击目标，
                        // 14px 偏小；15px 仍在 UI 尺度内（DESIGN.md 的
                        // 17px 是**营销正文**档，不适用于列表条目）。
                        fontSize: 15,
                        // w500 → w600：DESIGN.md:504 明文
                        // 「Don't set body copy at weight 500 — Apple's
                        // ladder is 300 / 400 / 600 / 700, with 500
                        // deliberately absent」。
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.1,
                        color: onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (doc.description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        doc.description,
                        style: TextStyle(
                          fontSize: 13,
                          // DESIGN.md:506「Don't tighten line-height below
                          // 1.47 for body copy」。描述最多两行，行高拉开后
                          // 整行更透气，也和正文阅读节奏一致。
                          height: AppleType.bodyLineHeight,
                          color: muted,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // N2：文件密码锁标（本会话未解锁）
              if (doc.locked) ...[
                Icon(Icons.lock_outline_rounded, size: 14, color: subtle),
                const SizedBox(width: 6),
              ],
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
              // 星标（U4a：触控目标 26→44px；R6：读屏语义——状态化标签）。
              Semantics(
                label: doc.isFavorite ? '取消收藏' : '添加收藏',
                button: true,
                child: InkWell(
                  onTap: onToggleFavorite,
                  borderRadius: BorderRadius.circular(AppleRadius.md),
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                      child: Icon(
                        doc.isFavorite
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        size: 18,
                        color: doc.isFavorite ? AppleColor.favourite : subtle,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 2),
              // ⋮ 菜单（U4a：触控目标 26→44px；死入口接活——onMenu 未传时
              // 打开与右键一致的上下文菜单。R6：读屏语义）。
              Semantics(
                label: '更多操作',
                button: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (details) {
                    if (onMenu != null) {
                      onMenu!();
                    } else {
                      showMenuAt(details.globalPosition);
                    }
                  },
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                      child: Icon(
                        Icons.more_horiz_rounded,
                        size: 18,
                        color: subtle,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
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
KindVisual visualForKind(AllDocKind kind) {
  switch (kind) {
    case AllDocKind.canvas:
      return KindVisual(Icons.crop_portrait_rounded, AppleColor.actionBlue);
    case AllDocKind.note:
      return KindVisual(Icons.sticky_note_2_rounded, AppleColor.noteGreen);
    case AllDocKind.blockdoc:
      return KindVisual(Icons.dashboard_rounded, AppleColor.blockPurple);
  }
}

/// U4a：文档行上下文菜单（桌面右键 / 触屏长按 / ⋮ 按钮共用）。
///
/// 只聚合**既有**功能入口（打开、收藏切换）——不新增业务动作；
/// 菜单在触发点（[position]）弹出。
Future<void> showAllDocContextMenu(
  BuildContext context, {
  required Offset position,
  required AllDoc doc,
  required VoidCallback onOpenDoc,
  VoidCallback? onToggleFavorite,
}) async {
  final action = await showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(
      position.dx,
      position.dy,
      position.dx + 1,
      position.dy + 1,
    ),
    items: [
      const PopupMenuItem(
        value: 'open',
        child: Row(
          children: [
            Icon(Icons.open_in_new_rounded, size: 18),
            SizedBox(width: 10),
            Text('打开'),
          ],
        ),
      ),
      if (onToggleFavorite != null)
        PopupMenuItem(
          value: 'favorite',
          child: Row(
            children: [
              Icon(
                doc.isFavorite ? Icons.star_border_rounded : Icons.star_rounded,
                size: 18,
              ),
              const SizedBox(width: 10),
              Text(doc.isFavorite ? '取消收藏' : '添加收藏'),
            ],
          ),
        ),
    ],
  );
  if (!context.mounted || action == null) return;
  if (action == 'open') {
    onOpenDoc();
  } else if (action == 'favorite') {
    onToggleFavorite?.call();
  }
}
