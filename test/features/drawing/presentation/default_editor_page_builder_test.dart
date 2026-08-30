import 'package:drawing_notes_app/app/default_editor_page_builder.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_page.dart';
import 'package:drawing_notes_app/features/notes/application/notebook_page_editor_session.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('独立画布会话由应用层构建为 EditorPage', () {
    final page = DefaultEditorPageBuilder.build(
      document: DrawingDocument(id: 'drawing-1', title: '画作'),
      documentStorage: StorageService(),
    );

    expect(page, isA<EditorPage>());
  });

  test('笔记页面会话由应用层构建为 EditorPage', () {
    final notebookPage = NotebookPage(
      id: 'page-1',
      title: '页面',
      document: DrawingDocument(id: 'document-1', title: '画布'),
    );

    final editor = DefaultEditorPageBuilder.build(
      session: NotebookPageEditorSession(notebookPage),
    );

    expect(editor, isA<EditorPage>());
  });
}
