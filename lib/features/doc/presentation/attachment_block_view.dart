/// 附件块视图（P3-3）：文件 / PDF 内嵌 / 书签卡片。
///
/// 用领域模型 [NoteAttachment]（P3-3）渲染附件卡片。
/// 附件块的 JSON 存于 props['attachment'] = NoteAttachment.toJson()。
/// 本文件仅依赖 notes.domain（NoteBlock/NoteAttachment），与 drawing/chart 解耦。
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:drawing_notes_app/core/storage/pdf_preview_renderer.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block.dart';
import 'package:drawing_notes_app/features/doc/domain/note_attachment.dart';
import 'package:drawing_notes_app/features/notes/presentation/pdf_preview.dart';

/// 附件块视图。
class AttachmentBlockView extends StatefulWidget {
  const AttachmentBlockView({
    super.key,
    required this.block,
    this.onChanged,
    this.pdfRenderer,
  });

  final NoteBlock block;
  final ValueChanged<NoteBlock>? onChanged;

  /// PDF 首页渲染器；null 时默认走 PDFium（生产）且仅当存在本地文件才渲染。
  /// 测试可注入 fake 以避免依赖 pdfrx 原生库。
  final PdfPreviewRenderer? pdfRenderer;

  /// 从块 props 解析 NoteAttachment；失败/缺失时返回 null（渲染空卡片）。
  static NoteAttachment? decodeAttachment(NoteBlock block) {
    final raw = block.props['attachment'];
    if (raw is! String || raw.isEmpty) return null;
    try {
      final obj = jsonDecode(raw);
      if (obj is Map<String, dynamic>) return NoteAttachment.fromJson(obj);
    } catch (_) {
      // ignore: fallback
    }
    return null;
  }

  /// 把 NoteAttachment 编码成块 props。
  static Map<String, dynamic> encodeProps(NoteAttachment a) => {
    'attachment': jsonEncode(a.toJson()),
  };

  @override
  State<AttachmentBlockView> createState() => _AttachmentBlockViewState();
}

class _AttachmentBlockViewState extends State<AttachmentBlockView> {
  NoteAttachment? _attachment;

  @override
  void initState() {
    super.initState();
    _attachment = AttachmentBlockView.decodeAttachment(widget.block);
  }

  @override
  void didUpdateWidget(covariant AttachmentBlockView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.block != widget.block) {
      _attachment = AttachmentBlockView.decodeAttachment(widget.block);
    }
  }

  void _apply(NoteAttachment Function(NoteAttachment) transform) {
    final a = _attachment;
    if (a == null) return;
    final next = transform(a);
    setState(() => _attachment = next);
    widget.onChanged?.call(
      widget.block.copyWith(props: AttachmentBlockView.encodeProps(next)),
    );
  }

  IconData get _icon => switch (_attachment!.kind) {
    AttachmentKind.pdf => Icons.picture_as_pdf_outlined,
    AttachmentKind.bookmark => Icons.bookmark_outline,
    AttachmentKind.file => Icons.insert_drive_file_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final a = _attachment;
    if (a == null) {
      return _placeholder(context);
    }
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(_icon, size: 22, color: scheme.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.name.isEmpty ? '未命名附件' : a.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      a.displaySubtitle,
                      style: TextStyle(fontSize: 12, color: scheme.outline),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (a.description.isNotEmpty)
                Tooltip(
                  message: a.description,
                  child: Icon(
                    Icons.chat_bubble_outline,
                    size: 16,
                    color: scheme.outline,
                  ),
                ),
              IconButton(
                tooltip: '编辑描述',
                icon: const Icon(Icons.edit_outlined, size: 18),
                onPressed: () => _editDescription(),
              ),
            ],
          ),
          if (a.isEmbeddable) ...[
            const SizedBox(height: 10),
            _embedPreview(context, a),
          ],
        ],
      ),
    );
  }

  Widget _placeholder(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.attachment_outlined, size: 22, color: scheme.outline),
          const SizedBox(width: 10),
          Text(
            '附件（待补充）',
            style: TextStyle(color: scheme.outline, fontSize: 13),
          ),
        ],
      ),
    );
  }

  /// PDF 分支：本地有文件且能渲染则用 [PdfAttachmentPreview]，否则回退占位。
  Widget _buildPdfPreview(BuildContext context, NoteAttachment a) {
    if (a.filePath.isEmpty) {
      return _pdfFallbackCard(context, a);
    }
    return PdfAttachmentPreview(
      attachment: a,
      renderer: widget.pdfRenderer ?? const PdfiumPreviewRenderer(),
      onOpen: () => _open(a),
    );
  }

  /// PDF 无本地文件时的回退卡片。
  Widget _pdfFallbackCard(BuildContext context, NoteAttachment a) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(Icons.picture_as_pdf, size: 32, color: scheme.outline),
          const SizedBox(height: 6),
          const Text('PDF 内嵌预览不可用（需本地文件）', style: TextStyle(fontSize: 12)),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: () => _open(a),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('打开 PDF'),
          ),
        ],
      ),
    );
  }

  Widget _embedPreview(BuildContext context, NoteAttachment a) {
    final scheme = Theme.of(context).colorScheme;
    switch (a.kind) {
      case AttachmentKind.pdf:
        return _buildPdfPreview(context, a);
      case AttachmentKind.bookmark:
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                a.url.isEmpty ? '（无链接）' : a.url,
                style: TextStyle(color: scheme.primary, fontSize: 13),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: () => _open(a),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('打开链接'),
              ),
            ],
          ),
        );
      case AttachmentKind.file:
        return const SizedBox.shrink(); // file 不可内嵌，仅显示卡片头
    }
  }

  Future<void> _editDescription() async {
    final a = _attachment;
    if (a == null) return;
    final controller = TextEditingController(text: a.description);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑备注'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '附件的描述/备注'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (result == null) return;
    _apply((x) => x.copyWith(description: result.trim()));
  }

  void _open(NoteAttachment a) {
    // v1：给出外部打开提示；后续接入 url_launcher / 本地文件打开。
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('打开：${a.url.isEmpty ? a.filePath : a.url}')),
    );
  }
}
