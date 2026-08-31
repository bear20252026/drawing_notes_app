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
                  message: option.tooltip,
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
        tooltip: '粗体',
        onPressed: hasFocus ? () => _toggleBold() : null,
      ),
      _toolbarIconButton(
        icon: Icons.format_italic,
        tooltip: '斜体',
        onPressed: hasFocus ? () => _toggleItalic() : null,
      ),
      _toolbarIconButton(
        icon: Icons.format_underline,
        tooltip: '下划线',
        onPressed: hasFocus ? () => _toggleUnderline() : null,
      ),
      _toolbarIconButton(
        icon: Icons.link,
        tooltip: '链接',
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
            padding: const EdgeInsets.all(AppleSpacing.sm),
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
}
