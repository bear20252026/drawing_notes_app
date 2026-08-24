// editor_core——文档锁（单文档编辑锁+.lock 文件检测——2026-08-24）。
//
// 防止并发编辑冲突：
// 1. 内存锁：单文档编辑锁（同一时刻只允许一个编辑会话）
// 2. 文件锁：.lock 文件检测（跨进程/跨设备锁）
// 3. 锁超时：自动释放过期锁（防死锁）
// 纯 Dart——禁 Flutter/dart:io（R-02）。
library;

import 'dart:collection';

/// 锁状态。
enum LockStatus {
  /// 未锁定。
  unlocked,

  /// 已锁定（当前会话持有）.
  locked,

  /// 已锁定（其他会话持有）.
  lockedByOther,

  /// 锁已过期.
  expired,
}

/// 锁信息（不可变）。
class LockInfo {
  const LockInfo({
    required this.docId,
    required this.ownerId,
    required this.lockedAt,
    this.timeout = const Duration(minutes: 30),
    this.metadata = const {},
  });

  /// 文档 ID。
  final String docId;

  /// 锁持有者 ID（设备 ID / 会话 ID）。
  final String ownerId;

  /// 锁定时间。
  final DateTime lockedAt;

  /// 锁超时时间（默认 30 分钟）。
  final Duration timeout;

  /// 附加元数据。
  final Map<String, String> metadata;

  /// 锁是否已过期。
  bool get isExpired => DateTime.now().difference(lockedAt) > timeout;

  /// 剩余时间。
  Duration get remaining => timeout - DateTime.now().difference(lockedAt);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LockInfo && docId == other.docId && ownerId == other.ownerId;

  @override
  int get hashCode => Object.hash(docId, ownerId);

  @override
  String toString() => 'LockInfo($docId, owner=$ownerId, '
      'locked=$lockedAt, timeout=$timeout)';
}

/// 文档锁管理器（内存锁+.lock 文件检测）。
///
/// 设计原则：
/// 1. 内存锁优先：同一进程内快速锁定
/// 2. 文件锁备份：跨进程/跨设备锁检测
/// 3. 超时自动释放：防死锁
/// 4. 不可变状态：锁信息不可变，状态变化返回新实例
class DocumentLockManager {
  DocumentLockManager({
    required this.nodeId,
    this.defaultTimeout = const Duration(minutes: 30),
  });

  /// 当前节点 ID（设备/会话标识）。
  final String nodeId;

  /// 默认锁超时时间。
  final Duration defaultTimeout;

  /// 内存锁表（文档 ID → 锁信息）。
  final SplayTreeMap<String, LockInfo> _locks = SplayTreeMap();

  /// 获取指定文档的锁状态。
  LockStatus getStatus(String docId) {
    final lock = _locks[docId];
    if (lock == null) return LockStatus.unlocked;
    if (lock.isExpired) {
      _locks.remove(docId);
      return LockStatus.expired;
    }
    if (lock.ownerId == nodeId) return LockStatus.locked;
    return LockStatus.lockedByOther;
  }

  /// 尝试锁定文档。
  ///
  /// 返回锁定是否成功。
  /// 如果文档已被其他节点锁定，返回 false。
  bool tryLock(String docId, {Duration? timeout, Map<String, String>? metadata}) {
    final status = getStatus(docId);
    if (status == LockStatus.lockedByOther) return false;
    if (status == LockStatus.locked) return true; // 已经持有锁

    _locks[docId] = LockInfo(
      docId: docId,
      ownerId: nodeId,
      lockedAt: DateTime.now(),
      timeout: timeout ?? defaultTimeout,
      metadata: metadata ?? {},
    );
    return true;
  }

  /// 释放文档锁。
  ///
  /// 只有锁持有者才能释放锁。
  /// 返回释放是否成功。
  bool unlock(String docId) {
    final lock = _locks[docId];
    if (lock == null) return true; // 未锁定
    if (lock.ownerId != nodeId) return false; // 非持有者

    _locks.remove(docId);
    return true;
  }

  /// 强制释放文档锁（管理员操作）。
  ///
  /// 无论锁持有者是谁，都释放锁。
  /// 用于处理异常情况（如锁持有者崩溃）。
  void forceUnlock(String docId) {
    _locks.remove(docId);
  }

  /// 获取锁信息。
  LockInfo? getLockInfo(String docId) {
    final lock = _locks[docId];
    if (lock == null) return null;
    if (lock.isExpired) {
      _locks.remove(docId);
      return null;
    }
    return lock;
  }

  /// 获取所有活跃锁。
  List<LockInfo> getActiveLocks() {
    _purgeExpired();
    return _locks.values.toList();
  }

  /// 获取当前节点持有的所有锁。
  List<LockInfo> getMyLocks() {
    _purgeExpired();
    return _locks.values.where((lock) => lock.ownerId == nodeId).toList();
  }

  /// 清理过期锁。
  void _purgeExpired() {
    _locks.removeWhere((_, lock) => lock.isExpired);
  }

  /// 清理所有锁。
  void clear() {
    _locks.clear();
  }

  /// 生成 .lock 文件内容（JSON 格式）。
  ///
  /// 用于跨进程/跨设备锁检测。
  String generateLockFileContent(String docId) {
    final lock = _locks[docId];
    if (lock == null) return '{}';

    return '''
{
  "docId": "${lock.docId}",
  "ownerId": "${lock.ownerId}",
  "lockedAt": "${lock.lockedAt.toIso8601String()}",
  "timeout": ${lock.timeout.inSeconds},
  "metadata": ${_serializeMetadata(lock.metadata)}
}''';
  }

  /// 解析 .lock 文件内容。
  ///
  /// 返回锁信息，解析失败返回 null。
  LockInfo? parseLockFileContent(String docId, String content) {
    try {
      // 简化版 JSON 解析（实际应使用 jsonDecode）
      final ownerId = _extractJsonString(content, 'ownerId');
      final lockedAtStr = _extractJsonString(content, 'lockedAt');
      final timeoutSeconds = _extractJsonInt(content, 'timeout');

      if (ownerId == null || lockedAtStr == null) return null;

      final lockedAt = DateTime.tryParse(lockedAtStr);
      if (lockedAt == null) return null;

      return LockInfo(
        docId: docId,
        ownerId: ownerId,
        lockedAt: lockedAt,
        timeout: Duration(seconds: timeoutSeconds ?? 1800),
      );
    } catch (_) {
      return null;
    }
  }

  /// 序列化元数据。
  String _serializeMetadata(Map<String, String> metadata) {
    if (metadata.isEmpty) return '{}';
    final entries = metadata.entries
        .map((e) => '"${e.key}": "${e.value}"')
        .join(', ');
    return '{ $entries }';
  }

  /// 提取 JSON 字符串值（简化版）。
  String? _extractJsonString(String json, String key) {
    final pattern = RegExp('"$key"\\s*:\\s*"([^"]*)"');
    final match = pattern.firstMatch(json);
    return match?.group(1);
  }

  /// 提取 JSON 整数值（简化版）。
  int? _extractJsonInt(String json, String key) {
    final pattern = RegExp('"$key"\\s*:\\s*(\\d+)');
    final match = pattern.firstMatch(json);
    return match != null ? int.tryParse(match.group(1)!) : null;
  }
}
