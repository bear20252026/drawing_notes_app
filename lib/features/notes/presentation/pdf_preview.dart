// 由 Claude 团队生成 | Drawing Notes App
// PDF 附件内嵌预览部件：把本地 PDF 的首页渲染成一张内存 PNG 并展示，
// 失败/无图回退为「打开 PDF」卡片。只依赖 core 的 [PdfPreviewRenderer]
// 接口（组合根注入实现），widget 层不直接触原生库。

import 'package:flutter/material.dart';

import 'package:drawing_notes_app/core/storage/pdf_preview_renderer.dart';
import 'package:drawing_notes_app/features/doc/domain/note_attachment.dart';
import '../../../core/theme/apple_design.dart';

/// 附件内嵌 PDF 预览（首页缩略）。
class PdfAttachmentPreview extends StatefulWidget {
  const PdfAttachmentPreview({
    super.key,
    required this.attachment,
    required this.renderer,
    required this.onOpen,
    this.maxWidth = 480,
    this.maxHeight = 220,
  });

  final NoteAttachment attachment;
  final PdfPreviewRenderer renderer;
  final VoidCallback onOpen;
  final double maxWidth;

  /// 预览高度上限，避免过高挤爆块。
  final double maxHeight;

  @override
  State<PdfAttachmentPreview> createState() => _PdfAttachmentPreviewState();
}

class _PdfAttachmentPreviewState extends State<PdfAttachmentPreview> {
  PdfPreviewPage? _page;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PdfAttachmentPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachment.filePath != widget.attachment.filePath) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _page = null;
    });
    PdfPreviewPage? page;
    try {
      page = await widget.renderer.renderPage(
        widget.attachment.filePath,
        maxWidth: widget.maxWidth,
      );
    } catch (_) {
      page = null;
    }
    if (!mounted) return;
    setState(() {
      _page = page;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final page = _page;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppleRadius.sm),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          if (_loading)
            SizedBox(
              height: widget.maxHeight,
              child: Center(
                child: SizedBox(
                  // 刻意保留 spinner（审计二-6 分类裁决）：这是文档
                  // 解析**进度**反馈而非页面布局骨架，无行结构可预告。
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (page != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(AppleRadius.xs),
              child: SizedBox(
                width: double.infinity,
                height: widget.maxHeight,
                child: Image.memory(
                  page.pngBytes,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.medium,
                ),
              ),
            )
          else
            // 无法渲染：回退为「打开 PDF」占位。
            Column(
              children: [
                Icon(
                  Icons.picture_as_pdf_outlined,
                  size: 32,
                  color: scheme.outline,
                ),
                const SizedBox(height: 4),
                Text(
                  'PDF 内嵌预览不可用',
                  style: TextStyle(fontSize: 12, color: scheme.outline),
                ),
              ],
            ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: widget.onOpen,
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('打开 PDF'),
            ),
          ),
        ],
      ),
    );
  }
}
