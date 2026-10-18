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
                  child: AppleFocusRing(borderRadius: AppleRadius.md, child: InkWell(
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
                            _blockTypeTooltip(option.type) ?? option.tooltip,
                            style: AppleType.captionStyle(
                              Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  /// 构建富文本工具栏按钮（粗体/斜体/下划线/链接）。
  ///
  /// FDC-03（业主 2026-10-17 选「标灰 + 说明」）：这四个入口写的样式今天**没有任何读者**
  /// （判据与原因都在 `doc_editor_style_entry.dart` / `inlineStylesAreRendered`），
  /// 所以禁用并在 tooltip 里说明，而不是让用户按了没反应。接上渲染后自动恢复。
  List<Widget> _buildRichTextButtons() {
    final enabled = styleEntryEnabled(hasTarget: _focusedBlockId != null);
    VoidCallback? guard(void Function() action) => enabled ? action : null;
    return [
      _toolbarIconButton(
        icon: Icons.format_bold,
        tooltip: styleEntryTooltip(context, AppLocalizations.of(context)?.mtBold ?? '粗体'),
        onPressed: guard(_toggleBold),
      ),
      _toolbarIconButton(
        icon: Icons.format_italic,
        tooltip: styleEntryTooltip(context, AppLocalizations.of(context)?.mtItalic ?? '斜体'),
        onPressed: guard(_toggleItalic),
      ),
      _toolbarIconButton(
        icon: Icons.format_underline,
        tooltip: styleEntryTooltip(
          context,
          AppLocalizations.of(context)?.mtUnderline ?? '下划线',
        ),
        onPressed: guard(_toggleUnderline),
      ),
      _toolbarIconButton(
        icon: Icons.link,
        tooltip: styleEntryTooltip(context, AppLocalizations.of(context)?.mtLink ?? '链接'),
        onPressed: guard(_insertLink),
      ),
    ];
  }

  /// 工具栏图标按钮的通用构造。
  Widget _toolbarIconButton({
    required IconData icon,
    required String tooltip,
    VoidCallback? onPressed,
  }) {
    // 审计 2026-09-26 #13：InkWell 不自带 button 标志，图标钮补
    // button 角色（label 复用 Tooltip 的 message，读屏不重复朗读）。
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppleSpacing.xxs),
      child: Semantics(
        button: true,
        child: Tooltip(
          message: tooltip,
          // V-12（审计 2026-09-27）：裸 Semantics+Tooltip+InkWell 图标钮的
          // 键盘焦点此前只有 Material 的 focusColor overlay（深色底几乎看不
          // 出），补 2px Focus Blue 描边。环外扩绘制不占布局，且
          // AppleFocusRing 的 Focus 节点 canRequestFocus:false 只观察不抢
          // 焦点，因此不多出 Tab 停靠。半径对齐 InkWell 自身的 sm。
          child: AppleFocusRing(
            borderRadius: AppleRadius.sm,
            enabled: onPressed != null,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppleRadius.sm),
              onTap: onPressed,
              child: Padding(
                // #34 间距归一：14→12（20px 图标 + 24 = 44px 触控目标，仍达标）。
                padding: const EdgeInsets.all(12),
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
