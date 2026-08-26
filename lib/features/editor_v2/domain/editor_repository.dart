// editor_v2 — Domain 层：仓储接口（零外部依赖）
// 遵循 Clean Architecture：Domain 层不依赖任何外部库或框架
// 仅定义抽象契约，实现由 Infrastructure 层提供

/// 编辑器文档仓储接口（V2 白板文档持久化）
///
/// 遵循 Repository 模式：
/// - Application 层通过此接口存取文档
/// - 实现由 Infrastructure 层提供（基于 StorageService / UnifiedStorage）
/// - Domain 层零依赖（不引用 Flutter / editor_core / dart:io 等）
abstract class EditorRepository {
  /// 加载文档 JSON（若无则返回 null）
  Future<Map<String, dynamic>?> loadDocument(String documentId);

  /// 保存文档 JSON（覆盖写入）
  Future<void> saveDocument(String documentId, Map<String, dynamic> json);

  /// 列出所有文档元数据（供侧边栏 / 标题栏使用）
  Future<List<DocumentMeta>> listDocumentMeta();

  /// 删除指定文档
  Future<void> deleteDocument(String documentId);
}

/// 文档元数据（Domain 模型——不可变）
///
/// 仅包含 UI 侧边栏 / 标题栏所需的最小字段
/// 完整文档内容通过 [EditorRepository.loadDocument] 获取
class DocumentMeta {
  const DocumentMeta({
    required this.id,
    required this.title,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String title;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}
