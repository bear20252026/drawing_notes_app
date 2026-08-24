// editor_core——同步抽象层（AFFiNE SyncEngine 借鉴——2026-08-24）。
//
// 参考 AFFiNE SyncEngine：
// - SyncClock 三时钟模型（logical/physical/hybrid）
// - SyncProvider 接口（本地/云端/P2P）
// - 优先级队列（紧急/高/中/低）
// 纯 Dart——禁 Flutter/dart:io（R-02）。
//
// AFFiNE 原版参考（Apache-2.0）：
// - SyncEngine：同步引擎核心
// - SyncProvider：同步提供者抽象
// - SyncPriority：同步优先级
library;

import 'dart:collection';

import 'vector_clock.dart';

/// 同步优先级（AFFiNE SyncPriority 借鉴）。
enum SyncPriority {
  /// 紧急（用户正在编辑——延迟敏感）。
  urgent(0),

  /// 高（最近修改——快速同步）。
  high(1),

  /// 中（常规同步）。
  medium(2),

  /// 低（后台同步——可延迟）。
  low(3);

  const SyncPriority(this.value);
  final int value;
}

/// 同步状态。
enum SyncStatus {
  /// 空闲。
  idle,

  /// 同步中。
  syncing,

  /// 等待重试。
  waitingRetry,

  /// 错误。
  error,

  /// 离线（无连接）。
  offline,
}

/// 同步操作类型。
enum SyncOperationType {
  /// 创建文档。
  create,

  /// 更新文档。
  update,

  /// 删除文档。
  delete,

  /// 冲突解决。
  conflictResolve,
}

/// 同步操作（不可变）。
class SyncOperation {
  SyncOperation({
    required this.docId,
    required this.type,
    required this.priority,
    required this.vectorClock,
    this.data,
    this.metadata,
  }) : createdAt = DateTime.now();

  final String docId;
  final SyncOperationType type;
  final SyncPriority priority;
  final VectorClock vectorClock;
  final List<int>? data;
  final Map<String, String>? metadata;

  /// 创建时间（用于队列排序——FIFO within same priority）。
  final DateTime createdAt;
}

/// 同步结果（不可变）。
class SyncResult {
  const SyncResult.success({this.message = ''})
      : error = null, conflictData = null;
  const SyncResult.failure(this.error)
      : message = '', conflictData = null;
  const SyncResult.conflict({required this.conflictData, this.message = 'Conflict detected'})
      : error = null;

  final String message;
  final String? error;
  final List<int>? conflictData;

  bool get isSuccess => error == null && conflictData == null;
  bool get isConflict => conflictData != null;
  bool get isFailure => error != null;
}

/// 同步事件（用于监听同步状态变化）。
class SyncEvent {
  const SyncEvent({
    required this.docId,
    required this.status,
    this.error,
  });

  final String docId;
  final SyncStatus status;
  final String? error;
}

/// 同步提供者抽象接口（AFFiNE SyncProvider 借鉴）。
///
/// 实现类可以是：本地文件同步、WebDAV、云 API、P2P 等。
abstract class SyncProvider {
  /// 提供者唯一标识。
  String get providerId;

  /// 当前同步状态。
  SyncStatus get status;

  /// 推送本地变更到远程。
  Future<SyncResult> push(SyncOperation operation);

  /// 拉取远程变更到本地。
  Future<SyncResult> pull(String docId, VectorClock localClock);

  /// 检查是否有远程变更。
  Future<bool> hasRemoteChanges(String docId, VectorClock localClock);

  /// 解决冲突（本地 vs 远程）。
  Future<SyncResult> resolveConflict(
    String docId,
    List<int> localData,
    List<int> remoteData,
    VectorClock localClock,
    VectorClock remoteClock,
  );

  /// 连接/断开。
  Future<void> connect();
  Future<void> disconnect();

  /// 是否已连接。
  bool get isConnected;
}

/// 同步时钟（SyncClock——AFFiNE 三时钟模型简化版）。
///
/// 三时钟：
/// 1. logicalClock：向量时钟（因果排序）
/// 2. physicalClock：物理时间戳（人类可读）
/// 3. hybridClock：混合时钟（逻辑优先，物理兜底）
class SyncClock {
  SyncClock({required this.nodeId});

  final String nodeId;

  /// 向量时钟（因果排序）。
  VectorClock _logicalClock = VectorClock();

  /// 最后物理时间戳（毫秒）。
  int _physicalTimestamp = 0;

  /// 递增逻辑时钟（每次编辑操作）。
  void tick() {
    _logicalClock = _logicalClock.increment(nodeId);
    _physicalTimestamp = DateTime.now().millisecondsSinceEpoch;
  }

  /// 合并远程时钟（收到远程变更时）。
  void merge(VectorClock remoteClock) {
    _logicalClock = _logicalClock.merge(remoteClock);
    _physicalTimestamp = DateTime.now().millisecondsSinceEpoch;
  }

  /// 当前向量时钟（快照）。
  VectorClock get logical => _logicalClock;

  /// 当前物理时间戳。
  int get physical => _physicalTimestamp;

  /// 混合时钟值（逻辑优先，物理兜底——用于排序）。
  int get hybrid => _logicalClock.get(nodeId) * 1000000 + _physicalTimestamp % 1000000;

  /// 判断本地是否比远程更新。
  bool isLocalNewer(VectorClock remoteClock) {
    return _logicalClock.happenedBefore(remoteClock) == false &&
        _logicalClock != remoteClock;
  }

  /// 判断是否并发（冲突标志）。
  bool isConcurrent(VectorClock remoteClock) {
    return _logicalClock.isConcurrent(remoteClock);
  }
}

/// 同步优先级队列（AFFiNE SyncPriorityQueue 借鉴）。
///
/// 按优先级排序：urgent > high > medium > low。
/// 同优先级内按创建时间 FIFO。
class SyncPriorityQueue {
  final _queues = <SyncPriority, Queue<SyncOperation>>{
    for (final p in SyncPriority.values) p: Queue<SyncOperation>(),
  };

  int _count = 0;

  /// 入队。
  void enqueue(SyncOperation operation) {
    _queues[operation.priority]!.add(operation);
    _count++;
  }

  /// 出队（最高优先级的最早操作）。队列空返回 null。
  SyncOperation? dequeue() {
    for (final priority in SyncPriority.values) {
      final queue = _queues[priority]!;
      if (queue.isNotEmpty) {
        _count--;
        return queue.removeFirst();
      }
    }
    return null;
  }

  /// 队列是否为空。
  bool get isEmpty => _count == 0;

  /// 队列长度。
  int get length => _count;

  /// 清空队列。
  void clear() {
    for (final queue in _queues.values) {
      queue.clear();
    }
    _count = 0;
  }
}

/// 同步引擎（AFFiNE SyncEngine 本地化——纯 Dart 骨架）。
///
/// 当前版本提供接口和本地同步提供者（no-op）。
/// 未来可插入 WebDAV/云端/P2P 提供者。
class SyncEngine {
  SyncEngine({
    required this.nodeId,
    SyncProvider? provider,
  }) : provider = provider ?? LocalSyncProvider();

  final String nodeId;
  final SyncProvider provider;
  final _clock = SyncClock(nodeId: '');
  final _queue = SyncPriorityQueue();

  /// 当前同步状态。
  SyncStatus get status => provider.status;

  /// 提交本地变更（入队 + 推送）。
  Future<SyncResult> submitChange({
    required String docId,
    required SyncOperationType type,
    required List<int> data,
    SyncPriority priority = SyncPriority.medium,
  }) async {
    _clock.tick();
    final operation = SyncOperation(
      docId: docId,
      type: type,
      priority: priority,
      vectorClock: _clock.logical,
      data: data,
    );
    _queue.enqueue(operation);

    // 立即推送（简化版——实际可批量/延迟）。
    final op = _queue.dequeue()!;
    return provider.push(op);
  }

  /// 拉取远程变更。
  Future<SyncResult> fetchChanges(String docId) async {
    return provider.pull(docId, _clock.logical);
  }

  /// 检查是否有远程变更。
  Future<bool> hasRemoteChanges(String docId) async {
    return provider.hasRemoteChanges(docId, _clock.logical);
  }
}

/// 本地同步提供者（no-op——纯本地模式）。
///
/// 所有操作立即成功，不执行实际同步。
/// 适用于纯本地应用场景。
class LocalSyncProvider implements SyncProvider {
  @override
  String get providerId => 'local';

  @override
  SyncStatus get status => SyncStatus.idle;

  @override
  bool get isConnected => true;

  @override
  Future<void> connect() async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<SyncResult> push(SyncOperation operation) async {
    return const SyncResult.success(message: 'Local push (no-op)');
  }

  @override
  Future<SyncResult> pull(String docId, VectorClock localClock) async {
    return const SyncResult.success(message: 'Local pull (no-op)');
  }

  @override
  Future<bool> hasRemoteChanges(String docId, VectorClock localClock) async {
    return false;
  }

  @override
  Future<SyncResult> resolveConflict(
    String docId,
    List<int> localData,
    List<int> remoteData,
    VectorClock localClock,
    VectorClock remoteClock,
  ) async {
    // 本地模式：始终选择本地数据（last-write-wins）。
    return const SyncResult.success(message: 'Conflict resolved: local wins (LWW)');
  }
}
