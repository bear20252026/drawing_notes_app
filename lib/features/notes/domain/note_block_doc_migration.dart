// 由 Claude 团队生成 | Drawing Notes App
// 存量迁移：将旧 NotebookPage 转为 NoteBlockDoc（向后兼容）。
// 纯 Dart，无 flutter/io/controller/存储依赖。

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/features/notes/domain/note_block.dart';
import 'package:drawing_notes_app/features/notes/domain/note_block_doc.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook_page.dart';

/// 将存量 [NotebookPage] 迁移为 [NoteBlockDoc]。
///
/// 迁移规则（纯函数，不修改源 page）：
/// 1. [page.textItems] 按顺序转为 text 块（每项一个 paragraph 块）。
/// 2. 若 textItems 为空 → body 至少保留一个空 text 块。
/// 3. 若 [page.document] 非空（含笔画/形状/图片/文本层等）→ 追加一个 canvas 块，
///    props={'document': page.document.toJson()}。
/// 4. 可选增强：[page.charts] / [page.imageItems] 非空时各追加 chart/image 块。
///
/// 不修改输入的 [page]；返回全新 [NoteBlockDoc] 实例。
NoteBlockDoc migrateNotebookPage(
  NotebookPage page, {
  bool includeCharts = true,
  bool includeImages = true,
}) {
  final blocks = <NoteBlock>[];

  // 1. 文字项 → text 块
  for (var i = 0; i < page.textItems.length; i++) {
    final item = page.textItems[i];
    blocks.add(NoteBlock.textBlock(
      '${page.id}_text_$i',
      text: item.text,
    ));
  }

  // 2. 空文档兜底：至少一个空 text 块
  if (blocks.isEmpty) {
    blocks.add(NoteBlock.textBlock('${page.id}_text_0', text: ''));
  }

  // 3. 画布内容 → canvas 块
  if (!_isDocumentEmpty(page.document)) {
    blocks.add(NoteBlock(
      id: '${page.id}_canvas',
      type: NoteBlockType.canvas,
      props: {'document': page.document.toJson()},
    ));
  }

  // 4. 可选：图表 → chart 块
  if (includeCharts && page.charts.isNotEmpty) {
    for (var i = 0; i < page.charts.length; i++) {
      final chart = page.charts[i];
      blocks.add(NoteBlock(
        id: '${page.id}_chart_$i',
        type: NoteBlockType.chart,
        props: {'chart': chart.toJson()},
      ));
    }
  }

  // 5. 可选：图片 → image 块
  if (includeImages && page.imageItems.isNotEmpty) {
    for (var i = 0; i < page.imageItems.length; i++) {
      final image = page.imageItems[i];
      blocks.add(NoteBlock(
        id: '${page.id}_image_$i',
        type: NoteBlockType.image,
        props: {'image': image.toJson()},
      ));
    }
  }

  return NoteBlockDoc(
    id: page.id,
    title: page.title,
    body: blocks,
    createdAt: page.createdAt,
    updatedAt: page.updatedAt,
  );
}

/// 判断 [DrawingDocument] 是否为空（无内容可迁移）。
bool _isDocumentEmpty(DrawingDocument doc) {
  return doc.layers.every((layer) => layer.strokes.isEmpty) &&
      doc.shapes.isEmpty &&
      doc.imageItems.isEmpty &&
      doc.textItems.isEmpty;
}
