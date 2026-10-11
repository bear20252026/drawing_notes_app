import 'dart:convert';

import 'package:drawing_notes_app/core/operation/document_operation.dart';

/// 会话操作日志（Operation Engine 第一阶段，2026-10-11）。
///
/// 在命令提交点成对记录的语义影子流：有界（丢最旧）、可导出为 JSONL
/// （一行一操作，供历史压缩 Level 3 / 会话导出 / 未来增量同步消费）。
///
/// 本阶段**不驱动撤销**——撤销仍由命令栈权威执行；日志是记录面。
/// `toJsonl/fromJsonl` 双向往返逐字节保真，供重放验证。
class OperationLog {
  OperationLog({int capacity = 2000})
    : assert(capacity > 0, '容量必须大于 0'),
      _capacity = capacity;

  final int _capacity;
  final List<DocumentOperation> _records = [];

  /// 已记录操作（只读视图，按提交顺序）。
  List<DocumentOperation> get records => List.unmodifiable(_records);

  int get length => _records.length;

  /// 记录一条操作；超出容量丢最旧（与命令栈 maxEntries 同哲学）。
  void record(DocumentOperation operation) {
    _records.add(operation);
    if (_records.length > _capacity) {
      _records.removeRange(0, _records.length - _capacity);
    }
  }

  /// 清空（新会话/显式重置；磁盘导出后的滚动归零由调用方决定）。
  void clear() => _records.clear();

  /// 导出 JSON Lines（一行一操作；尾部带换行）。
  String toJsonl() => [
    for (final op in _records) jsonEncode(op.toJson()),
  ].join('\n');

  /// 从 JSONL 重建（未知类型抛 FormatException——日志重放不容静默丢弃）。
  static OperationLog fromJsonl(String jsonl) {
    final log = OperationLog();
    for (final line in jsonl.split('\n')) {
      if (line.trim().isEmpty) continue;
      log.record(
        DocumentOperation.fromJson(
          Map<String, dynamic>.from(jsonDecode(line) as Map),
        ),
      );
    }
    return log;
  }
}
