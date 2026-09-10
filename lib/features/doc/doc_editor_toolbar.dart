// 由 Claude 团队生成 | Drawing Notes App
// doc_editor 拆分（R4b，架构审计 M1）：底部工具栏。

part of 'doc_editor.dart';

extension DocEditorToolbar on DocEditorState {
  // ── 工具栏 ─────────────────────────────────────────────────

  Widget _buildToolbar() {
    final focusedType = _focusedBlockType;
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: AppleSpacing.sm,
        horizontal: AppleSpacing.xs,
      ),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            ..._buildRichTextButtons(),
            const VerticalDivider(width: 8),
            ..._blockTypeOptions.map((option) {
              final isSelected = focusedType == option.type;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Tooltip(
                  message: _blockTypeTooltip(option.type) ?? option.tooltip,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppleRadius.md),
                    onTap: _focusedBlockId != null
                        ? () => _changeBlockType(_focusedBlockId!, option.type)
                        : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppleSpacing.sm,
                        horizontal: AppleSpacing.sm,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppleColor.actionBlue.withValues(alpha: 0.12)
                            : null,
                        borderRadius: BorderRadius.circular(AppleRadius.md),
                        border: isSelected
                            ? Border.all(color: AppleColor.actionBlue)
                            : null,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(option.icon, size: 20),
                          const SizedBox(height: AppleSpacing.xxs),
                          Text(
                            option.tooltip,
                            style: AppleType.captionStyle(
                              Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  /// 构建富文本工具栏按钮（粗体/斜体/下划线/链接）。
  List<Widget> _buildRichTextButtons() {
    final hasFocus = _focusedBlockId != null;
    return [
      _toolbarIconButton(
        icon: Icons.format_bold,
        tooltip: AppLocalizations.of(context)?.mtBold ?? '粗体',
        onPressed: hasFocus ? () => _toggleBold() : null,
      ),
      _toolbarIconButton(
        icon: Icons.format_italic,
        tooltip: AppLocalizations.of(context)?.mtItalic ?? '斜体',
        onPressed: hasFocus ? () => _toggleItalic() : null,
      ),
      _toolbarIconButton(
        icon: Icons.format_underline,
        tooltip: AppLocalizations.of(context)?.mtUnderline ?? '下划线',
        onPressed: hasFocus ? () => _toggleUnderline() : null,
      ),
      _toolbarIconButton(
        icon: Icons.link,
        tooltip: AppLocalizations.of(context)?.mtLink ?? '链接',
        onPressed: hasFocus ? () => _insertLink() : null,
      ),
    ];
  }

  /// 工具栏图标按钮的通用构造。
  Widget _toolbarIconButton({
    required IconData icon,
    required String tooltip,
    VoidCallback? onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppleSpacing.xxs),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppleRadius.sm),
          onTap: onPressed,
          child: Padding(
            // U4a：AppleSpacing.sm(12)→14——20px 图标 + 28 = 48px 触控目标。
            padding: const EdgeInsets.all(14),
            child: Icon(
              icon,
              size: 20,
              color: onPressed != null
                  ? Theme.of(context).colorScheme.onSurface
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  /// 当前聚焦块的类型（若无聚焦块则返回 null）。
  NoteBlockType? get _focusedBlockType {
    if (_focusedBlockId == null) return null;
    final block = _editor.findBlock(_root, _focusedBlockId!);
    return block?.type;
  }

  /// i18n（E1 批 4）：块类型工具条 tooltip 按 locale 解析（const 列表保持
  /// zh 数据兜底）。
  String? _blockTypeTooltip(NoteBlockType type) {
    final l10n = AppLocalizations.of(context);
    switch (type) {
      case NoteBlockType.text:
        return l10n?.tParagraph ?? '段落';
      case NoteBlockType.heading:
        return l10n?.tHeading ?? '标题';
      case NoteBlockType.todo:
        return l10n?.tTodo ?? '待办';
      case NoteBlockType.quote:
        return l10n?.tQuote ?? '引用';
      case NoteBlockType.code:
        return l10n?.tCode ?? '代码';
      case NoteBlockType.divider:
        return l10n?.tDivider ?? '分隔线';
      case NoteBlockType.image:
        return l10n?.tImage ?? '图片';
      case NoteBlockType.link:
        return l10n?.tLink ?? '链接';
      case NoteBlockType.table:
        return l10n?.tTable ?? '表格';
      case NoteBlockType.database:
        return l10n?.tDatabase ?? '数据库';
      case NoteBlockType.canvas:
        return l10n?.tEmbedCanvas ?? '内嵌画布';
      case NoteBlockType.chart:
        return l10n?.tEmbedChart ?? '内嵌图表';
      case NoteBlockType.bullet:
        return l10n?.tBulletList ?? '无序列表';
      case NoteBlockType.ordered:
        return l10n?.tOrderedList ?? '有序列表';
      case NoteBlockType.toggle:
      case NoteBlockType.callout:
      case NoteBlockType.attachment:
        return null;
    }
  }
}
