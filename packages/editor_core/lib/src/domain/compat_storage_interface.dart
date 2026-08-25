// compat_storage_interface.dart — 兼容存储服务抽象接口（2026-08-25）。
//
// 存储适配器使用此接口与主应用 StorageService 交互，
// 避免 editor_core 包直接依赖 drawing_notes_app（循环依赖）。
//
// 主应用需实现此接口并注入到 StorageAdapter。
// 纯 Dart——禁 Flutter/dart:io（R-02）。

/// 兼容存储服务抽象接口（StorageService 的纯 Dart 替代）。
///
/// 主应用的 StorageService 需要实现此接口。
abstract class CompatStorageService {
  /// 保存文档。
  Future<void> save(CompatDocument doc);

  /// 加载文档。
  Future<CompatDocument?> load(String docId);

  /// 删除文档。
  Future<void> delete(String docId);

  /// 列出所有文档元数据。
  Future<List<CompatDocumentMeta>> listDocuments();
}

/// 兼容文档数据类（DrawingDocument 的纯 Dart 替代）。
class CompatDocument {
  const CompatDocument({required this.id, required this.data});

  final String id;
  final Map<String, dynamic> data;

  factory CompatDocument.fromJson(Map<String, dynamic> json) =>
      CompatDocument(
        id: json['id'] as String,
        data: json,
      );

  Map<String, dynamic> toJson() => data;
}

/// 兼容文档元数据（DocumentMetadata 的纯 Dart 替代）。
class CompatDocumentMeta {
  const CompatDocumentMeta({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.sizeBytes = 0,
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int sizeBytes;
}
