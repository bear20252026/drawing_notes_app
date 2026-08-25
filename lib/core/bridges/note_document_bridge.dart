// NoteDocument ↔ Notebook 双向转换桥接（#13 持久化修复——2026-08-24）。
//
// 将 V2 的 NoteDocument/NoteParagraph 与 legacy 的
// Notebook/NotebookPage/PageTextItem 进行双向转换，
// 使 V2 编辑器能通过 NotebookStorage 持久化。
//
// 本文件位于 core/bridges/，不属于 V2 模块，因此可以
// 同时 import editor_core 和 legacy 类型（规避 V-005 架构边界检查）。
import 'package:editor_core/editor_core.dart';

import 'package:drawing_notes_app/features/drawing/domain/document.dart';
import 'package:drawing_notes_app/features/drawing/domain/text_item.dart';
import 'package:drawing_notes_app/features/drawing/infrastructure/document_container_codec.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';

/// V2 NoteDocument ↔ Legacy Notebook 双向转换桥接。
///
/// 允许 V2 编辑器通过 NotebookStorage 持久化，
/// 同时保持 V2 数据模型的独立性。
class NoteDocumentBridge {
  const NoteDocumentBridge._();

  // ──────────────────────────── 正向转换（V2 → Legacy） ────────────────────────────

  /// 将 V2 的 [NoteParagraph] 列表转换为 Legacy 的 [PageTextItem] 列表。
  static List<PageTextItem> paragraphsToTextItems(
      List<NoteParagraph> paragraphs) {
    if (paragraphs.isEmpty) return [];
    final items = <PageTextItem>[];
    for (var i = 0; i < paragraphs.length; i++) {
      final p = paragraphs[i];
      items.add(PageTextItem(
        id: p.id,
        x: 0,
        y: i.toDouble(),
        text: p.content,
        fontSize: _fontSizeForParagraphType(p.type),
      ));
    }
    return items;
  }

  static double _fontSizeForParagraphType(NoteParagraphType type) {
    switch (type) {
      case NoteParagraphType.heading:
        return 28;
      case NoteParagraphType.paragraph:
      default:
        return 16;
    }
  }

  /// 将 V2 的 [NoteDocument] 应用到 Legacy 的 [Notebook]。
  static void applyToNotebook(NoteDocument doc, Notebook notebook) {
    notebook.title = doc.title;
    final textItems = paragraphsToTextItems(doc.paragraphs);

    if (notebook.pages.isEmpty) {
      notebook.pages.add(NotebookPage(
        id: '${notebook.id}_page_0',
        title: '页面 1',
        document: DrawingDocument(id: '${notebook.id}_doc', title: '笔记'),
        textItems: textItems,
      ));
    } else {
      final page = notebook.pages.first;
      page.textItems
        ..clear()
        ..addAll(textItems);
    }
  }

  // ──────────────────────────── 反向转换（Legacy → V2） ────────────────────────────

  /// 将 Legacy 的 [PageTextItem] 列表转换为 V2 的 [NoteParagraph] 列表。
  static List<NoteParagraph> textItemsToParagraphs(List<PageTextItem> items) {
    if (items.isEmpty) {
      return [const NoteParagraph(id: 'p_default', content: '')];
    }
    final sorted = List<PageTextItem>.from(items)
      ..sort((a, b) => a.y.compareTo(b.y));
    return sorted
        .map((item) => NoteParagraph(
              id: item.id,
              content: item.text,
              type: item.fontSize >= 24
                  ? NoteParagraphType.heading
                  : NoteParagraphType.paragraph,
            ))
        .toList();
  }

  /// 从 Legacy 的 [Notebook] 创建 V2 的 [NoteDocument]。
  static NoteDocument fromNotebook(Notebook notebook) {
    if (notebook.pages.isEmpty) {
      return NoteDocument(
        id: notebook.id,
        title: notebook.title,
        paragraphs: [const NoteParagraph(id: 'p_default', content: '')],
      );
    }
    final page = notebook.pages.first;
    return NoteDocument(
      id: notebook.id,
      title: notebook.title,
      paragraphs: textItemsToParagraphs(page.textItems),
    );
  }
}
