import '../../features/drawing/domain/document.dart';
import '../../features/notes/domain/notebook.dart';

/// 画作文档仓库抽象接口（B4，借鉴 Memos REST API 的存储解耦）。
///
/// UI/引擎层只依赖此接口，不感知具体存储实现；
/// 未来接云同步时实现同一接口即可替换（本地 JSON → 远端 API），
/// 画布与笔记逻辑无需改动。
abstract class DocumentRepository {
  Future<String> save(DrawingDocument doc);
  Future<DrawingDocument?> load(String id);
  Future<List<DocumentMeta>> listDocuments();
  Future<bool> delete(String id);
}

/// 笔记本仓库抽象接口（B4）。
abstract class NotebookRepository {
  Future<String> save(Notebook notebook);
  Future<Notebook?> load(String id);
  Future<List<Notebook>> listAll();
  Future<bool> delete(String id);
}

/// 文档元信息（列表页展示用，不包含全部数据，读取快）。
class DocumentMeta {
  const DocumentMeta({
    required this.id,
    required this.title,
    required this.width,
    required this.height,
    required this.createdAt,
    required this.updatedAt,
    required this.layerCount,
    required this.strokeCount,
  });

  final String id;
  final String title;
  final int width;
  final int height;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int layerCount;
  final int strokeCount;
}
