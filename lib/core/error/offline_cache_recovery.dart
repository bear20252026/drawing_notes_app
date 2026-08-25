import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// 离线缓存恢复策略
///
/// 提供写入失败缓存、网络恢复重试、超时清理功能
class OfflineCacheRecovery {
  OfflineCacheRecovery._();

  static final OfflineCacheRecovery _instance = OfflineCacheRecovery._();
  static OfflineCacheRecovery get instance => _instance;

  /// 缓存条目过期时间（7天）
  static const Duration _expirationDuration = Duration(days: 7);

  /// 最大缓存条目数
  static const int _maxCacheSize = 1000;

  /// 重试间隔（指数退避基数）
  static const Duration _baseRetryDelay = Duration(seconds: 5);

  /// 最大重试次数
  static const int _maxRetryAttempts = 5;

  /// 缓存文件目录
  Directory? _cacheDir;

  /// 待处理的操作队列
  final List<_CacheEntry> _pendingQueue = [];

  /// 是否正在处理队列
  bool _isProcessing = false;

  /// 网络状态监听器
  bool _isOnline = true;

  /// 初始化缓存恢复服务
  Future<void> initialize() async {
    try {
      final appDir = Directory.systemTemp;
      _cacheDir = Directory('${appDir.path}/offline_cache_recovery');
      if (!await _cacheDir!.exists()) {
        await _cacheDir!.create(recursive: true);
      }
      await _loadPersistedQueue();
    } on Exception catch (e) {
      debugPrint('OfflineCacheRecovery: 初始化失败 - $e');
    }
  }

  /// 添加写入失败的操作到缓存
  ///
  /// [operationId] 操作唯一标识
  /// [operationType] 操作类型（save/delete/update）
  /// [payload] 操作数据
  /// [targetPath] 目标文件路径
  Future<void> cacheFailedOperation({
    required String operationId,
    required String operationType,
    required Map<String, dynamic> payload,
    String? targetPath,
  }) async {
    final entry = _CacheEntry(
      id: operationId,
      operationType: operationType,
      payload: payload,
      targetPath: targetPath,
      createdAt: DateTime.now(),
      retryCount: 0,
    );

    // 添加到内存队列
    _pendingQueue.add(entry);

    // 持久化到磁盘
    await _persistEntry(entry);

    // 限制缓存大小
    await _enforceMaxCacheSize();

    debugPrint('OfflineCacheRecovery: 缓存操作 $operationId ($operationType)');
  }

  /// 设置网络状态
  void setNetworkStatus(bool isOnline) {
    final wasOffline = !_isOnline;
    _isOnline = isOnline;

    // 网络恢复时自动重试
    if (isOnline && wasOffline && _pendingQueue.isNotEmpty) {
      debugPrint('OfflineCacheRecovery: 网络恢复，开始重试 ${_pendingQueue.length} 个操作');
      _processQueue();
    }
  }

  /// 手动触发队列处理
  Future<void> retryAll() async {
    if (_pendingQueue.isEmpty) return;
    await _processQueue();
  }

  /// 获取待处理操作数量
  int get pendingCount => _pendingQueue.length;

  /// 获取待处理操作列表（只读）
  List<Map<String, dynamic>> get pendingOperations =>
      _pendingQueue.map((e) => e.toJson()).toList();

  /// 清除指定操作
  Future<void> clearOperation(String operationId) async {
    _pendingQueue.removeWhere((e) => e.id == operationId);
    await _deletePersistedEntry(operationId);
  }

  /// 清除所有过期条目
  Future<int> cleanupExpired() async {
    final now = DateTime.now();
    final expired = _pendingQueue
        .where((e) => now.difference(e.createdAt) > _expirationDuration)
        .toList();

    for (final entry in expired) {
      _pendingQueue.remove(entry);
      await _deletePersistedEntry(entry.id);
    }

    if (expired.isNotEmpty) {
      debugPrint('OfflineCacheRecovery: 清理 ${expired.length} 个过期条目');
    }
    return expired.length;
  }

  /// 清除所有缓存
  Future<void> clearAll() async {
    _pendingQueue.clear();
    if (_cacheDir != null && await _cacheDir!.exists()) {
      await for (final file in _cacheDir!.list()) {
        if (file is File && file.path.endsWith('.cache')) {
          await file.delete();
        }
      }
    }
    debugPrint('OfflineCacheRecovery: 清除所有缓存');
  }

  /// 处理队列中的操作
  Future<void> _processQueue() async {
    if (_isProcessing || _pendingQueue.isEmpty) return;
    _isProcessing = true;

    try {
      // 先清理过期条目
      await cleanupExpired();

      // 复制队列以便安全迭代
      final queue = List<_CacheEntry>.from(_pendingQueue);

      for (final entry in queue) {
        if (!_isOnline) break; // 离线时停止处理

        // 检查重试次数
        if (entry.retryCount >= _maxRetryAttempts) {
          debugPrint('OfflineCacheRecovery: 操作 ${entry.id} 超过最大重试次数，丢弃');
          await clearOperation(entry.id);
          continue;
        }

        // 计算退避延迟
        final delay = _calculateBackoff(entry.retryCount);
        if (delay > Duration.zero) {
          await Future.delayed(delay);
        }

        // 执行重试
        final success = await _executeOperation(entry);

        if (success) {
          debugPrint('OfflineCacheRecovery: 操作 ${entry.id} 重试成功');
          await clearOperation(entry.id);
        } else {
          // 增加重试计数
          entry.retryCount++;
          entry.lastRetryAt = DateTime.now();
          await _persistEntry(entry);
          debugPrint(
              'OfflineCacheRecovery: 操作 ${entry.id} 重试失败 (${entry.retryCount}/$_maxRetryAttempts)');
        }
      }
    } finally {
      _isProcessing = false;
    }
  }

  /// 执行缓存的操作
  Future<bool> _executeOperation(_CacheEntry entry) async {
    try {
      switch (entry.operationType) {
        case 'save':
          return await _executeSave(entry);
        case 'delete':
          return await _executeDelete(entry);
        case 'update':
          return await _executeUpdate(entry);
        default:
          debugPrint('OfflineCacheRecovery: 未知操作类型 ${entry.operationType}');
          return false;
      }
    } on Exception catch (e) {
      debugPrint('OfflineCacheRecovery: 执行操作 ${entry.id} 异常 - $e');
      return false;
    }
  }

  /// 执行保存操作
  Future<bool> _executeSave(_CacheEntry entry) async {
    if (entry.targetPath == null) return false;

    try {
      final file = File(entry.targetPath!);
      final dir = file.parent;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final data = jsonEncode(entry.payload);
      await file.writeAsString(data);

      // 验证写入
      final content = await file.readAsString();
      return content == data;
    } on Exception {
      return false;
    }
  }

  /// 执行删除操作
  Future<bool> _executeDelete(_CacheEntry entry) async {
    if (entry.targetPath == null) return false;

    try {
      final file = File(entry.targetPath!);
      if (await file.exists()) {
        await file.delete();
      }
      return true;
    } on Exception {
      return false;
    }
  }

  /// 执行更新操作
  Future<bool> _executeUpdate(_CacheEntry entry) async {
    // 更新操作与保存操作类似（覆盖写入）
    return await _executeSave(entry);
  }

  /// 计算指数退避延迟
  Duration _calculateBackoff(int retryCount) {
    if (retryCount == 0) return Duration.zero;
    final multiplier = 1 << (retryCount - 1); // 1, 2, 4, 8, 16
    return _baseRetryDelay * multiplier;
  }

  /// 持久化条目到磁盘
  Future<void> _persistEntry(_CacheEntry entry) async {
    if (_cacheDir == null) return;

    try {
      final file = File('${_cacheDir!.path}/${entry.id}.cache');
      final data = jsonEncode(entry.toJson());
      await file.writeAsString(data);
    } on Exception catch (e) {
      debugPrint('OfflineCacheRecovery: 持久化条目 ${entry.id} 失败 - $e');
    }
  }

  /// 删除持久化条目
  Future<void> _deletePersistedEntry(String operationId) async {
    if (_cacheDir == null) return;

    try {
      final file = File('${_cacheDir!.path}/$operationId.cache');
      if (await file.exists()) {
        await file.delete();
      }
    } on Exception catch (e) {
      debugPrint('OfflineCacheRecovery: 删除持久化条目 $operationId 失败 - $e');
    }
  }

  /// 加载持久化的队列
  Future<void> _loadPersistedQueue() async {
    if (_cacheDir == null || !await _cacheDir!.exists()) return;

    try {
      await for (final file in _cacheDir!.list()) {
        if (file is File && file.path.endsWith('.cache')) {
          try {
            final content = await file.readAsString();
            final data = jsonDecode(content) as Map<String, dynamic>;
            final entry = _CacheEntry.fromJson(data);
            _pendingQueue.add(entry);
          } on Exception {
            // 损坏的缓存文件，删除
            await file.delete();
          }
        }
      }

      debugPrint('OfflineCacheRecovery: 加载 ${_pendingQueue.length} 个持久化条目');
    } on Exception catch (e) {
      debugPrint('OfflineCacheRecovery: 加载持久化队列失败 - $e');
    }
  }

  /// 限制缓存大小（移除最旧的条目）
  Future<void> _enforceMaxCacheSize() async {
    if (_pendingQueue.length <= _maxCacheSize) return;

    // 按创建时间排序，移除最旧的
    _pendingQueue.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final toRemove = _pendingQueue.length - _maxCacheSize;
    final removed = _pendingQueue.sublist(0, toRemove);

    for (final entry in removed) {
      _pendingQueue.remove(entry);
      await _deletePersistedEntry(entry.id);
    }

    debugPrint('OfflineCacheRecovery: 移除 $toRemove 个超限条目');
  }

  /// 释放资源
  void dispose() {
    _pendingQueue.clear();
  }
}

/// 缓存条目数据类
class _CacheEntry {
  _CacheEntry({
    required this.id,
    required this.operationType,
    required this.payload,
    this.targetPath,
    required this.createdAt,
    required this.retryCount,
    this.lastRetryAt,
  });

  /// 操作唯一标识
  final String id;

  /// 操作类型（save/delete/update）
  final String operationType;

  /// 操作数据
  final Map<String, dynamic> payload;

  /// 目标文件路径
  final String? targetPath;

  /// 创建时间
  final DateTime createdAt;

  /// 重试次数
  int retryCount;

  /// 最后重试时间
  DateTime? lastRetryAt;

  /// 转换为 JSON
  Map<String, dynamic> toJson() => {
        'id': id,
        'operationType': operationType,
        'payload': payload,
        'targetPath': targetPath,
        'createdAt': createdAt.toIso8601String(),
        'retryCount': retryCount,
        'lastRetryAt': lastRetryAt?.toIso8601String(),
      };

  /// 从 JSON 创建
  factory _CacheEntry.fromJson(Map<String, dynamic> json) => _CacheEntry(
        id: json['id'] as String,
        operationType: json['operationType'] as String,
        payload: json['payload'] as Map<String, dynamic>,
        targetPath: json['targetPath'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
        retryCount: json['retryCount'] as int,
        lastRetryAt: json['lastRetryAt'] != null
            ? DateTime.parse(json['lastRetryAt'] as String)
            : null,
      );
}

/// 离线缓存恢复的便捷扩展
extension OfflineCacheRecoveryExtension on OfflineCacheRecovery {
  /// 缓存写入失败的操作
  Future<void> cacheWriteFailure({
    required String documentId,
    required Map<String, dynamic> documentData,
    required String targetPath,
  }) async {
    await cacheFailedOperation(
      operationId: 'write_$documentId',
      operationType: 'save',
      payload: documentData,
      targetPath: targetPath,
    );
  }

  /// 缓存删除失败的操作
  Future<void> cacheDeleteFailure({
    required String documentId,
    required String targetPath,
  }) async {
    await cacheFailedOperation(
      operationId: 'delete_$documentId',
      operationType: 'delete',
      payload: {'documentId': documentId},
      targetPath: targetPath,
    );
  }

  /// 缓存更新失败的操作
  Future<void> cacheUpdateFailure({
    required String documentId,
    required Map<String, dynamic> documentData,
    required String targetPath,
  }) async {
    await cacheFailedOperation(
      operationId: 'update_$documentId',
      operationType: 'update',
      payload: documentData,
      targetPath: targetPath,
    );
  }
}
