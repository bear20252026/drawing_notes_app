// editor_core——可插拔存储后端抽象（AFFiNE SpaceStorage 借鉴——2026-08-24）。
//
// 参考 AFFiNE SpaceStorage：多后端可插拔，统一 StorageBackend 接口。
// 参考 Saber VFS：JSON index + 二进制文档分离。
// 纯 Dart——禁 Flutter/dart:io（R-02）。
//
// AFFiNE 原版参考（Apache-2.0）：
// - SpaceStorage：多后端注册/切换/统一读写
// - BlobStorage：二进制大对象存储
// - DocStorage：文档 CRDT 存储
library;

import 'dart:typed_data';

/// 存储操作结果（不可变）。
class StorageResult<T> {
  const StorageResult.success(this.data) : error = null;
  const StorageResult.failure(this.error) : data = null;

  final T? data;
  final String? error;

  bool get isSuccess => error == null;
  bool get isFailure => error != null;
}

/// 文档元数据（轻量级列表展示——不含完整数据）。
class DocMetadata {
  const DocMetadata({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.sizeBytes = 0,
    this.tags = const [],
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int sizeBytes;
  final List<String> tags;
}

/// Blob 元数据（二进制大对象）。
class BlobMetadata {
  const BlobMetadata({
    required this.key,
    required this.sizeBytes,
    required this.contentType,
    required this.createdAt,
  });

  final String key;
  final int sizeBytes;
  final String contentType;
  final DateTime createdAt;
}

/// 存储后端抽象接口（AFFiNE SpaceStorage 借鉴）。
///
/// 统一文档和二进制数据的存储操作。
/// 实现类可以是：本地文件、内存（测试）、SQLite、云端 API 等。
abstract class StorageBackend {
  /// 后端唯一标识（如 'local-file', 'memory', 'sqlite', 'cloud'）。
  String get backendId;

  /// 后端是否可用（如网络连接检查、文件系统权限检查）。
  Future<bool> isAvailable();

  // ── 文档操作 ──

  /// 保存文档（JSON 编码的字节）。
  Future<StorageResult<void>> saveDoc(String docId, Uint8List data);

  /// 加载文档。不存在返回 success(null)。
  Future<StorageResult<Uint8List?>> loadDoc(String docId);

  /// 删除文档。
  Future<StorageResult<void>> deleteDoc(String docId);

  /// 列出所有文档元数据。
  Future<StorageResult<List<DocMetadata>>> listDocs();

  /// 检查文档是否存在。
  Future<bool> docExists(String docId);

  // ── Blob 操作（Saber VFS：二进制附件分离存储） ──

  /// 保存二进制 Blob（图片、音频等）。
  Future<StorageResult<void>> saveBlob(String key, Uint8List data, String contentType);

  /// 加载二进制 Blob。不存在返回 success(null)。
  Future<StorageResult<Uint8List?>> loadBlob(String key);

  /// 删除二进制 Blob。
  Future<StorageResult<void>> deleteBlob(String key);

  /// 列出所有 Blob 元数据。
  Future<StorageResult<List<BlobMetadata>>> listBlobs();

  // ── 生命周期 ──

  /// 初始化后端（创建目录、建表等）。
  Future<StorageResult<void>> initialize();

  /// 关闭后端（释放资源）。
  Future<void> close();
}

/// 存储后端注册表（AFFiNE SpaceStorage 注册机制借鉴）。
///
/// 管理多个存储后端的注册和解析。
/// 支持默认后端和按名称查询。
class StorageBackendRegistry {
  StorageBackendRegistry({StorageBackend? defaultBackend})
      : _defaultBackendId = defaultBackend?.backendId ?? '';

  final Map<String, StorageBackend> _backends = {};
  String _defaultBackendId;

  /// 注册后端。
  void register(StorageBackend backend) {
    _backends[backend.backendId] = backend;
  }

  /// 注销后端。
  void unregister(String backendId) {
    _backends.remove(backendId);
    if (_defaultBackendId == backendId) {
      _defaultBackendId = _backends.isNotEmpty ? _backends.keys.first : '';
    }
  }

  /// 获取后端。不存在返回 null。
  StorageBackend? get(String backendId) => _backends[backendId];

  /// 获取默认后端。未设置时返回第一个注册的后端。
  StorageBackend? get defaultBackend =>
      _backends[_defaultBackendId] ?? _backends.values.firstOrNull;

  /// 设置默认后端。
  void setDefault(String backendId) {
    if (_backends.containsKey(backendId)) {
      _defaultBackendId = backendId;
    }
  }

  /// 所有已注册后端 ID。
  List<String> get registeredIds => _backends.keys.toList();

  /// 已注册后端数量。
  int get count => _backends.length;

  /// 检查后端是否已注册。
  bool contains(String backendId) => _backends.containsKey(backendId);
}
