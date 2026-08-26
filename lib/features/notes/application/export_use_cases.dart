// notes — Application 层：导出用例
// 遵循 Clean Architecture：Application 层只依赖 Domain 层

import '../../../core/storage/repository.dart';
import '../domain/entities/notebook.dart';

/// 导出用例（Application 层）
///
/// 封装笔记导出相关业务逻辑
class ExportUseCases {
  const ExportUseCases(this._repository);

  final NotebookRepository _repository;

  /// 导出笔记本为纯文本
  Future<String> exportAsText(String notebookId) async {
    final notebook = await _repository.load(notebookId);
    if (notebook == null) return '';
    final buffer = StringBuffer();
    buffer.writeln('# ${notebook.title}');
    buffer.writeln();
    for (final page in notebook.pages) {
      for (final paragraph in page.paragraphs) {
        buffer.writeln(paragraph.text);
      }
      buffer.writeln('---');
    }
    return buffer.toString();
  }

  /// 导出笔记本元数据摘要
  Future<Map<String, dynamic>> exportMetadata(String notebookId) async {
    final notebook = await _repository.load(notebookId);
    if (notebook == null) return {};
    return {
      'id': notebook.id,
      'title': notebook.title,
      'pageCount': notebook.pages.length,
      'createdAt': notebook.createdAt.toIso8601String(),
      'updatedAt': notebook.updatedAt.toIso8601String(),
      'encrypted': notebook.encrypted,
    };
  }
}
