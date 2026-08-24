// editor_core——向量时钟（CRDT 预留——AFFiNE y-octo 借鉴——2026-08-24）。
//
// 参考 AFFiNE y-octo (MIT)：CRDT 文档模型的版本向量。
// 为未来 CRDT 合并预留字段——当前版本仅记录，不执行合并。
// 纯 Dart——禁 Flutter/dart:io（R-02）。
//
// AFFiNE 原版参考（MIT）：
// - y-octo：Yjs 兼容 CRDT 实现
// - VersionVector：逻辑时钟用于因果排序
library;

import 'dart:collection';

/// 向量时钟节点（逻辑时钟——Lamport Clock 扩展）。
///
/// 每个节点代表一个编辑者（设备/会话），时钟值单调递增。
/// 用于判断事件的因果关系（happened-before）。
class VectorClockNode {
  const VectorClockNode({required this.nodeId, required this.clock});

  /// 节点唯一标识（设备 ID / 会话 ID）。
  final String nodeId;

  /// 该节点的逻辑时钟值（单调递增——每次编辑 +1）。
  final int clock;

  /// 递增时钟。
  VectorClockNode increment() => VectorClockNode(nodeId: nodeId, clock: clock + 1);

  @override
  bool operator ==(Object other) =>
      other is VectorClockNode && nodeId == other.nodeId && clock == other.clock;

  @override
  int get hashCode => Object.hash(nodeId, clock);

  @override
  String toString() => '$nodeId:$clock';
}

/// 向量时钟（Vector Clock——CRDT 版本向量预留）。
///
/// 记录每个编辑节点的逻辑时钟，用于：
/// 1. 因果排序：判断操作的先后关系
/// 2. 冲突检测：并发编辑识别
/// 3. CRDT 合并：未来 y-octo 集成的基础
///
/// 当前版本仅记录，不执行 CRDT 合并。
class VectorClock {
  VectorClock([Map<String, int>? clocks])
      : _clocks = SplayTreeMap<String, int>.from(clocks ?? {});

  final SplayTreeMap<String, int> _clocks;

  /// 获取指定节点的时钟值。不存在返回 0。
  int get(String nodeId) => _clocks[nodeId] ?? 0;

  /// 递增指定节点的时钟（返回新实例——不可变约定）。
  VectorClock increment(String nodeId) {
    final updated = Map<String, int>.from(_clocks);
    updated[nodeId] = (updated[nodeId] ?? 0) + 1;
    return VectorClock(updated);
  }

  /// 合并两个向量时钟（取每个节点的最大值——CRDT join 操作）。
  ///
  /// 这是 CRDT 合并的基础操作：对于每个节点，
  /// 合并后的时钟 = max(本地时钟, 远程时钟)。
  VectorClock merge(VectorClock other) {
    final merged = Map<String, int>.from(_clocks);
    for (final entry in other._clocks.entries) {
      merged[entry.key] = (merged[entry.key] ?? 0) > entry.value
          ? merged[entry.key]!
          : entry.value;
    }
    return VectorClock(merged);
  }

  /// 判断 [other] 是否发生在 [this] 之前（严格因果序）。
  ///
  /// other < this 当且仅当：
  /// - 所有节点 other.clock <= this.clock
  /// - 至少一个节点 other.clock < this.clock
  bool happenedBefore(VectorClock other) {
    var hasStrictlyLess = false;
    final allNodes = {..._clocks.keys, ...other._clocks.keys};
    for (final node in allNodes) {
      final a = _clocks[node] ?? 0;
      final b = other._clocks[node] ?? 0;
      if (b > a) return false; // other 有节点更大 → 不是 before
      if (b < a) hasStrictlyLess = true;
    }
    return hasStrictlyLess;
  }

  /// 判断两个时钟是否并发（不可比较——冲突标志）。
  ///
  /// 并发 = neither happenedBefore the other。
  bool isConcurrent(VectorClock other) {
    return !happenedBefore(other) && !other.happenedBefore(this) && this != other;
  }

  /// 所有节点 ID。
  Set<String> get nodeIds => _clocks.keys.toSet();

  /// 时钟是否为空。
  bool get isEmpty => _clocks.isEmpty;

  /// 节点数量。
  int get length => _clocks.length;

  /// 转换为不可变 Map。
  Map<String, int> toMap() => Map.unmodifiable(_clocks);

  @override
  bool operator ==(Object other) {
    if (other is! VectorClock || _clocks.length != other._clocks.length) {
      return false;
    }
    for (final entry in _clocks.entries) {
      if (other._clocks[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode {
    var hash = 0;
    for (final entry in _clocks.entries) {
      hash ^= Object.hash(entry.key, entry.value);
    }
    return hash;
  }

  @override
  String toString() => '{${_clocks.entries.map((e) => '${e.key}:${e.value}').join(', ')}}';
}
