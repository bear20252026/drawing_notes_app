// editor_v2——NoteEditorWidget 笔记文档编辑器（AFFiNE Page 借鉴——2026-08-22）。
//
// 用户需求：笔记区域就是一个笔记——像 Word 文档一样可以直接打字。
// 校验 AFFiNE：Page Mode = 块编辑器（BlockSuite——直接打字——Word 文档式）。
//
// 本地化：段落列表（NoteParagraph[]——可编辑——直接打字——Word 式——
// 每段落一个 TextField——回车新增段落——标题/正文）。
// 积木式独立 Widget——可插拔——不搞崩。
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_design.dart';
import '../../../../core/theme/responsive.dart';
import '../../../core/theme/text_scale_helper.dart';
import 'package:editor_core/editor_core.dart';

/// 笔记文档编辑器（Word 文档式——直接打字——AFFiNE Page 借鉴）。
///
/// 用法（note 模式）：
/// ```dart
/// NoteEditorWidget(
///   document: noteDocument,
///   onChanged: (doc) => save(doc),
/// )
/// ```
/// 每段落一个 TextField——直接打字——Word 式——回车新增段落。
class NoteEditorWidget extends StatefulWidget {
  const NoteEditorWidget({
    super.key,
    required this.document,
    required this.onChanged,
  });

  /// 笔记文档（段落列表——Word 式）。
  final NoteDocument document;

  /// 内容变更回调（保存）。
  final ValueChanged<NoteDocument> onChanged;

  @override
  State<NoteEditorWidget> createState() => _NoteEditorWidgetState();
}

class _NoteEditorWidgetState extends State<NoteEditorWidget> {
  final List<TextEditingController> _controllers = [];
  late TextEditingController _titleController;
  final FocusNode _autoFocusNode = FocusNode();
  bool _hasAutoFocused = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.document.title);
    _syncControllers();
    // 自动请求焦点——确保可立即打字。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_hasAutoFocused) {
        _hasAutoFocused = true;
        if (_controllers.isNotEmpty) {
          _controllers.first.selection = TextSelection.collapsed(
            offset: _controllers.first.text.length,
          );
          _autoFocusNode.requestFocus();
        }
      }
    });
  }

  @override
  void didUpdateWidget(covariant NoteEditorWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.document.paragraphCount != widget.document.paragraphCount) {
      _syncControllers();
    }
  }

  /// 同步控制器（每个段落一个——Word 式打字）。
  void _syncControllers() {
    while (_controllers.length > widget.document.paragraphCount) {
      _controllers.removeLast().dispose();
    }
    while (_controllers.length < widget.document.paragraphCount) {
      _controllers.add(TextEditingController());
    }
  }

  @override
  void dispose() {
    _autoFocusNode.dispose();
    _titleController.dispose();
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  /// 新增段落（回车——Word 式）。
  void _addParagraph() {
    final paragraphs = List<NoteParagraph>.from(widget.document.paragraphs);
    paragraphs.add(NoteParagraph(
      id: 'para-${DateTime.now().millisecondsSinceEpoch}',
      content: '',
    ));
    widget.onChanged(widget.document.copyWith(paragraphs: paragraphs));
    Future.microtask(() {
      if (mounted) setState(() {});
    });
  }

  /// 更新段落内容。
  void _updateParagraph(int index, String content) {
    if (index >= widget.document.paragraphCount) return;
    final paragraphs = List<NoteParagraph>.from(widget.document.paragraphs);
    paragraphs[index] = paragraphs[index].copyWith(content: content);
    widget.onChanged(widget.document.copyWith(paragraphs: paragraphs));
  }

  @override
  Widget build(BuildContext context) {
    // Word 文档式页面（白纸——AFFiNE Page——居中——可读性好）。
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final padding = context.responsivePadding();
    return Container(
      color: isDark ? AppDesign.darkCanvas : Colors.white,
      child: SingleChildScrollView(
        padding: padding,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: context.responsiveFont(mobile: 640, desktop: 800)), // Word 页面宽度。
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 标题（可编辑——Word 文档标题）。
                TextField(
                  controller: _titleController,
                  style: TextStyle(
                    fontSize: TextScaleHelper.scaled(context, 24) + 4, // 28 → responsive
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                  decoration: InputDecoration(
                    hintText: '标题',
                    hintStyle: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: context.responsiveFont(mobile: 6, desktop: 10)),
                  ),
                  onChanged: (text) {
                    widget.onChanged(widget.document.copyWith(title: text));
                  },
                ),
                SizedBox(height: context.responsiveFont(mobile: 12, desktop: 20)),
                // 段落列表（每段 TextField——直接打字——Word 式）。
                for (var i = 0; i < widget.document.paragraphCount; i++)
                  _buildParagraphField(i),
                // 无"新增段落"按钮——Enter 键新增（Word 式体验）。
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 段落输入框（Word 文档式——直接打字）。
  Widget _buildParagraphField(int index) {
    final paragraph = widget.document.paragraphs[index];
    final controller = _controllers[index];
    // 仅在外部文档更新时同步——避免覆盖用户正在输入的内容。
    if (controller.text.isEmpty && paragraph.content.isNotEmpty) {
      controller.text = paragraph.content;
      controller.selection = TextSelection.collapsed(offset: controller.text.length);
    }

    final theme = Theme.of(context);
    final style = TextStyle(
      fontSize: context.responsiveFont(mobile: paragraph.isHeading ? 22 : 15, desktop: paragraph.isHeading ? 26 : 18),
      fontWeight: paragraph.isHeading ? FontWeight.bold : FontWeight.normal,
      height: 1.6,
      color: theme.colorScheme.onSurface,
    );

    return TextField(
      controller: controller,
      focusNode: index == 0 ? _autoFocusNode : null, // 第一段落自动聚焦。
      maxLines: null, // 多行——Word 式。
      style: style,
      decoration: InputDecoration(
        hintText: paragraph.isHeading ? '标题' : '开始输入…',
        hintStyle: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
        border: InputBorder.none, // 白纸无边框。
        contentPadding: EdgeInsets.symmetric(vertical: context.responsiveFont(mobile: 6, desktop: 10)),
      ),
      onChanged: (text) => _updateParagraph(index, text),
      onSubmitted: (_) => _addParagraph(), // 回车新增段落（Word 式）。
    );
  }
}
