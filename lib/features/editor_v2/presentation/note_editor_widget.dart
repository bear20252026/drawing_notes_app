// NoteEditorWidget——笔记模式编辑器（#18 Word 式直接打字——2026-08-22——
// #13 持久化修复——2026-08-24）。
//
// 设计理念（借鉴 AFFiNE Page——保留版权声明）：
// - Word 式文档编辑：标题 + 多段落（直接打字——不弹窗）
// - Enter 新增段落（光标移到新段落——Word 体验）
// - Backspace 删除空段落（合并到上一段——Word 体验）
// - 每个段落独立 TextEditingController（精准光标控制）
// - onChanged 回调父组件（持久化由 EditorV2Screen 处理——#13）
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:editor_core/editor_core.dart';

/// NoteEditorWidget——Word 式文档编辑器（#18）。
///
/// 受控组件：document 来自父组件，onChanged 回调变更。
/// 父组件（EditorV2Screen）负责存储状态和持久化（#13）。
class NoteEditorWidget extends StatefulWidget {
  const NoteEditorWidget({
    super.key,
    required this.document,
    required this.onChanged,
  });

  /// 当前笔记文档（来自父组件——受控模式）。
  final NoteDocument document;

  /// 内容变更回调（父组件更新状态 + 持久化）。
  final ValueChanged<NoteDocument> onChanged;

  @override
  State<NoteEditorWidget> createState() => _NoteEditorWidgetState();
}

class _NoteEditorWidgetState extends State<NoteEditorWidget> {
  late TextEditingController _titleController;
  late List<TextEditingController> _paragraphControllers;
  late List<FocusNode> _focusNodes;

  /// 当前 document 的段落数（用于检测外部变化）。
  late int _currentParagraphCount;

  @override
  void initState() {
    super.initState();
    _currentParagraphCount = widget.document.paragraphs.length;
    _titleController = TextEditingController(text: widget.document.title);
    _paragraphControllers = widget.document.paragraphs
        .map((p) => TextEditingController(text: p.content))
        .toList();
    _focusNodes = List.generate(
      widget.document.paragraphs.length,
      (_) => FocusNode(),
    );
  }

  @override
  void didUpdateWidget(NoteEditorWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 外部 document 变化（从存储加载、撤销等）→ 重建控制器。
    final newCount = widget.document.paragraphs.length;
    if (newCount != _currentParagraphCount) {
      _rebuildControllers();
      _currentParagraphCount = newCount;
    }

    // 同步标题（外部变更时）
    if (_titleController.text != widget.document.title) {
      _titleController.text = widget.document.title;
    }
  }

  /// 重建所有段落控制器（段落数变化时调用）。
  void _rebuildControllers() {
    // 释放旧控制器
    for (final c in _paragraphControllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    // 创建新控制器
    _paragraphControllers = widget.document.paragraphs
        .map((p) => TextEditingController(text: p.content))
        .toList();
    _focusNodes = List.generate(
      widget.document.paragraphs.length,
      (_) => FocusNode(),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    for (final c in _paragraphControllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  // ──────────────────────────── 段落操作 ────────────────────────────

  /// 更新指定段落内容（触发 onChanged 回调）。
  void _updateParagraph(int index, String text) {
    if (index >= widget.document.paragraphs.length) return;
    final updated = List<NoteParagraph>.from(widget.document.paragraphs);
    updated[index] = updated[index].copyWith(content: text);
    widget.onChanged(widget.document.copyWith(paragraphs: updated));
  }

  /// 更新标题（触发 onChanged 回调）。
  void _updateTitle(String text) {
    widget.onChanged(widget.document.copyWith(title: text));
  }

  /// 新增段落（Enter 键触发——Word 式——#18）。
  void _addParagraph(int afterIndex) {
    final updated = List<NoteParagraph>.from(widget.document.paragraphs);
    final newId = 'p${DateTime.now().millisecondsSinceEpoch}';
    updated.insert(afterIndex + 1, NoteParagraph(id: newId, content: ''));
    widget.onChanged(widget.document.copyWith(paragraphs: updated));
    // 新段落聚焦（延迟等 build 完成——控制器已重建）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final targetIndex = afterIndex + 1;
      if (targetIndex < _focusNodes.length) {
        _focusNodes[targetIndex].requestFocus();
      }
    });
  }

  /// 删除段落（Backspace 空段落触发——Word 式——#18）。
  void _deleteParagraph(int index) {
    if (index <= 0) return; // 保留第一个段落
    final updated = List<NoteParagraph>.from(widget.document.paragraphs);
    if (updated.length <= 1) return; // 至少保留一个段落
    updated.removeAt(index);
    widget.onChanged(widget.document.copyWith(paragraphs: updated));
    // 聚焦前一段末尾（延迟等 build 完成）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final targetIndex = index - 1;
      if (targetIndex < _focusNodes.length) {
        _focusNodes[targetIndex].requestFocus();
        // 移动光标到末尾
        final controller = _paragraphControllers[targetIndex];
        controller.selection = TextSelection.collapsed(
          offset: controller.text.length,
        );
      }
    });
  }

  // ──────────────────────────── 构建 UI ────────────────────────────

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // 点击空白区域聚焦最后一个段落（Word 体验——#18）
      onTap: () {
        if (_focusNodes.isNotEmpty) {
          _focusNodes.last.requestFocus();
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 标题区（可编辑——Word 式标题——#18）──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: TextField(
              controller: _titleController,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
              decoration: const InputDecoration(
                hintText: '标题',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: _updateTitle,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) {
                // 从标题跳转到第一段落（Word 体验——Tab/Enter）
                if (_focusNodes.isNotEmpty) {
                  _focusNodes.first.requestFocus();
                }
              },
            ),
          ),
          const Divider(height: 1, thickness: 0.5),
          // ── 段落列表（Word 式——Enter 新增——Backspace 删除——直接打字）──
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 80),
              itemCount: widget.document.paragraphs.length,
              itemBuilder: (context, index) {
                if (index >= widget.document.paragraphs.length) {
                  return const SizedBox.shrink();
                }
                final paragraph = widget.document.paragraphs[index];
                return _buildParagraphField(context, index, paragraph);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParagraphField(
    BuildContext context,
    int index,
    NoteParagraph paragraph,
  ) {
    // 防越界
    if (index >= _paragraphControllers.length) {
      return const SizedBox.shrink();
    }

    final controller = _paragraphControllers[index];

    // 同步控制器文本（外部更新时——如从存储加载）
    if (controller.text != paragraph.content) {
      final oldOffset = controller.selection.extentOffset;
      controller.text = paragraph.content;
      // 尝试恢复光标位置（最佳努力——不崩溃）
      try {
        final safeOffset = oldOffset.clamp(0, controller.text.length);
        controller.selection = TextSelection.collapsed(offset: safeOffset);
      } catch (_) {}
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;

          // Enter 键：新增段落（Word 式——#18）。
          if (event.logicalKey == LogicalKeyboardKey.enter &&
              !HardwareKeyboard.instance.isShiftPressed) {
            _addParagraph(index);
            return KeyEventResult.handled;
          }

          // Backspace 键：删除空段落（Word 式——合并到上一段——#18）。
          if (event.logicalKey == LogicalKeyboardKey.backspace &&
              controller.text.isEmpty &&
              index > 0) {
            _deleteParagraph(index);
            return KeyEventResult.handled;
          }

          return KeyEventResult.ignored;
        },
        child: paragraph.isHeading
            ? TextField(
                controller: controller,
                focusNode: _focusNodes[index],
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                decoration: const InputDecoration(
                  hintText: '标题',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: (text) => _updateParagraph(index, text),
                textInputAction: TextInputAction.next,
                onSubmitted: (_) {
                  // 段落标题 Enter → 跳转下一段（已由 _addParagraph 处理，
                  // 此处作为 fallback）
                  if (index + 1 < _focusNodes.length) {
                    _focusNodes[index + 1].requestFocus();
                  }
                },
              )
            : TextField(
                controller: controller,
                focusNode: _focusNodes[index],
                maxLines: null,
                minLines: 1,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  hintText: '开始输入…',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: (text) => _updateParagraph(index, text),
              ),
      ),
    );
  }
}
