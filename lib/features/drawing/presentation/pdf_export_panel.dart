import 'package:flutter/material.dart';

import 'package:drawing_notes_app/core/theme/apple_design.dart';
import 'package:drawing_notes_app/features/drawing/application/pdf_export_options.dart';
import 'package:drawing_notes_app/shared/widgets/apple_pressable.dart';
import 'package:drawing_notes_app/shared/widgets/glass_dialog.dart';

/// PDF 导出二级面板的选项结果（null = 用户取消）。
class PdfExportSelection {
  const PdfExportSelection({
    required this.paper,
    required this.range,
    required this.quality,
  });

  final PdfPaper paper;
  final PdfRange range;
  final PdfQuality quality;
}

/// PDF 导出二级面板（M12.5 功能向欠账——设计稿结构：纸张/范围/质量三组）。
///
/// - 纸张：A4 / Letter / 跟随画布（默认 A4；独立画布 + 笔记本当前页生效；
///   整本导出按画布尺寸成页，该行置灰并附注）；
/// - 范围：当前页 / 全部页（仅分页/笔记本模式显示；独立画布隐藏）；
/// - 质量：无损 / 标准 80 / 省流量 60（光栅层；钢笔矢量永远无损）。
/// 按钮序遵循 [AppleDialog] 既有约定（取消左、导出右——C1 未决前不自创新序）。
Future<PdfExportSelection?> showPdfExportPanel(
  BuildContext context, {
  required bool hasMultiplePages,
  required int pageCount,
  PdfPaper initialPaper = PdfPaper.a4,
  PdfQuality initialQuality = PdfQuality.standard,
}) {
  return GlassDialog.show<PdfExportSelection>(
    context: context,
    builder: (ctx) => _PdfExportPanelDialog(
      hasMultiplePages: hasMultiplePages,
      pageCount: pageCount,
      initialPaper: initialPaper,
      initialQuality: initialQuality,
    ),
  );
}

class _PdfExportPanelDialog extends StatefulWidget {
  const _PdfExportPanelDialog({
    required this.hasMultiplePages,
    required this.pageCount,
    required this.initialPaper,
    required this.initialQuality,
  });

  final bool hasMultiplePages;
  final int pageCount;
  final PdfPaper initialPaper;
  final PdfQuality initialQuality;

  @override
  State<_PdfExportPanelDialog> createState() => _PdfExportPanelDialogState();
}

class _PdfExportPanelDialogState extends State<_PdfExportPanelDialog> {
  late PdfPaper _paper = widget.initialPaper;
  late PdfRange _range = PdfRange.currentPage;
  late PdfQuality _quality = widget.initialQuality;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final wholeBook = widget.hasMultiplePages && _range == PdfRange.allPages;
    return AlertDialog(
      title: const Text('导出 PDF'),
      content: SizedBox(
        width: 340,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _groupLabel('纸张'),
              SegmentedButton<PdfPaper>(
                segments: [
                  for (final p in PdfPaper.values)
                    ButtonSegment(value: p, label: Text(p.label)),
                ],
                selected: {_paper},
                onSelectionChanged: (s) => setState(() => _paper = s.first),
              ),
              if (wholeBook)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '整本按画布尺寸成页（沿用整本导出行为）',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              if (widget.hasMultiplePages) ...[
                _groupLabel('范围（共 ${widget.pageCount} 页）'),
                SegmentedButton<PdfRange>(
                  segments: [
                    for (final r in PdfRange.values)
                      ButtonSegment(value: r, label: Text(r.label)),
                  ],
                  selected: {_range},
                  onSelectionChanged: (s) => setState(() => _range = s.first),
                ),
                const SizedBox(height: 12),
              ],
              _groupLabel('质量'),
              SegmentedButton<PdfQuality>(
                segments: [
                  for (final q in PdfQuality.values)
                    ButtonSegment(value: q, label: Text(q.label)),
                ],
                selected: {_quality},
                onSelectionChanged: (s) => setState(() => _quality = s.first),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _quality.hint,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        // ApplePressable 纯视觉模式（手势交给内层 FilledButton；读屏语义
        // 由内层按钮提供，此处不再重复暴露——R6 口径）。
        ApplePressable(
          borderRadius: BorderRadius.circular(AppleRadius.sm),
          child: FilledButton(
            onPressed: () => Navigator.of(context).pop(
              PdfExportSelection(
                paper: _paper,
                range: _range,
                quality: _quality,
              ),
            ),
            child: Text(
              wholeBook ? '导出 ${widget.pageCount} 页' : '导出',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _groupLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppleColor.inkMuted,
        ),
      ),
    );
  }
}
