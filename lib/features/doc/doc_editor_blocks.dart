// 由 Claude 团队生成 | Drawing Notes App
// doc_editor 拆分（R4b，架构审计 M1）：块渲染区。
// extension on DocEditorState（同库 part，可访问私有成员）；
// 生命周期方法与字段仍留在 doc_editor.dart 主文件。

part of 'doc_editor.dart';

extension DocEditorBlocks on DocEditorState {
  /// 空文档提示（AFFiNE 风格：引导用户输入）。
  Widget _buildEmptyHint() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppleSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.edit_note,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppleSpacing.md),
            Text(
              '键入 / 添加块',
              style: AppleType.titleStyle(
                Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: AppleSpacing.xs),
            Text(
              '按 Enter 分块，按 Backspace 合并空块',
              style: AppleType.bodyStyle(
                Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlockList(List<NoteBlock> blocks) {
    return ListView.builder(
      controller: _listScroll,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      itemCount: blocks.length,
      itemBuilder: (context, index) {
        return _buildBlockRow(blocks[index], index);
      },
    );
  }

  Widget _buildBlockRow(NoteBlock block, int index) {
    final isFocused = _focusedBlockId == block.id;
    final isDraggingThis = _draggingBlockId == block.id;
    final showDropLine =
        _draggingBlockId != null &&
        _dropTargetIndex != null &&
        _dropTargetIndex == index;
    // LayerLink 锚点：浮动选区工具条跟随本块定位（AFFiNE 风格）。
    return CompositedTransformTarget(
      link: _layerLinks[block.id] ?? LayerLink(),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: DragTarget<String>(
          onWillAcceptWithDetails: (details) {
            // 不接受自身拖拽到自身位置。
            if (details.data == block.id) return false;
            editorSetState(() => _dropTargetIndex = index);
            return true;
          },
          onLeave: (_) {
            if (_dropTargetIndex == index) {
              editorSetState(() => _dropTargetIndex = null);
            }
          },
          onAcceptWithDetails: (details) {
            _moveBlockToPosition(details.data, index);
          },
          builder: (context, candidateData, rejectedData) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showDropLine)
                  Container(
                    height: 3,
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(AppleRadius.xs),
                    ),
                  ),
                Opacity(
                  opacity: isDraggingThis ? 0.3 : 1.0,
                  child: Semantics(
                    label: _semanticLabelForBlock(block),
                    focused: isFocused,
                    container: true,
                    child: Container(
                      decoration: isFocused
                          ? BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(AppleRadius.xs),
                            )
                          : null,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildBlockHandle(block),
                          _buildBlockPrefix(block, index),
                          Expanded(child: _buildBlockInput(block)),
                        ],
                      ),
                    ),
                  ),
                ),
                // ── 嵌套子块（缩进渲染，不可整行拖拽）────────────────
                // toggle 块折叠时不渲染子块（AFFiNE Toggle list 语义）。
                if (block.children.isNotEmpty &&
                    (block.type != NoteBlockType.toggle ||
                        (block.props['expanded'] as bool? ?? true)))
                  Padding(
                    padding: const EdgeInsets.only(left: 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < block.children.length; i++)
                          _buildNestedBlockRow(
                            block.children[i],
                            i,
                            parentId: block.id,
                          ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 构建嵌套子块行（缩进显示、无整行拖拽；仍是可编辑/可键盘操作的行）。
  Widget _buildNestedBlockRow(
    NoteBlock block,
    int index, {
    required String parentId,
  }) {
    final isFocused = _focusedBlockId == block.id;
    final isDraggingThis = _draggingBlockId == block.id;
    final showDropLine =
        _draggingBlockId != null &&
        _nestedDropParentId == parentId &&
        _nestedDropIndex == index;
    return CompositedTransformTarget(
      link: _layerLinks[block.id] ?? LayerLink(),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: DragTarget<String>(
          onWillAcceptWithDetails: (details) {
            if (details.data == block.id) return false;
            final parent = _editor.findBlock(_root, parentId);
            if (parent == null) return false;
            editorSetState(() {
              _nestedDropParentId = parentId;
              _nestedDropIndex = index;
            });
            return true;
          },
          onLeave: (_) {
            if (_nestedDropParentId == parentId && _nestedDropIndex == index) {
              editorSetState(() => _nestedDropIndex = null);
            }
          },
          onAcceptWithDetails: (details) {
            _moveBlockToParentPosition(details.data, parentId, index);
          },
          builder: (context, candidateData, rejectedData) {
            return Opacity(
              opacity: isDraggingThis ? 0.3 : 1.0,
              child: Semantics(
                label: _semanticLabelForBlock(block),
                focused: isFocused,
                container: true,
                child: Container(
                  decoration: showDropLine
                      ? BoxDecoration(
                          border: Border(
                            top: BorderSide(
                              color: Theme.of(context).colorScheme.primary,
                              width: 2,
                            ),
                          ),
                        )
                      : (isFocused
                            ? BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primaryContainer
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(AppleRadius.xs),
                              )
                            : null),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 真实拖拽把手：嵌套子块可拖拽（M11，AFFiNE 一致性）
                      _buildBlockHandle(block),
                      _buildBlockPrefix(block, index),
                      Expanded(child: _buildBlockInput(block)),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// 构建块拖拽手柄（grip）。
  Widget _buildBlockHandle(NoteBlock block) {
    return Draggable<String>(
      data: block.id,
      feedback: Material(
        color: Colors.transparent,
        child: Icon(
          Icons.drag_handle,
          size: 20,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      childWhenDragging: const SizedBox(width: 24, height: 24),
      onDragStarted: () {
        editorSetState(() {
          _draggingBlockId = block.id;
          _dropTargetIndex = null;
        });
      },
      onDragEnd: (_) {
        editorSetState(() {
          _draggingBlockId = null;
          _dropTargetIndex = null;
        });
      },
      child: GestureDetector(
        onTap: () => _selectBlock(block.id),
        child: Padding(
          padding: const EdgeInsets.only(top: 10, right: 4),
          child: Opacity(
            opacity: _focusedBlockId == block.id ? 1.0 : 0.4,
            child: Icon(
              Icons.drag_handle,
              size: 18,
              color: AppleColor.subtleOf(Theme.of(context).colorScheme),
            ),
          ),
        ),
      ),
    );
  }

  /// 将指定块移动到目标索引位置（顶层列表内）。
  /// 将块移动到 [parentId] 下的 [targetIndex] 位置（M11：支持嵌套间与跨层移动）。
  void _moveBlockToParentPosition(
    String blockId,
    String parentId,
    int targetIndex,
  ) {
    final parent = _editor.findBlock(_root, parentId);
    if (parent == null) return;
    final siblings = parent.children;
    final currentIndex = siblings.indexWhere((b) => b.id == blockId);
    var adjusted = targetIndex;
    // 同父内移动：移除源后索引前移一位。
    if (currentIndex >= 0 && targetIndex > currentIndex) {
      adjusted = targetIndex - 1;
    }
    if (adjusted < 0 || adjusted > siblings.length) return;
    final moved = _editor.moveBlock(_root, blockId, parentId, index: adjusted);
    if (moved == _root) return;
    editorSetState(() {
      _root = moved;
      _nestedDropParentId = null;
      _nestedDropIndex = null;
      _dropTargetIndex = null;
      _updateDirtyState();
    });
  }

  void _moveBlockToPosition(String blockId, int targetIndex) {
    final blocks = _root.children;
    final currentIndex = blocks.indexWhere((b) => b.id == blockId);
    var adjustedTarget = targetIndex;
    if (currentIndex >= 0 && targetIndex > currentIndex) {
      adjustedTarget = targetIndex - 1;
    }
    // 跨层移动（嵌套 → 顶层）：currentIndex == -1，索引不调整。
    if (adjustedTarget < 0 || adjustedTarget > blocks.length) return;
    final moved = _editor.moveBlock(
      _root,
      blockId,
      _root.id,
      index: adjustedTarget,
    );
    editorSetState(() {
      _root = moved;
      _nestedDropParentId = null;
      _nestedDropIndex = null;
      _updateDirtyState();
    });
  }

  /// 选中整块（聚焦并更新聚焦 id）。
  void _selectBlock(String blockId) {
    editorSetState(() => _focusedBlockId = blockId);
    final node = _focusNodes[blockId];
    node?.requestFocus();
  }

  /// 为无障碍朗读生成块描述标签。
  String _semanticLabelForBlock(NoteBlock block) {
    final typeLabel = switch (block.type) {
      NoteBlockType.heading => '标题${block.props['level'] ?? 1}',
      NoteBlockType.todo => '待办事项',
      NoteBlockType.code => '代码块',
      NoteBlockType.quote => '引用',
      NoteBlockType.bullet => '无序列表',
      NoteBlockType.ordered => '有序列表',
      NoteBlockType.divider => '分割线',
      NoteBlockType.callout => '提示',
      NoteBlockType.toggle => '切换列表',
      NoteBlockType.image => '图片',
      _ => '段落',
    };
    return '$typeLabel: ${block.text.isEmpty ? '空' : block.text}';
  }

  /// 根据块类型构建前缀 widget（列表符号、复选框等）。
  Widget _buildBlockPrefix(NoteBlock block, int index) {
    switch (block.type) {
      case NoteBlockType.bullet:
        return const Padding(
          padding: EdgeInsets.only(top: 12, right: 4),
          child: Text('•', style: TextStyle(fontSize: 18)),
        );
      case NoteBlockType.ordered:
        return Padding(
          padding: const EdgeInsets.only(top: 12, right: 4),
          child: Text('${index + 1}.', style: const TextStyle(fontSize: 16)),
        );
      case NoteBlockType.todo:
        final checked = block.props['checked'] as bool? ?? false;
        return Padding(
          padding: const EdgeInsets.only(top: 8, right: 4),
          child: GestureDetector(
            onTap: () => _toggleTodo(block.id),
            child: Icon(
              checked ? Icons.check_box : Icons.check_box_outline_blank,
              size: 22,
              color: checked ? Theme.of(context).colorScheme.primary : null,
            ),
          ),
        );
      case NoteBlockType.quote:
        return Padding(
          padding: const EdgeInsets.only(top: 8, right: 8),
          child: Container(
            width: 4,
            height: 28,
            decoration: BoxDecoration(
              color: AppleColor.actionBlue.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(AppleRadius.xs),
            ),
          ),
        );
      case NoteBlockType.divider:
        return const SizedBox.shrink();
      case NoteBlockType.toggle:
        final expanded = block.props['expanded'] as bool? ?? true;
        return Padding(
          padding: const EdgeInsets.only(top: 6, right: 2),
          child: GestureDetector(
            onTap: () => _toggleToggleExpanded(block.id),
            child: Icon(
              expanded
                  ? Icons.keyboard_arrow_down_rounded
                  : Icons.keyboard_arrow_right_rounded,
              size: 22,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        );
      default:
        return const SizedBox(width: 8);
    }
  }

  /// 构建块的可编辑输入区域。
  Widget _buildBlockInput(NoteBlock block) {
    // 分隔线块特殊渲染
    if (block.type == NoteBlockType.divider) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Divider(thickness: 2),
      );
    }

    // 内嵌块使用 EmbeddedBlockView 渲染（不进入可编辑 TextField）
    if (EmbeddedBlockView.isEmbeddedType(block.type)) {
      return EmbeddedBlockView(
        block: block,
        embeddedBuilder: widget.embeddedBlockBuilder,
      );
    }

    final controller = _controllers[block.id];
    final focusNode = _focusNodes[block.id];
    if (controller == null || focusNode == null) {
      return const SizedBox.shrink();
    }

    // 监听键盘事件。Focus 作为祖先节点监听按键（键盘事件会从聚焦的
    // TextField 沿焦点树向上冒泡到这里），因此无需与 TextField 共用
    // focusNode——共用还会触发 "child into parent of itself" 焦点错误。
    return Focus(
      onKeyEvent: (_, event) => _handleBlockKey(block.id, event),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        style: _textStyleForBlockType(block),
        decoration: InputDecoration(
          hintText: _hintTextForBlockType(block.type),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 10,
            horizontal: 4,
          ),
          isDense: true,
        ),
        maxLines: null,
        textInputAction: TextInputAction.none,
        onChanged: (text) => _syncText(block.id),
        onTap: () {
          if (_focusedBlockId != block.id) {
            editorSetState(() {
              _focusedBlockId = block.id;
            });
          }
        },
      ),
    );
  }

  /// 处理块的键盘事件（Enter 分块 / Backspace 空块合并）。
  KeyEventResult _handleBlockKey(String blockId, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // M12.5（IME 兼容根修）：输入法组合期间，一切按键交还输入法——
    // Enter 确认候选词、↑↓ 在候选列表选词、Backspace 删组合文本。
    // 新版 Flutter 会把组合期按键派发给 onKeyEvent（旧 material_ui fork
    // 基于旧版 Flutter 不会派发），方言统一后本处理器在组合期拦截按键，
    // 造成中文输入"无法正常键入"。以组合区间判定，非表面过滤单一按键。
    final composing = _controllers[blockId]?.value.composing;
    if (composing != null && composing != TextRange.empty) {
      return KeyEventResult.ignored;
    }

    // ── 撤销 / 重做（Ctrl+Z / Ctrl+Shift+Z / Ctrl+Y）────────────────
    final isCtrl =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (isCtrl &&
        (event.logicalKey == LogicalKeyboardKey.keyZ ||
            event.logicalKey == LogicalKeyboardKey.keyY)) {
      final isRedo =
          event.logicalKey == LogicalKeyboardKey.keyY ||
          HardwareKeyboard.instance.isShiftPressed;
      final doc = isRedo ? _history.redo() : _history.undo();
      if (doc != null) {
        _restoreDoc(doc);
      }
      return KeyEventResult.handled;
    }

    // ── 上 / 下 方向键块间导航 ───────────────────────────────────────
    final order = List<String>.from(_root.children.map((b) => b.id));
    final idx = order.indexOf(blockId);
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (idx > 0) {
        _focusNodes[order[idx - 1]]?.requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (idx >= 0 && idx < order.length - 1) {
        _focusNodes[order[idx + 1]]?.requestFocus();
      }
      return KeyEventResult.handled;
    }

    // ── Tab / Shift+Tab 缩进 / 取消缩进（创建/退出嵌套）──────────────
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        _outdentBlock(blockId);
      } else {
        _indentBlock(blockId);
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.enter) {
      _splitBlock(blockId);
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      final controller = _controllers[blockId];
      if (controller != null && controller.text.isEmpty) {
        _mergeWithPrevious(blockId);
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  /// 根据块类型返回文本样式（h1-h6 字级 + 主题感知）。
  TextStyle _textStyleForBlockType(NoteBlock block) {
    final theme = Theme.of(context);
    switch (block.type) {
      case NoteBlockType.heading:
        final level = (block.props['level'] as int? ?? 1).clamp(1, 6);
        const sizes = {1: 28.0, 2: 24.0, 3: 20.0, 4: 18.0, 5: 16.0, 6: 14.0};
        return TextStyle(
          fontSize: sizes[level],
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.onSurface,
        );
      case NoteBlockType.code:
        return TextStyle(
          fontFamily: 'monospace',
          fontSize: 15,
          backgroundColor: AppleColor.fillOf(theme.colorScheme),
          color: theme.colorScheme.onSurface,
        );
      case NoteBlockType.todo:
        final checked = block.props['checked'] as bool? ?? false;
        return TextStyle(
          fontSize: 16,
          decoration: checked ? TextDecoration.lineThrough : null,
          color: checked
              ? AppleColor.subtleOf(theme.colorScheme)
              : theme.colorScheme.onSurface,
        );
      case NoteBlockType.quote:
        return TextStyle(
          fontSize: 16,
          fontStyle: FontStyle.italic,
          color: theme.colorScheme.onSurface,
        );
      case NoteBlockType.callout:
        return TextStyle(
          fontSize: 16,
          backgroundColor: theme.colorScheme.primaryContainer.withValues(
            alpha: 0.3,
          ),
          color: theme.colorScheme.onSurface,
        );
      default:
        return TextStyle(fontSize: 16, color: theme.colorScheme.onSurface);
    }
  }

  /// 根据块类型返回占位提示文本。
  String _hintTextForBlockType(NoteBlockType type) {
    switch (type) {
      case NoteBlockType.heading:
        return '标题';
      case NoteBlockType.bullet:
        return '列表项';
      case NoteBlockType.ordered:
        return '列表项';
      case NoteBlockType.todo:
        return '待办事项';
      case NoteBlockType.toggle:
        return '切换列表';
      case NoteBlockType.quote:
        return '引用';
      case NoteBlockType.code:
        return '代码';
      case NoteBlockType.text:
        return '输入内容...';
      case NoteBlockType.divider:
      case NoteBlockType.image:
      case NoteBlockType.callout:
      case NoteBlockType.canvas:
      case NoteBlockType.chart:
      case NoteBlockType.link:
      case NoteBlockType.table:
      case NoteBlockType.database:
      case NoteBlockType.attachment:
        return '';
    }
  }
}
