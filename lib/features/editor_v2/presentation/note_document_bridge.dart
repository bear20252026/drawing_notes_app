// NoteDocument ↔ Notebook 持久化桥接（#13 修复——2026-08-24）。
//
// 解决核心问题：NoteEditorWidget 的 NoteDocument 与 NotebookStorage 的
// Notebook 之间没有持久化通道，导致打字内容重启即丢失。
//
// 桥接策略：
// - NoteDocument.paragraphs ↔ NotebookPage.textItems（一对一映射）
// - 段落类型通过 fontSize 编码（heading=28, paragraph=16）
// - 段落顺序通过 textItems 的 y 坐标排序维护
library;

import 'package:editor_core/editor_core.dart';
import 'package:drawing_notes_app/features/drawing/domain/document.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';

/// NoteDocument ↔ Notebook 双向转换桥接。
class NoteDocumentBridge {
  NoteDocumentBridge._();

  // ──────────────────────────── NoteDocument → Notebook ────────────────────────────

  /// 将 NoteDocument 的段落转换为 PageTextItems（用于存储到 NotebookPage）。
  ///
  /// 每个 NoteParagraph 映射为一个 PageTextItem：
  /// - text = paragraph.content
  /// - y = 段落索引（排序用）
  /// - fontSize 编码段落类型（heading=28, paragraph=16）
  static List<PageTextItem> paragraphsToTextItems(
    List<NoteParagraph> paragraphs,
  ) {
    return List.generate(paragraphs.length, (i) {
      final p = paragraphs[i];
      return PageTextItem(
        id: p.id,
        x: 0,
        y: i.toDouble(),
        text: p.content,
        fontSize: p.isHeading ? 28 : 16,
      );
    });
  }

  /// 将 NoteDocument 保存到 Notebook（更新或创建对应的 NotebookPage）。
  ///
  /// 逻辑：
  /// 1. 若 notebook.pages 为空，创建一个新 page
  /// 2. 更新第一个 page 的 textItems 和 title
  /// 3. 更新 notebook.title（若 noteDoc.title 不同）
  /// 4. touch() 更新时间戳
  static void applyToNotebook(NoteDocument noteDoc, Notebook notebook) {
    final textItems = paragraphsToTextItems(noteDoc.paragraphs);

    if (notebook.pages.isEmpty) {
      // 创建默认页面
      notebook.pages.add(
        NotebookPage(
          id: '${notebook.id}_page1',
          title: noteDoc.title.isNotEmpty ? noteDoc.title : '笔记',
          document: DrawingDocument(id: '${notebook.id}_doc', title: '笔记'),
          textItems: textItems,
        ),
      );
    } else {
      // 更新现有页面
      final page = notebook.pages.first;
      page.textItems
        ..clear()
        ..addAll(textItems);
      page.title = noteDoc.title;
      page.updatedAt = DateTime.now();
    }

    // 同步笔记本标题
    if (noteDoc.title.isNotEmpty) {
      notebook.title = noteDoc.title;
    }
    notebook.touch();
  }

  // ──────────────────────────── Notebook → NoteDocument ────────────────────────────

  /// 将 PageTextItems 转换为 NoteParagraphs（从 NotebookPage 加载）。
  ///
  /// - 按 y 坐标排序维护段落顺序
  /// - fontSize >= 24 视为 heading，否则为 paragraph
  static List<NoteParagraph> textItemsToParagraphs(
    List<PageTextItem> items,
  ) {
    if (items.isEmpty) return [const NoteParagraph(id: 'p1', content: '')];

    // 按 y 坐标排序（段落顺序）
    final sorted = List<PageTextItem>.from(items)
      ..sort((a, b) => a.y.compareTo(b.y));

    return sorted.map((item) {
      return NoteParagraph(
        id: item.id,
        content: item.text,
        type: item.fontSize >= 24
            ? NoteParagraphType.heading
            : NoteParagraphType.paragraph,
      );
    }).toList();
  }

  /// 从 Notebook 加载 NoteDocument（提取第一个 page 的 textItems）。
  ///
  /// 若 notebook.pages 为空或 textItems 为空，返回默认空文档。
  static NoteDocument fromNotebook(Notebook notebook) {
    if (notebook.pages.isEmpty) {
      return NoteDocument(
        id: notebook.id,
        title: notebook.title,
        paragraphs: [const NoteParagraph(id: 'p1', content: '')],
      );
    }

    final page = notebook.pages.first;
    final paragraphs = textItemsToParagraphs(page.textItems);

    return NoteDocument(
      id: notebook.id,
      title: notebook.title,
      paragraphs: paragraphs,
    );
  }
}
