import 'package:flutter/material.dart';
import 'package:drawing_notes_app/l10n/app_localizations.dart';

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
    this.layout = PdfLayout.single,
    this.columnMajor = false,
    this.footer = false,
  });

  final PdfPaper paper;
  final PdfRange range;
  final PdfQuality quality;

  /// 独立画布布局档位（v1.17.20）：单页大图 / 按纸张分页。
  final PdfLayout layout;

  /// 分页页序（v1.17.22）：false = 先横后纵（行优先）；true = 先纵后横。
  final bool columnMajor;

  /// 分页页脚（v1.17.22）：标题 · n / m（打印装订用）。
  final bool footer;
}

/// PDF 导出二级面板（M12.5 功能向欠账——设计稿结构：纸张/范围/质量三组）。
///
/// - 纸张：A4 / Letter / 跟随画布（默认 A4；独立画布 + 笔记本当前页生效；
///   整本导出按画布尺寸成页，该行置灰并附注）；
/// - 范围：当前页 / 全部页（仅分页/笔记本模式显示；独立画布隐藏）；
/// - 布局：单页大图 / 按纸张分页（仅独立画布显示；v1.17.20）；
/// - 质量：无损 / 标准 80 / 省流量 60（光栅层；钢笔矢量永远无损）。
/// 按钮序遵循 [AppleDialog] 既有约定（取消左、导出右——C1 未决前不自创新序）。
Future<PdfExportSelection?> showPdfExportPanel(
  BuildContext context, {
  required bool hasMultiplePages,
  required int pageCount,
  bool showLayout = false,
  PdfPaper initialPaper = PdfPaper.a4,
  PdfQuality initialQuality = PdfQuality.standard,
}) {
  return GlassDialog.show<PdfExportSelection>(
    context: context,
    builder: (ctx) => _PdfExportPanelDialog(
      hasMultiplePages: hasMultiplePages,
      pageCount: pageCount,
      showLayout: showLayout,
      initialPaper: initialPaper,
      initialQuality: initialQuality,
    ),
  );
}

class _PdfExportPanelDialog extends StatefulWidget {
  const _PdfExportPanelDialog({
    required this.hasMultiplePages,
    required this.pageCount,
    required this.showLayout,
    required this.initialPaper,
    required this.initialQuality,
  });

  final bool hasMultiplePages;
  final int pageCount;
  final bool showLayout;
  final PdfPaper initialPaper;
  final PdfQuality initialQuality;

  @override
  State<_PdfExportPanelDialog> createState() => _PdfExportPanelDialogState();
}

class _PdfExportPanelDialogState extends State<_PdfExportPanelDialog> {
  late PdfPaper _paper = widget.initialPaper;
  late PdfRange _range = PdfRange.currentPage;
  late PdfQuality _quality = widget.initialQuality;
  PdfLayout _layout = PdfLayout.single;
  bool _columnMajor = false;
  bool _footer = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final wholeBook = widget.hasMultiplePages && _range == PdfRange.allPages;
    return AlertDialog(
      title: Text(AppLocalizations.of(context)?.docMenuExportPdf ?? '导出 PDF'),
      content: SizedBox(
        width: 340,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _groupLabel(AppLocalizations.of(context)?.pdfGroupPaper ?? '纸张'),
              SegmentedButton<PdfPaper>(
                segments: [
                  for (final p in PdfPaper.values)
                    ButtonSegment(
                      value: p,
                      label: Text(
                        p == PdfPaper.canvas
                            ? AppLocalizations.of(context)?.pdfPaperFollow ??
                                  p.label
                            : p.label,
                      ),
                    ),
                ],
                selected: {_paper},
                onSelectionChanged: (s) => setState(() => _paper = s.first),
              ),
              if (wholeBook)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '整本按画布尺寸成页（沿用整本导出行为）',
                    style: AppleType.captionStyle(scheme.onSurfaceVariant),
                  ),
                ),
              const SizedBox(height: 12),
              if (widget.hasMultiplePages) ...[
                _groupLabel('范围（共 ${widget.pageCount} 页）'),
                SegmentedButton<PdfRange>(
                  segments: [
                    for (final r in PdfRange.values)
                      ButtonSegment(
                        value: r,
                        label: Text(
                          r == PdfRange.currentPage
                              ? AppLocalizations.of(context)?.pdfRangeCurrent ??
                                    r.label
                              : AppLocalizations.of(context)?.pdfRangeAll ??
                                    r.label,
                        ),
                      ),
                  ],
                  selected: {_range},
                  onSelectionChanged: (s) => setState(() => _range = s.first),
                ),
                const SizedBox(height: 12),
              ],
              // v1.17.20 布局档位：仅独立画布（笔记本天然分页，无此问题）。
              if (widget.showLayout) ...[
                _groupLabel(
                  AppLocalizations.of(context)?.pdfGroupLayout ?? '布局',
                ),
                SegmentedButton<PdfLayout>(
                  segments: [
                    for (final l in PdfLayout.values)
                      ButtonSegment(
                        value: l,
                        label: Text(
                          l == PdfLayout.single
                              ? AppLocalizations.of(context)?.pdfLayoutSingle ??
                                    l.label
                              : AppLocalizations.of(context)?.pdfLayoutTiled ??
                                    l.label,
                        ),
                      ),
                  ],
                  selected: {_layout},
                  onSelectionChanged: (s) => setState(() => _layout = s.first),
                ),
                if (_layout == PdfLayout.tiled) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      AppLocalizations.of(context)?.pdfLayoutTiledDesc ??
                          '按纸张切成多页常规纸，可打印，不再受超大单页裁剪影响',
                      style: AppleType.captionStyle(scheme.onSurfaceVariant),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // v1.17.22 页序：内容排页方向（纵向长内容选「先纵后横」）。
                  _groupLabel(
                    AppLocalizations.of(context)?.pdfPageOrderLabel ?? '页序',
                  ),
                  SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(
                        value: false,
                        label: Text(
                          AppLocalizations.of(context)?.pdfPageOrderRow ??
                              '先横后纵',
                        ),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text(
                          AppLocalizations.of(context)?.pdfPageOrderColumn ??
                              '先纵后横',
                        ),
                      ),
                    ],
                    selected: {_columnMajor},
                    onSelectionChanged: (s) =>
                        setState(() => _columnMajor = s.first),
                  ),
                  const SizedBox(height: 8),
                  // v1.17.22 页脚：标题 · n / m（打印装订定位用）。
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(
                      AppLocalizations.of(context)?.pdfFooterLabel ?? '页脚页码',
                      style: AppleType.controlStyle(scheme.onSurface),
                    ),
                    subtitle: Text(
                      AppLocalizations.of(context)?.pdfFooterDesc ??
                          '每页底部标注「标题 · n / m」',
                      style: AppleType.captionStyle(scheme.onSurfaceVariant),
                    ),
                    value: _footer,
                    onChanged: (v) => setState(() => _footer = v),
                  ),
                ],
                const SizedBox(height: 12),
              ],
              _groupLabel(
                AppLocalizations.of(context)?.pdfGroupQuality ?? '质量',
              ),
              SegmentedButton<PdfQuality>(
                segments: [
                  for (final q in PdfQuality.values)
                    ButtonSegment(
                      value: q,
                      label: Text(
                        q == PdfQuality.lossless
                            ? AppLocalizations.of(
                                    context,
                                  )?.pdfQualityLossless ??
                                  q.label
                            : q.label,
                      ),
                    ),
                ],
                selected: {_quality},
                onSelectionChanged: (s) => setState(() => _quality = s.first),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _quality == PdfQuality.lossless
                      ? AppLocalizations.of(context)?.pdfQualityLosslessDesc ??
                            _quality.hint
                      : _quality == PdfQuality.standard
                      ? AppLocalizations.of(context)?.pdfQualityStandardDesc ??
                            _quality.hint
                      : AppLocalizations.of(context)?.pdfQualitySaverDesc ??
                            _quality.hint,
                  style: AppleType.captionStyle(scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(AppLocalizations.of(context)?.cancel ?? '取消'),
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
                layout: _layout,
                columnMajor: _columnMajor,
                footer: _footer,
              ),
            ),
            child: Text(
              wholeBook
                  ? AppLocalizations.of(
                          context,
                        )?.pdfExportNPages(widget.pageCount) ??
                        '导出 ${widget.pageCount} 页'
                  : AppLocalizations.of(context)?.catExport ?? '导出',
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
      child: Text(text, style: AppleType.controlStyle(AppleColor.inkMuted)),
    );
  }
}
