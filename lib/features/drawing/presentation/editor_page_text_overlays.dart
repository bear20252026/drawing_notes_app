part of 'editor_page.dart';

/// 编辑器文字叠层、就地编辑与斜杠命令展示域。
///
/// 此 extension 只组合文字相关 Widget，并将所有状态修改继续委托给
/// _EditorPageState 的既有方法，避免产生新的文档或工具状态源。
extension _EditorPageTextOverlays on _EditorPageState {
  Widget _buildInlineEditor(PageTextItem item) {
    final viewPos = _controller.canvasToView(item.position);
    return Positioned(
      left: viewPos.dx,
      top: viewPos.dy,
      child: Stack(
        children: [
          SizedBox(
            width: 320, // 固定编辑宽度，避免布局跳动
            child: TextField(
              controller: _editController,
              focusNode: _editFocus,
              autofocus: true,
              textInputAction: TextInputAction.done,
              maxLines: null,
              minLines: 1,
              style: TextStyle(
                fontSize: item.fontSize * _controller.viewScale,
                color: Color(item.color),
              ),
              decoration: InputDecoration(
                isCollapsed: false,
                // 可见文本框（对齐 Excalidraw 打字体验）：
                // 空文本时也显示明显边框+背景，用户能清楚看到输入位置。
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.92),
                border: const OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF42A5F5), width: 1.5),
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: const Color(0xFF42A5F5).withValues(alpha: 0.7),
                    width: 1.5,
                  ),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF42A5F5), width: 2),
                ),
                hintText: '输入文字…（回车结束）',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
              ),
              onChanged: (_) {
                // D5 斜杠命令：输入 / 展开快捷菜单，继续输入则收起。
                final text = _editController.text;
                final showSlash =
                    text == '/' ||
                    (text.endsWith('/') &&
                        !text.substring(0, text.length - 1).contains('/'));
                if (showSlash != _slashOpen) {
                  _applyState(() => _slashOpen = showSlash);
                }
              },
              onSubmitted: (_) {
                _commitTextEditing();
              },
              onTapOutside: (_) {
                _commitTextEditing();
              },
            ),
          ),
          // 斜杠命令菜单（D5，借鉴 Lokus）：输入 / 时弹出
          if (_slashOpen)
            Positioned(
              top: 26,
              left: 0,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(AppleRadius.xs),
                color: Theme.of(context).colorScheme.surface,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _slashCommand(
                      label: '加粗',
                      onTap: () => _applySlashCommand((it) => it.bold = true),
                    ),
                    _slashCommand(
                      label: '斜体',
                      onTap: () => _applySlashCommand((it) => it.italic = true),
                    ),
                    _slashCommand(
                      label: '待办',
                      onTap: () => _applySlashCommand((it) => it.isTodo = true),
                    ),
                    _slashCommand(
                      label: '居中',
                      onTap: () => _applySlashCommand(
                        (it) => it.align = TextAlignType.center,
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

  Widget _slashCommand({required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
      ),
    );
  }

  /// 应用斜杠命令：给当前文字块设置样式，并清除 '/' 与菜单。
  void _applySlashCommand(void Function(PageTextItem) apply) {
    final item = _pendingTextItem;
    if (item != null) {
      apply(item);
    }
    // 移除末尾的 '/'。
    final t = _editController.text;
    if (t.endsWith('/')) {
      _editController.text = t.substring(0, t.length - 1);
    }
    _applyState(() => _slashOpen = false);
    _notifyChanged();
  }

  /// 文字块叠加层（可拖动、点击选中、双击编辑）。
  /// [item.isSticky] 为 true 时以便利贴（标签）样式渲染：色块背景 + 圆角。
  Widget _buildTextOverlay(PageTextItem item) {
    final viewPos = _controller.canvasToView(item.position);
    final selected =
        _selectedItemId == item.id || _multiSelectedIds.contains(item.id);
    // 连线模式下的起点高亮（橙色）：让用户看到已选中的端点。
    final linkSource = _linkMode && _linkSourceId == item.id;
    // 放置过渡动画：新元素淡入（借鉴 Excalidraw 克制的微交互）。
    // 删除淡出：删除中的元素透明度渐变为 0（_deletingIds 标记）。
    // 注意：Positioned 必须是最外层（直接位于 Stack 下）——渐显动画
    // 只能包内容体。此前动画包在 Positioned 外面，提交文字的一瞬间
    // 触发 ParentDataWidget 崩溃，整页渲染冻结（真机「画板打字即冻结」
    // 的根因之二）。
    return Positioned(
      left: viewPos.dx,
      top: viewPos.dy,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        builder: (context, opacity, child) =>
            Opacity(opacity: opacity, child: child),
        child: AnimatedOpacity(
          opacity: _deletingIds.contains(item.id) ? 0 : 1,
          duration: const Duration(milliseconds: 180),
          child: _buildTextOverlayInner(item, selected, linkSource),
        ),
      ),
    );
  }

  Widget _buildTextOverlayInner(
    PageTextItem item,
    bool selected,
    bool linkSource,
  ) {
    final textLayout = EditorTextPresentationStyle.layout(
      width: item.width,
      viewScale: _controller.viewScale,
    );
    return GestureDetector(
      onTap: () => _onItemTap(item.id),
      onDoubleTap: _editTextItem,
      onSecondaryTapDown: (d) =>
          _showItemContextMenu(item.id, globalAnchor: d.globalPosition),
      // 触屏长按 = 右键等价入口（审计二-10）。
      onLongPressStart: (d) =>
          _showItemContextMenu(item.id, globalAnchor: d.globalPosition),
      onPanUpdate: (d) => _dragItem(item.id, d.delta),
      onPanEnd: (_) => _notifyChanged(),
      child: Stack(
        children: [
          Container(
            constraints: item.isSticky
                ? const BoxConstraints(minWidth: 120, minHeight: 40)
                : null,
            padding: item.isSticky
                ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6)
                : EdgeInsets.zero,
            decoration: item.isSticky
                ? BoxDecoration(
                    color: Color(item.color),
                    borderRadius: BorderRadius.circular(AppleRadius.xs),
                    border: selected || linkSource
                        ? Border.all(
                            color: linkSource
                                ? const Color(0xFFFF9800)
                                : const Color(0xFF42A5F5),
                            width: 1.5,
                          )
                        : null,
                  )
                : (selected || linkSource
                      ? BoxDecoration(
                          border: Border.all(
                            color: linkSource
                                ? const Color(0xFFFF9800)
                                : const Color(0xFF42A5F5),
                            width: 1.5,
                          ),
                        )
                      : null),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 待办 checkbox（借鉴 QOwnNotes：点击切换勾选状态）
                if (item.isTodo)
                  InkWell(
                    onTap: () {
                      _applyState(() => item.todoChecked = !item.todoChecked);
                      _notifyChanged();
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(
                        item.todoChecked
                            ? Icons.check_box
                            : Icons.check_box_outline_blank,
                        size: item.fontSize * _controller.viewScale * 0.9,
                        color: Color(item.color),
                      ),
                    ),
                  ),
                // 多行文本（对齐 Excalidraw 文本框）：width 非 null 时
                // 约束宽度 + softWrap 自动换行，可拖拽右侧手柄调整。
                Flexible(
                  child: ConstrainedBox(
                    constraints: textLayout.constraints,
                    // 富文本片段渲染（落地 Quill Delta runs，独立实现）：
                    // 有 runs 时按片段应用各自样式（加粗/斜体/下划线/颜色），
                    // 无 runs（旧文档）回退整块样式。
                    child: item.runs != null
                        ? Text.rich(
                            TextSpan(
                              style: EditorTextPresentationStyle.richBaseStyle(
                                fontSize: item.fontSize,
                                viewScale: _controller.viewScale,
                                fontFamily: item.fontFamily,
                              ),
                              children: [
                                for (final run in item.runs!)
                                  TextSpan(
                                    text: run.text,
                                    style:
                                        EditorTextPresentationStyle.richRunStyle(
                                          fallbackColor: item.color,
                                          color: run.color,
                                          bold: run.bold,
                                          italic: run.italic,
                                          underline: run.underline,
                                          strikethrough: run.strikethrough,
                                        ),
                                  ),
                              ],
                            ),
                            softWrap: textLayout.softWrap,
                            textAlign: EditorTextPresentationStyle.textAlignFor(
                              item.align.name,
                            ),
                          )
                        : Text(
                            item.text,
                            softWrap: textLayout.softWrap,
                            textAlign: EditorTextPresentationStyle.textAlignFor(
                              item.align.name,
                            ),
                            style: EditorTextPresentationStyle.plainTextStyle((
                              fontSize: item.fontSize,
                              viewScale: _controller.viewScale,
                              color: item.color,
                              fontFamily: item.fontFamily,
                              isTodo: item.isTodo,
                              todoChecked: item.todoChecked,
                              isSticky: item.isSticky,
                              bold: item.bold,
                              italic: item.italic,
                              underline: item.underline,
                              strikethrough: item.strikethrough,
                            )),
                          ),
                  ),
                ),
              ],
            ),
          ),
          // 宽度拖拽手柄（落地 Excalidraw resizeElements 的文字缩放
          // 重排版）：选中且有宽度时，右下角手柄拖拽同步调整宽度与字号
          // （字号随宽度比例缩放，保持文字整体版式不变形）。
          if (selected && item.width != null)
            Positioned(
              right: -4,
              bottom: -4,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) {
                  _textResizeAnchor = (
                    width: item.width!,
                    fontSize: item.fontSize,
                    x: _controller.canvasToView(item.position).dx,
                  );
                },
                onPanUpdate: (d) {
                  final anchor = _textResizeAnchor;
                  if (anchor == null) return;
                  final delta = screenDeltaToCanvas(
                    d.delta,
                    _controller.viewRotation,
                    _controller.viewScale,
                  );
                  _applyState(() {
                    final newWidth = (anchor.width + delta.dx)
                        .clamp(40, 2000)
                        .toDouble();
                    // 字号随宽度等比缩放（Excalidraw measureFontSizeFromWidth
                    // 思路），最小 8pt 保证可读性。
                    item.fontSize = (anchor.fontSize * newWidth / anchor.width)
                        .clamp(8.0, 120.0)
                        .toDouble();
                    item.width = newWidth;
                  });
                  _notifyChanged();
                },
                onPanEnd: (_) => _textResizeAnchor = null,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: const Color(0xFF42A5F5),
                    borderRadius: BorderRadius.circular(AppleRadius.xs),
                    border: Border.all(color: Colors.white, width: 1),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 图片块叠加层（可拖动、点击选中）。
}
