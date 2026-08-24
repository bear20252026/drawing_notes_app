// editor_core——文档锁与冲突检测（2026-08-24）。
//
// 单文档编辑锁——防止并发编辑冲突。
// 文件级 .lock 检测——跨进程锁。
// 纯 Dart——禁 Flutter/dart:io（R-02）。
library;

import 'dart:collection';

/// 锁状态。
enum LockState {
  /// 未锁定。
  unlocked,

  /// 已锁定（当前持有者）。
  lockedByMe,

  /// 已锁定（其他持有者）。
  lockedByOther,

  /// 锁已过期。
  expired,
}

/// 锁信息（不可变）。
class LockInfo {
  const LockInfo({
    required this.docId,
    required this.holderId,
    required this.acquiredAt,
    required this.expiresAt,
    this.metadata = const {},
  });

  final String docId;
  final String holderId;
  final DateTime acquiredAt;
  final DateTime expiresAt;
  final Map<String, String> metadata;

  /// 锁是否已过期。
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// 剩余有效时长。
  Duration get remaining => isExpired ? Duration.zero : expiresAt.difference(DateTime.now());
}

/// 文档锁管理器（单文档编辑锁 + 自动过期）。
///
/// 设计要点：
/// 1. 每个文档最多一个活跃锁
/// 2. 锁有 TTL（默认 30 秒），防止进程崩溃后死锁
/// 3. 支持续期（heartbeat）——编辑中定期延长锁
/// 4. 支持强制释放（管理员/超时）
class DocumentLockManager {
  DocumentLockManager({
    this.defaultTtl = const Duration(seconds: 30),
    this.localHolderId = 'local',
  });

  /// 默认锁 TTL。
  final Duration defaultTtl;

  /// 当前进程/会话的持有者 ID。
  final String localHolderId;

  /// 活跃锁（docId → LockInfo）。
  final SplayTreeMap<String, LockInfo> _locks = {};

  /// 获取锁状态。
  LockState getState(String docId) {
    final lock = _locks[docId];
    if (lock == null) return LockState.unlocked;
    if (lock.isExpired) {
      _locks.remove(docId);
      return LockState.expired;
    }
    return lock.holderId == localHolderId
        ? LockState.lockedByMe
        : LockState.lockedByOther;
  }

  /// 尝试获取锁。成功返回 LockInfo，失败返回 null（已被他人持有）。
  LockInfo? tryAcquire(String docId, {Duration? ttl}) {
    final existing = _locks[docId];
    if (existing != null && !existing.isExpired) {
      if (existing.holderId == localHolderId) {
        // 已持有——续期。
        return _renew(docId, ttl ?? defaultTtl);
      }
      return null; // 被他人持有。
    }

    final now = DateTime.now();
    final lock = LockInfo(
      docId: docId,
      holderId: localHolderId,
      acquiredAt: now,
      expiresAt: now.add(ttl ?? defaultTtl),
    );
    _locks[docId] = lock;
    return lock;
  }

  /// 续期（heartbeat）。返回续期后的 LockInfo，锁不存在/非持有者返回 null。
  LockInfo? renew(String docId, {Duration? ttl}) {
    final lock = _locks[docId];
    if (lock == null || lock.isExpired || lock.holderId != localHolderId) {
      return null;
    }
    return _renew(docId, ttl ?? defaultTtl);
  }

  LockInfo _renew(String docId, Duration ttl) {
    final now = DateTime.now();
    final renewed = LockInfo(
      docId: docId,
      holderId: localHolderId,
      acquiredAt: _locks[docId]!.acquiredAt,
      expiresAt: now.add(ttl),
      metadata: _locks[docId]!.metadata,
    );
    _locks[docId] = renewed;
    return renewed;
  }

  /// 释放锁。只有持有者可以释放。
  bool release(String docId) {
    final lock = _locks[docId];
    if (lock == null || lock.holderId != localHolderId) return false;
    _locks.remove(docId);
    return true;
  }

  /// 强制释放锁（管理员操作）。
  void forceRelease(String docId) {
    _locks.remove(docId);
  }

  /// 清理所有过期锁。
  int purgeExpired() {
    final expired = _locks.entries.where((e) => e.value.isExpired).toList();
    for (final e in expired) {
      _locks.remove(e.key);
    }
    return expired.length;
  }

  /// 当前活跃锁数量。
  int get activeLockCount => _locks.length;

  /// 当前持有的锁。
  List<LockInfo> get myLocks =>
      _locks.values.where((l) => l.holderId == localHolderId).toList();
}

/// 冲突检测器（文件级 .lock 检测）。
///
/// 用于检测外部进程/编辑器是否正在编辑同一文档。
/// 基于约定：编辑时创建 `.lock` 文件，编辑完成删除。
class FileLockDetector {
  /// 生成 .lock 文件路径。
  static String lockPath(String docPath) => '$docPath.lock';

  /// 生成锁文件内容（持有者 + 时间戳）。
  static String generateLockContent(String holderId) {
    return '$holderId@${DateTime.now().toIso8601String()}';
  }

  /// 解析锁文件内容。返回 (holderId, timestamp)，解析失败返回 null。
  static (String, DateTime)? parseLockContent(String content) {
    final parts = content.split('@');
    if (parts.length < 2) return null;
    final timestamp = DateTime.tryParse(parts.sublist(1).join('@'));
    if (timestamp == null) return null;
    return (parts[0], timestamp);
  }

  /// 检查锁是否已过期（默认 5 分钟超时）。
  static bool isLockExpired(
    DateTime lockTimestamp, {
    Duration timeout = const Duration(minutes: 5),
  }) {
    return DateTime.now().difference(lockTimestamp) > timeout;
  }
}
