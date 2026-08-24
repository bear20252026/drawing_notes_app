// storage_adapter.dart — StorageService → UnifiedStorage 桥接适配器（2026-08-24）。
//
// 架构：
// - StorageService（旧）：基于文件的简单存储，无版本向量/锁/同步
// - UnifiedStorageService（新）：多后端可插拔，版本向量/文档锁/同步抽象
// - StorageAdapter：桥接层——将旧 StorageService 适配为 UnifiedStorageService
//
// 迁移策略：
// 1. 渐进式迁移——旧代码继续使用 StorageService
// 2. 新代码使用 UnifiedStorageService（通过 StorageAdapter）
// 3. 逐步替换调用点，最终废弃 StorageService
//
// 纯 Dart——禁 Flutter/dart:io（R-02）。

import 'dart:convert';
import 'dart:typed_data';

import 'document_lock.dart';
import 'legacy_storage_interface.dart';
import 'schema_version.dart';
import 'storage_backend.dart';
import 'sync_provider.dart';
import 'unified_storage.dart';
import 'vector_clock.dart';

/// StorageService → UnifiedStorage 桥接适配器。
///
/// 将旧 StorageService 适配为 UnifiedStorageService 接口。
/// 支持：
/// - Schema 版本管理 + 自动迁移
/// - 数据完整性 SHA-256 校验
/// - 版本向量（CRDT 预留）
class StorageAdapter implements UnifiedStorageService {
  StorageAdapter({
    required this.storageService,
    required this.nodeId,
    SchemaMigrationManager? migrationManager,
  }) : _migrationManager = migrationManager ?? SchemaMigrationManager();

  final LegacyStorageService storageService;
  final String nodeId;
  final SchemaMigrationManager _migrationManager;

  /// 文档版本向量缓存。
  final Map<String, VectorClock> _versionCache = {};

  @override
  String get serviceId => 'storage-adapter';

  @override
  StorageBackend get currentBackend => _StorageServiceBackend(storageService);

  @override
  Future<void> switchBackend(StorageBackend backend) async {
    // StorageAdapter 不支持切换后端——它包装的是固定的 StorageService。
    throw UnsupportedError('StorageAdapter 不支持切换后端');
  }

  @override
  Future<UnifiedStorageResult<void>> initialize() async {
    // StorageService 无需显式初始化。
    return const UnifiedStorageResult.success(null);
  }

  @override
  Future<void> close() async {
    _versionCache.clear();
  }

  @override
  Future<UnifiedStorageResult<void>> saveDoc(
    String docId,
    Uint8List data, {
    VectorClock? vectorClock,
  }) async {
    try {
      // 解析 JSON 数据。
      final json = jsonDecode(utf8.decode(data)) as Map<String, dynamic>;

      // 迁移到最新 Schema 版本。
      final migrated = _migrationManager.migrateToLatest(json);

      // 计算数据完整性哈希。
      final integrityHash = DataIntegrityChecker.hashDocument(migrated);
      migrated['dataIntegrityHash'] = integrityHash;

      // 更新版本向量。
      final currentClock = _versionCache[docId] ?? VectorClock();
      final updatedClock = (vectorClock ?? currentClock).increment(nodeId);
      _versionCache[docId] = updatedClock;

      // 添加版本向量到数据。
      migrated['vectorClock'] = {
        'clocks': updatedClock.toMap(),
      };

      // 保存到 StorageService。
      final doc = LegacyDocument.fromJson(migrated);
      await storageService.save(doc);

      return UnifiedStorageResult.success(null, vectorClock: updatedClock);
    } catch (e) {
      return UnifiedStorageResult.failure('保存文档失败: $e');
    }
  }

  @override
  Future<UnifiedStorageResult<Uint8List?>> loadDoc(String docId) async {
    try {
      final doc = await storageService.load(docId);
      if (doc == null) {
        return const UnifiedStorageResult.success(null);
      }

      // 转换为 JSON。
      final json = doc.toJson();

      // 验证数据完整性。
      if (!DataIntegrityChecker.verifyDocument(json)) {
        return UnifiedStorageResult.failure('数据完整性校验失败');
      }

      // 迁移到最新 Schema 版本（如果需要）。
      if (_migrationManager.needsMigration(json)) {
        final migrated = _migrationManager.migrateToLatest(json);
        final data = utf8.encode(jsonEncode(migrated));
        return UnifiedStorageResult.success(
          Uint8List.fromList(data),
          vectorClock: _versionCache[docId],
        );
      }

      final data = utf8.encode(jsonEncode(json));
      return UnifiedStorageResult.success(
        Uint8List.fromList(data),
        vectorClock: _versionCache[docId],
      );
    } catch (e) {
      return UnifiedStorageResult.failure('加载文档失败: $e');
    }
  }

  @override
  Future<UnifiedStorageResult<void>> deleteDoc(String docId) async {
    try {
      await storageService.delete(docId);
      _versionCache.remove(docId);
      return const UnifiedStorageResult.success(null);
    } catch (e) {
      return UnifiedStorageResult.failure('删除文档失败: $e');
    }
  }

  @override
  Future<UnifiedStorageResult<List<DocumentVersion>>> listDocs() async {
    try {
      final docs = await storageService.listDocuments();
      final versions = docs.map((meta) {
        final clock = _versionCache[meta.id] ?? VectorClock();
        return DocumentVersion(
          docId: meta.id,
          vectorClock: clock,
          lastModified: meta.updatedAt,
          sizeBytes: meta.sizeBytes,
        );
      }).toList();

      return UnifiedStorageResult.success(versions);
    } catch (e) {
      return UnifiedStorageResult.failure('列出文档失败: $e');
    }
  }

  @override
  Future<bool> docExists(String docId) async {
    try {
      final doc = await storageService.load(docId);
      return doc != null;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<UnifiedStorageResult<void>> saveBlob(
    String key,
    Uint8List data,
    String contentType,
  ) async {
    // StorageService 不支持 Blob 存储——返回失败。
    return UnifiedStorageResult.failure('StorageService 不支持 Blob 存储');
  }

  @override
  Future<UnifiedStorageResult<Uint8List?>> loadBlob(String key) async {
    return UnifiedStorageResult.failure('StorageService 不支持 Blob 存储');
  }

  @override
  Future<UnifiedStorageResult<void>> deleteBlob(String key) async {
    return UnifiedStorageResult.failure('StorageService 不支持 Blob 存储');
  }

  @override
  Future<UnifiedStorageResult<bool>> tryLockDoc(
    String docId, {
    Duration? timeout,
  }) async {
    // StorageService 不支持文档锁——始终返回成功。
    return const UnifiedStorageResult.success(true);
  }

  @override
  Future<UnifiedStorageResult<bool>> unlockDoc(String docId) async {
    return const UnifiedStorageResult.success(true);
  }

  @override
  Future<UnifiedStorageResult<LockStatus>> getLockStatus(String docId) async {
    return const UnifiedStorageResult.success(LockStatus.unlocked);
  }

  @override
  Future<UnifiedStorageResult<void>> submitChange(
    String docId,
    SyncOperationType type,
  ) async {
    // StorageService 不支持同步——静默成功。
    return const UnifiedStorageResult.success(null);
  }

  @override
  Future<UnifiedStorageResult<void>> fetchChanges(String docId) async {
    return const UnifiedStorageResult.success(null);
  }

  @override
  Future<bool> hasRemoteChanges(String docId) async {
    return false;
  }
}

/// StorageService → StorageBackend 适配器。
///
/// 将旧 StorageService 适配为 StorageBackend 接口。
class _StorageServiceBackend implements StorageBackend {
  _StorageServiceBackend(this._storageService);

  final LegacyStorageService _storageService;

  @override
  String get backendId => 'storage-service';

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<StorageResult<void>> saveDoc(String docId, Uint8List data) async {
    try {
      final json = jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
      final doc = LegacyDocument.fromJson(json);
      await _storageService.save(doc);
      return const StorageResult.success(null);
    } catch (e) {
      return StorageResult.failure('保存文档失败: $e');
    }
  }

  @override
  Future<StorageResult<Uint8List?>> loadDoc(String docId) async {
    try {
      final doc = await _storageService.load(docId);
      if (doc == null) {
        return const StorageResult.success(null);
      }
      final data = utf8.encode(jsonEncode(doc.toJson()));
      return StorageResult.success(Uint8List.fromList(data));
    } catch (e) {
      return StorageResult.failure('加载文档失败: $e');
    }
  }

  @override
  Future<StorageResult<void>> deleteDoc(String docId) async {
    try {
      await _storageService.delete(docId);
      return const StorageResult.success(null);
    } catch (e) {
      return StorageResult.failure('删除文档失败: $e');
    }
  }

  @override
  Future<StorageResult<List<DocMetadata>>> listDocs() async {
    try {
      final docs = await _storageService.listDocuments();
      final metadata = docs.map((meta) => DocMetadata(
        id: meta.id,
        title: meta.name,
        createdAt: meta.createdAt,
        updatedAt: meta.updatedAt,
        sizeBytes: meta.sizeBytes,
      )).toList();
      return StorageResult.success(metadata);
    } catch (e) {
      return StorageResult.failure('列出文档失败: $e');
    }
  }

  @override
  Future<bool> docExists(String docId) async {
    try {
      final doc = await _storageService.load(docId);
      return doc != null;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<StorageResult<void>> saveBlob(
    String key,
    Uint8List data,
    String contentType,
  ) async {
    return StorageResult.failure('StorageService 不支持 Blob 存储');
  }

  @override
  Future<StorageResult<Uint8List?>> loadBlob(String key) async {
    return StorageResult.failure('StorageService 不支持 Blob 存储');
  }

  @override
  Future<StorageResult<void>> deleteBlob(String key) async {
    return StorageResult.failure('StorageService 不支持 Blob 存储');
  }

  @override
  Future<StorageResult<List<BlobMetadata>>> listBlobs() async {
    return StorageResult.failure('StorageService 不支持 Blob 存储');
  }

  @override
  Future<StorageResult<void>> initialize() async {
    return const StorageResult.success(null);
  }

  @override
  Future<void> close() async {
    // StorageService 无需显式关闭。
  }
}
