import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:drawing_notes_app/core/navigation/editor_page_builder.dart';
import 'package:drawing_notes_app/core/navigation/editor_page_session.dart';
import 'package:drawing_notes_app/core/notes_accessor.dart';
import 'package:drawing_notes_app/core/rendering/notebook_print_page_data.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_page.dart';
import 'package:drawing_notes_app/features/notes/application/notebook_pdf_exporter.dart';

/// 应用层的默认编辑器实现。
///
/// 此文件是 notes/drawing presentation 的唯一组合点；功能模块只依赖
/// [EditorPageBuilder] 契约，不再直接构造 [EditorPage]。
///
/// C-01 解环（审计 2026-09-27）：多页 PDF 合成引擎由本组合点注入——
/// drawing（EditorExporter）与 notes（NotebookPdfExporter）各自只依赖
/// core 契约（NotebookPrintPageData），feature 级环自此斩断。
class DefaultEditorPageBuilder {
  const DefaultEditorPageBuilder._();

  static Widget build({
    DrawingDocument? document,
    EditorPageSession? session,
    List<EditorPageSession> Function()? allSessions,
    Future<Uint8List> Function(
      List<NotebookPrintPageData> pages, {
      int? jpegQuality,
    })?
    multipageComposer,
    INotebookAccessor? notebookAccessor,
    StorageService? documentStorage,
    VoidCallback? onChanged,
    Future<void> Function(BuildContext context)? openPresentation,
  }) {
    return EditorPage(
      document: document,
      session: session,
      allSessionsProvider: allSessions,
      multipagePdfComposer:
          multipageComposer ?? NotebookPdfExporter.exportPages,
      storage: notebookAccessor,
      docStorage: documentStorage,
      onChanged: onChanged,
      openPresentation: openPresentation,
    );
  }
}
