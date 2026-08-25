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

  @override
  void initState() {
    super.initState();
    _syncControllers();
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
    return Container(
      color: Colors.white,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720), // Word 页面宽度。
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 标题（笔记标题——Word 文档标题）。
                Text(
                  widget.document.title,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 16),
                // 段落列表（每段 TextField——直接打字——Word 式）。
                for (var i = 0; i < widget.document.paragraphCount; i++)
                  _buildParagraphField(i),
                // 新增段落按钮（Word 式——点击加段落）。
                TextButton.icon(
                  onPressed: _addParagraph,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('新增段落'),
                ),
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
    if (controller.text != paragraph.content) {
      controller.text = paragraph.content;
      controller.selection = TextSelection.collapsed(offset: controller.text.length);
    }

    final style = TextStyle(
      fontSize: paragraph.isHeading ? 24 : 17, // 标题大——正文 17（SF Pro——苹果）。
      fontWeight: paragraph.isHeading ? FontWeight.bold : FontWeight.normal,
      height: 1.6,
      color: Colors.black87,
    );

    return TextField(
      controller: controller,
      maxLines: null, // 多行——Word 式。
      style: style,
      decoration: InputDecoration(
        hintText: paragraph.isHeading ? '标题' : '开始打字……（Word 文档式）',
        border: InputBorder.none, // 白纸无边框。
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
      ),
      onChanged: (text) => _updateParagraph(index, text),
      onSubmitted: (_) => _addParagraph(), // 回车新增段落（Word 式）。
    );
  }
}
