import 'dart:convert';

import 'package:drawing_notes_app/core/operation/document_operation.dart';

/// 一条记录 + 它在会话里的提交序号。
///
/// 序号必须跟着记录一起交出去，不能靠「第几条」反推：容量截断丢最旧之后两者会错位，
/// 而磁盘侧车的水位线一旦错位就是**静默丢操作**。
typedef OperationLogEntry = ({int serial, DocumentOperation operation});

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
  final List<int> _serials = [];
  int _serial = 0;

  /// 已记录操作（只读视图，按提交顺序）。
  List<DocumentOperation> get records => List.unmodifiable(_records);

  int get length => _records.length;

  /// 最后一条操作的提交序号（本会话内单调递增）。
  ///
  /// 与 [length] 的区别：容量截断丢最旧、[clear] 都**不**让它回退，所以磁盘侧车
  /// 拿它当水位线是安全的——回退会让已落盘的那段被再落一次。
  int get lastSerial => _serial;

  /// 序号大于 [serial] 且**仍在本窗口里**的记录（按提交顺序）。
  /// 被容量截断丢掉的那些不会出现在结果里，也不会把水位线推过它们。
  List<OperationLogEntry> entriesSince(int serial) => [
    for (var i = 0; i < _records.length; i++)
      if (_serials[i] > serial)
        (serial: _serials[i], operation: _records[i]),
  ];

  /// 记录一条操作；超出容量丢最旧（与命令栈 maxEntries 同哲学）。
  void record(DocumentOperation operation) {
    _serial++;
    _records.add(operation);
    _serials.add(_serial);
    if (_records.length > _capacity) {
      final drop = _records.length - _capacity;
      _records.removeRange(0, drop);
      _serials.removeRange(0, drop);
    }
  }

  /// 清空（新会话/显式重置；磁盘导出后的滚动归零由调用方决定）。
  /// 序号**不清零**：它是水位线的坐标轴，清零等于宣布「已落盘的没落过」。
  void clear() {
    _records.clear();
    _serials.clear();
  }

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
