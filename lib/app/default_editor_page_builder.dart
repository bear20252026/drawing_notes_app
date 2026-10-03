import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:drawing_notes_app/core/navigation/editor_page_builder.dart';
import 'package:drawing_notes_app/core/navigation/editor_page_session.dart';
import 'package:drawing_notes_app/core/notes_accessor.dart';
import 'package:drawing_notes_app/core/rendering/notebook_print_page_data.dart';
import 'package:drawing_notes_app/core/security/media_crypto_service.dart';
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

  /// 缺省多页导出器（C-06，审计 2026-09-27）：NotebookPdfExporter 改实例
  /// 类后，媒体解密依赖在此由组合根装配（app 层是唯一允许触达 core 解锁
  /// 会话单例的组装位置——features/shared 已被
  /// test/security_static_access_gate_test.dart 锁死零直取）。
  static final NotebookPdfExporter _defaultPdfExporter = NotebookPdfExporter(
    mediaCrypto: MediaCryptoService.instance,
  );

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
    MediaCryptoService? mediaCrypto,
    Future<void> Function(BuildContext context)? openPresentation,
  }) {
    return EditorPage(
      document: document,
      session: session,
      allSessionsProvider: allSessions,
      multipagePdfComposer:
          multipageComposer ?? _defaultPdfExporter.exportPages,
      storage: notebookAccessor,
      docStorage: documentStorage,
      onChanged: onChanged,
      mediaCrypto: mediaCrypto,
      openPresentation: openPresentation,
    );
  }
}
