/// 画作文档仓库抽象接口 — 零外部依赖。
///
/// 定义画作文档存储的契约，由 infrastructure/storage/ 实现。
///
/// 架构原则：
/// - Domain 层零依赖：不引用任何 Flutter 或其他 feature
/// - 依赖倒置：core 提供接口，infrastructure 实现接口
library;

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

/// 画作文档仓库抽象接口。
///
/// UI/引擎层只依赖此接口，不感知具体存储实现；
/// 未来接云同步时实现同一接口即可替换（本地 JSON → 远端 API），
/// 画布与笔记逻辑无需改动。
abstract class DocumentRepository {
  Future<String> save(dynamic doc);
  Future<dynamic?> load(String id);
  Future<List<DocumentMeta>> listDocuments();
  Future<bool> delete(String id);
}
