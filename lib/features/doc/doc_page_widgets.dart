// doc_page.dart 的 part：顶栏 _DocHeader 与反链面板 _BacklinksPanel。
// 与主文件同 library，共享 import 与私有成员。
part of 'doc_page.dart';

/// 顶栏：返回 + 标题 + ☆收藏 + ⓘ信息 + ⋯更多 + 大纲开关 + 分享。
class _DocHeader extends StatelessWidget implements PreferredSizeWidget {
  const _DocHeader({
    required this.title,
    required this.isFavorite,
    required this.outlineOpen,
    required this.onToggleFavorite,
    required this.onToggleOutline,
    required this.onShowInfo,
    required this.statusLabel,
    required this.statusColor,
    required this.onSavePressed,
    this.onOpenInEdgeless,
    this.onExportMarkdown,
    this.onExportHtml,
    this.onInsertPageLink,
    this.onExportPdf,
    this.onManagePassword,
  });

  final String title;
  final bool isFavorite;
  final bool outlineOpen;
  final VoidCallback onToggleFavorite;
  final VoidCallback onToggleOutline;
  final VoidCallback onShowInfo;

  /// 保存状态文案（未保存 / 保存中… / 已保存 HH:mm）与主题色。
  final String statusLabel;
  final Color statusColor;
  final VoidCallback onSavePressed;
  final VoidCallback? onOpenInEdgeless;

  /// 导出 Markdown（M12.5）。
  final VoidCallback? onExportMarkdown;

  /// 导出 HTML（M12.6）。
  final VoidCallback? onExportHtml;

  /// 插入页面链接（M12.7 反向链接）。
  final VoidCallback? onInsertPageLink;

  /// 导出 PDF（M12.8）。
  final VoidCallback? onExportPdf;

  /// 文件密码管理（N2；null 时不显示菜单项——如未注入 blockDocStore）。
  final VoidCallback? onManagePassword;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isNarrow = !isDesktopLayout(context);
    return AppBar(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      // 移动端（<900）：顶栏一行装不下 5 个图标 + 状态文字 + 分享按钮
      // （400dp 实测溢出 24px）。AFFiNE mobile 的做法是"功能不消失、只换位置"：
      // 状态文字降为标题副标题，次要动作收进 ⋯ 菜单，分享由带文字按钮改为图标。
      title: isNarrow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title.isEmpty ? '未命名' : title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ],
            )
          : Text(
              title.isEmpty ? '未命名' : title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
      actions: [
        // 保存状态（透明可见）：未保存 / 保存中… / 已保存 HH:mm
        // 移动端已降为标题副标题，此处仅桌面显示。
        if (!isNarrow)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Center(
              child: Text(
                statusLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: statusColor,
                ),
              ),
            ),
          ),
        if (!isNarrow)
          IconButton(
            tooltip: '插入页面链接',
            icon: const Icon(Icons.insert_link_rounded),
            onPressed: onInsertPageLink,
          ),
        IconButton(
          tooltip: '保存',
          icon: const Icon(Icons.save_outlined),
          onPressed: onSavePressed,
        ),
        IconButton(
          tooltip: isFavorite ? '取消收藏' : '收藏',
          icon: Icon(
            isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
            color: isFavorite ? const Color(0xFFF5A623) : null,
          ),
          onPressed: onToggleFavorite,
        ),
        if (!isNarrow)
          IconButton(
            tooltip: '文档信息',
            icon: const Icon(Icons.info_outline_rounded, size: 20),
            onPressed: onShowInfo,
          ),
        PopupMenuButton<String>(
          tooltip: '更多',
          icon: const Icon(Icons.more_horiz_rounded),
          onSelected: (v) {
            // 移动端把顶栏装不下的动作收进此处（功能不消失，只换位置）。
            if (v == 'info') onShowInfo();
            if (v == 'link') onInsertPageLink?.call();
            if (v == 'share') _showShareSnackBar(context);
            if (v == 'edgeless') onOpenInEdgeless?.call();
            if (v == 'exportMd') onExportMarkdown?.call();
            if (v == 'exportHtml') onExportHtml?.call();
            if (v == 'exportPdf') onExportPdf?.call();
            if (v == 'password') onManagePassword?.call();
          },
          itemBuilder: (context) => [
            if (isNarrow)
              PopupMenuItem(
                value: 'info',
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    const Text('文档信息'),
                  ],
                ),
              ),
            if (isNarrow)
              PopupMenuItem(
                value: 'link',
                child: Row(
                  children: [
                    Icon(
                      Icons.insert_link_rounded,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    const Text('插入页面链接'),
                  ],
                ),
              ),
            PopupMenuItem(
              value: 'exportPdf',
              child: Row(
                children: [
                  Icon(
                    Icons.picture_as_pdf_rounded,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  const Text('导出 PDF'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'exportHtml',
              child: Row(
                children: [
                  Icon(
                    Icons.code_rounded,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  const Text('导出 HTML'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'exportMd',
              child: Row(
                children: [
                  Icon(
                    Icons.data_object_rounded,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  const Text('导出 Markdown'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'edgeless',
              enabled: onOpenInEdgeless != null,
              child: Row(
                children: [
                  Icon(
                    Icons.draw_outlined,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  const Text('在画布中打开'),
                ],
              ),
            ),
            // N2：文件密码管理（独立密码与画布/分页画布同口径）。
            if (onManagePassword != null)
              PopupMenuItem(
                value: 'password',
                child: Row(
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    const Text('文件密码'),
                  ],
                ),
              ),
          ],
        ),
        if (!isNarrow)
          Padding(
            padding: const EdgeInsets.only(right: 12, left: 4),
            child: FilledButton.icon(
              onPressed: () => _showShareSnackBar(context),
              icon: const Icon(Icons.ios_share_rounded, size: 15),
              label: const Text('分享'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0066CC),
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 34),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        // 移动端：带文字的分享按钮放不下，收为图标按钮。
        if (isNarrow)
          IconButton(
            tooltip: '分享',
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: () => _showShareSnackBar(context),
          ),
        IconButton(
          tooltip: '大纲',
          icon: Icon(
            Icons.format_list_bulleted_rounded,
            color: outlineOpen ? scheme.primary : null,
          ),
          onPressed: onToggleOutline,
        ),
      ],
    );
  }
}

/// 反向链接面板（M12.7，AFFiNE Backlinks 对齐）：
/// 列出引用了当前文档的笔记（[[标题]] 双链），点击跳转。
class _BacklinksPanel extends StatefulWidget {
  const _BacklinksPanel({
    required this.currentDoc,
    required this.docsFuture,
    this.onOpenDocById,
  });

  final NoteBlockDoc currentDoc;
  final Future<List<NoteBlockDoc>> docsFuture;
  final void Function(String docId)? onOpenDocById;

  @override
  State<_BacklinksPanel> createState() => _BacklinksPanelState();
}

class _BacklinksPanelState extends State<_BacklinksPanel> {
  List<NoteBlockDoc>? _backlinks;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(_BacklinksPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当前文档变化（保存回写）时重算索引。
    if (oldWidget.currentDoc.updatedAt != widget.currentDoc.updatedAt ||
        oldWidget.currentDoc.id != widget.currentDoc.id) {
      _reload();
    }
  }

  Future<void> _reload() async {
    final all = await widget.docsFuture;
    if (!mounted) return;
    setState(() => _backlinks = backlinksOf(widget.currentDoc, all));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final backlinks = _backlinks;
    if (backlinks == null || backlinks.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppleRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.link_rounded,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                '反向链接 · ${backlinks.length}',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final doc in backlinks)
            InkWell(
              onTap: () => widget.onOpenDocById?.call(doc.id),
              borderRadius: BorderRadius.circular(AppleRadius.xs),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.edit_note_rounded,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        doc.title.isEmpty ? '未命名' : doc.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: scheme.onSurface),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
