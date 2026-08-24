// editor_core——统一存储服务（可插拔存储——AFFiNE SpaceStorage 借鉴——2026-08-24）。
//
// 参考 AFFiNE SpaceStorage：
// - 多后端可插拔（本地/内存/SQLite/云端）
// - 统一 StorageService 接口
// - 版本向量集成（CRDT 预留）
// 纯 Dart——禁 Flutter/dart:io（R-02）。
library;

import 'dart:typed_data';

import 'storage_backend.dart';
import 'vector_clock.dart';
import 'sync_provider.dart';
import 'document_lock.dart';

/// 统一存储操作结果（不可变）。
class UnifiedStorageResult<T> {
  const UnifiedStorageResult.success(this.data, {this.vectorClock})
      : error = null;
  const UnifiedStorageResult.failure(this.error)
      : data = null, vectorClock = null;

  final T? data;
  final String? error;
  final VectorClock? vectorClock;

  bool get isSuccess => error == null;
  bool get isFailure => error != null;
}

/// 文档版本信息（CRDT 预留）。
class DocumentVersion {
  const DocumentVersion({
    required this.docId,
    required this.vectorClock,
    required this.lastModified,
    this.sizeBytes = 0,
  });

  final String docId;
  final VectorClock vectorClock;
  final DateTime lastModified;
  final int sizeBytes;
}

/// 统一存储服务接口（AFFiNE SpaceStorage 借鉴）。
///
/// 抽象层：隐藏具体存储后端实现，提供统一 API。
/// 支持：
/// 1. 多后端可插拔（本地/内存/SQLite/云端）
/// 2. 版本向量（CRDT 预留）
/// 3. 文档锁（并发控制）
/// 4. 同步抽象（本地/云端/P2P）
abstract class UnifiedStorageService {
  /// 存储服务 ID。
  String get serviceId;

  /// 当前使用的后端。
  StorageBackend get currentBackend;

  /// 切换存储后端。
  Future<void> switchBackend(StorageBackend backend);

  /// 初始化存储服务。
  Future<UnifiedStorageResult<void>> initialize();

  /// 关闭存储服务。
  Future<void> close();

  // ── 文档操作（带版本向量） ──

  /// 保存文档（带版本向量）。
  Future<UnifiedStorageResult<void>> saveDoc(
    String docId,
    Uint8List data, {
    VectorClock? vectorClock,
  });

  /// 加载文档（带版本向量）。
  Future<UnifiedStorageResult<Uint8List?>> loadDoc(String docId);

  /// 删除文档。
  Future<UnifiedStorageResult<void>> deleteDoc(String docId);

  /// 列出所有文档（带版本信息）。
  Future<UnifiedStorageResult<List<DocumentVersion>>> listDocs();

  /// 检查文档是否存在。
  Future<bool> docExists(String docId);

  // ── Blob 操作 ──

  /// 保存二进制 Blob。
  Future<UnifiedStorageResult<void>> saveBlob(
    String key,
    Uint8List data,
    String contentType,
  );

  /// 加载二进制 Blob。
  Future<UnifiedStorageResult<Uint8List?>> loadBlob(String key);

  /// 删除二进制 Blob。
  Future<UnifiedStorageResult<void>> deleteBlob(String key);

  // ── 文档锁操作 ──

  /// 尝试锁定文档。
  Future<UnifiedStorageResult<bool>> tryLockDoc(
    String docId, {
    Duration? timeout,
  });

  /// 释放文档锁。
  Future<UnifiedStorageResult<bool>> unlockDoc(String docId);

  /// 获取文档锁状态。
  Future<UnifiedStorageResult<LockStatus>> getLockStatus(String docId);

  // ── 同步操作 ──

  /// 提交本地变更到同步队列。
  Future<UnifiedStorageResult<void>> submitChange(
    String docId,
    SyncOperationType type,
  );

  /// 拉取远程变更。
  Future<UnifiedStorageResult<void>> fetchChanges(String docId);

  /// 检查是否有远程变更。
  Future<bool> hasRemoteChanges(String docId);
}

/// 本地文件存储服务实现（当前版本）。
///
/// 基于 StorageBackend 的统一存储服务。
/// 版本向量仅记录，不执行 CRDT 合并。
class LocalUnifiedStorageService implements UnifiedStorageService {
  LocalUnifiedStorageService({
    required this.nodeId,
    required StorageBackend backend,
    SyncProvider? syncProvider,
  }) : _backend = backend,
       _syncProvider = syncProvider ?? LocalSyncProvider(),
       _lockManager = DocumentLockManager(nodeId: nodeId);

  final String nodeId;
  StorageBackend _backend;
  final SyncProvider _syncProvider;
  final DocumentLockManager _lockManager;

  /// 文档版本向量缓存。
  final Map<String, VectorClock> _versionCache = {};

  @override
  String get serviceId => 'local-unified';

  @override
  StorageBackend get currentBackend => _backend;

  @override
  Future<void> switchBackend(StorageBackend backend) async {
    await _backend.close();
    _backend = backend;
    await _backend.initialize();
  }

  @override
  Future<UnifiedStorageResult<void>> initialize() async {
    final result = await _backend.initialize();
    if (result.isFailure) {
      return UnifiedStorageResult.failure(result.error);
    }
    await _syncProvider.connect();
    return const UnifiedStorageResult.success(null);
  }

  @override
  Future<void> close() async {
    await _syncProvider.disconnect();
    await _backend.close();
    _versionCache.clear();
    _lockManager.clear();
  }

  @override
  Future<UnifiedStorageResult<void>> saveDoc(
    String docId,
    Uint8List data, {
    VectorClock? vectorClock,
  }) async {
    // 检查锁状态
    final lockStatus = _lockManager.getStatus(docId);
    if (lockStatus == LockStatus.lockedByOther) {
      return UnifiedStorageResult.failure(
        'Document locked by another session',
      );
    }

    // 更新版本向量
    final currentClock = _versionCache[docId] ?? VectorClock();
    final updatedClock = (vectorClock ?? currentClock).increment(nodeId);
    _versionCache[docId] = updatedClock;

    // 保存到后端
    final result = await _backend.saveDoc(docId, data);
    if (result.isFailure) {
      return UnifiedStorageResult.failure(result.error);
    }

    // 提交同步变更
    await _syncProvider.push(SyncOperation(
      docId: docId,
      type: SyncOperationType.update,
      priority: SyncPriority.medium,
      vectorClock: updatedClock,
      data: data,
    ));

    return UnifiedStorageResult.success(null, vectorClock: updatedClock);
  }

  @override
  Future<UnifiedStorageResult<Uint8List?>> loadDoc(String docId) async {
    final result = await _backend.loadDoc(docId);
    if (result.isFailure) {
      return UnifiedStorageResult.failure(result.error);
    }

    return UnifiedStorageResult.success(
      result.data,
      vectorClock: _versionCache[docId],
    );
  }

  @override
  Future<UnifiedStorageResult<void>> deleteDoc(String docId) async {
    // 检查锁状态
    final lockStatus = _lockManager.getStatus(docId);
    if (lockStatus == LockStatus.lockedByOther) {
      return UnifiedStorageResult.failure(
        'Document locked by another session',
      );
    }

    // 释放锁
    _lockManager.unlock(docId);

    // 删除文档
    final result = await _backend.deleteDoc(docId);
    if (result.isFailure) {
      return UnifiedStorageResult.failure(result.error);
    }

    // 清理版本缓存
    _versionCache.remove(docId);

    // 提交同步变更
    await _syncProvider.push(SyncOperation(
      docId: docId,
      type: SyncOperationType.delete,
      priority: SyncPriority.medium,
      vectorClock: VectorClock(),
    ));

    return const UnifiedStorageResult.success(null);
  }

  @override
  Future<UnifiedStorageResult<List<DocumentVersion>>> listDocs() async {
    final result = await _backend.listDocs();
    if (result.isFailure) {
      return UnifiedStorageResult.failure(result.error);
    }

    final versions = result.data!.map((meta) {
      final clock = _versionCache[meta.id] ?? VectorClock();
      return DocumentVersion(
        docId: meta.id,
        vectorClock: clock,
        lastModified: meta.updatedAt,
        sizeBytes: meta.sizeBytes,
      );
    }).toList();

    return UnifiedStorageResult.success(versions);
  }

  @override
  Future<bool> docExists(String docId) => _backend.docExists(docId);

  @override
  Future<UnifiedStorageResult<void>> saveBlob(
    String key,
    Uint8List data,
    String contentType,
  ) async {
    final result = await _backend.saveBlob(key, data, contentType);
    if (result.isFailure) {
      return UnifiedStorageResult.failure(result.error);
    }
    return const UnifiedStorageResult.success(null);
  }

  @override
  Future<UnifiedStorageResult<Uint8List?>> loadBlob(String key) async {
    final result = await _backend.loadBlob(key);
    if (result.isFailure) {
      return UnifiedStorageResult.failure(result.error);
    }
    return UnifiedStorageResult.success(result.data);
  }

  @override
  Future<UnifiedStorageResult<void>> deleteBlob(String key) async {
    final result = await _backend.deleteBlob(key);
    if (result.isFailure) {
      return UnifiedStorageResult.failure(result.error);
    }
    return const UnifiedStorageResult.success(null);
  }

  @override
  Future<UnifiedStorageResult<bool>> tryLockDoc(
    String docId, {
    Duration? timeout,
  }) async {
    final success = _lockManager.tryLock(docId, timeout: timeout);
    return UnifiedStorageResult.success(success);
  }

  @override
  Future<UnifiedStorageResult<bool>> unlockDoc(String docId) async {
    final success = _lockManager.unlock(docId);
    return UnifiedStorageResult.success(success);
  }

  @override
  Future<UnifiedStorageResult<LockStatus>> getLockStatus(String docId) async {
    final status = _lockManager.getStatus(docId);
    return UnifiedStorageResult.success(status);
  }

  @override
  Future<UnifiedStorageResult<void>> submitChange(
    String docId,
    SyncOperationType type,
  ) async {
    final clock = _versionCache[docId] ?? VectorClock();
    await _syncProvider.push(SyncOperation(
      docId: docId,
      type: type,
      priority: SyncPriority.medium,
      vectorClock: clock,
    ));
    return const UnifiedStorageResult.success(null);
  }

  @override
  Future<UnifiedStorageResult<void>> fetchChanges(String docId) async {
    final clock = _versionCache[docId] ?? VectorClock();
    final result = await _syncProvider.pull(docId, clock);
    if (result.isFailure) {
      return UnifiedStorageResult.failure(result.error);
    }
    return const UnifiedStorageResult.success(null);
  }

  @override
  Future<bool> hasRemoteChanges(String docId) async {
    final clock = _versionCache[docId] ?? VectorClock();
    return _syncProvider.hasRemoteChanges(docId, clock);
  }
}
