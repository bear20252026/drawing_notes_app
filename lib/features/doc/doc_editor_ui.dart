part of 'doc_editor.dart';

// 大纲/对话框域（O1 拆分自 doc_editor.dart）：标题输入框、大纲抽屉、
// 退出确认。public outline/scrollToBlock 留在本体。行为零变化。

/// 大纲/对话框域私有助手（拆分自 doc_editor.dart）。
extension _DocEditorUi on DocEditorState {
  /// AFFiNE 式正文大标题。
  Widget _buildTitleField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: TextField(
        controller: _titleController,
        decoration: InputDecoration(
          hintText: AppLocalizations.of(context)?.docUntitled ?? '未命名',
          border: InputBorder.none,
        ),
        style: AppleType.titleStyle(
          Theme.of(context).colorScheme.onSurface,
        ).copyWith(fontSize: 26, fontWeight: AppleType.bold),
        maxLines: null,
      ),
    );
  }

  bool _containsId(NoteBlock node, String id) {
    if (node.id == id) return true;
    for (final c in node.children) {
      if (_containsId(c, id)) return true;
    }
    return false;
  }

  /// 大纲停靠面板。
  Widget _buildOutlineDrawer() {
    final entries = outline();
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('outline-on'),
      width: 264,
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
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context)?.outlineTitle ?? '大纲',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: AppleType.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip:
                        AppLocalizations.of(context)?.docToolbarRefresh ?? '刷新',
                    icon: const Icon(Icons.refresh, size: 20),
                    onPressed: () => editorSetState(() {}),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: entries.isEmpty
                  ? Center(
                      child: Text(
                        AppLocalizations.of(context)?.docOutlineEmpty ??
                            '暂无标题块，用 / 菜单插入「标题」后出现在这里',
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
                          onTap: () {
                            scrollToBlock(e.id);
                            Navigator.of(context).pop();
                          },
                          child: Padding(
                            padding: EdgeInsets.only(
                              left: 16 + (e.level - 1) * 16.0,
                              right: 16,
                              top: 8,
                              bottom: 8,
                            ),
                            child: Text(
                              e.text.isEmpty ? '（空标题）' : e.text,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    fontWeight: e.level <= 2
                                        ? FontWeight.w600
                                        : FontWeight.w400,
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

  /// 退出未保存提醒对话框。
  void _showExitDialog() {
    GlassDialog.show<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          AppLocalizations.of(context)?.docUnsavedChangesTitle ?? '未保存的改动',
        ),
        content: const Text('文档有未保存的改动，确定要退出吗？'),
        actions: AppleDialog.actions([
          TextButton(
            // 键盘可达 + 防误触：默认聚焦「取消」，Enter 不会直接丢数据。
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(),
            child: Text(AppLocalizations.of(context)?.cancel ?? '取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop();
            },
            child: Text(AppLocalizations.of(context)?.docDiscard ?? '放弃'),
          ),
        ]),
      ),
    );
  }
}
