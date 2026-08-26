import 'package:material_ui/material_ui.dart';

import 'package:drawing_notes_app/core/navigation/editor_page_builder.dart';
import 'package:drawing_notes_app/core/notes_accessor.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';
import 'package:drawing_notes_app/features/drawing/domain/document.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_page.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';

/// 应用层的默认编辑器实现。
///
/// 此文件是 notes/drawing presentation 的唯一组合点；功能模块只依赖
/// [EditorPageBuilder] 契约，不再直接构造 [EditorPage]。
class DefaultEditorPageBuilder {
  const DefaultEditorPageBuilder._();

  static Widget build({
    DrawingDocument? document,
    Notebook? notebook,
    NotebookPage? page,
    INotebookAccessor? notebookAccessor,
    StorageService? documentStorage,
    VoidCallback? onChanged,
    Future<void> Function(BuildContext context, NotebookPage page)?
    openPresentation,
  }) {
    return EditorPage(
      document: document,
      notebook: notebook,
      page: page,
      storage: notebookAccessor,
      docStorage: documentStorage,
      onChanged: onChanged,
      openPresentation: openPresentation,
    );
  }
}
