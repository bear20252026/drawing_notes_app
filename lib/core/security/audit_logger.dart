import 'dart:convert';

import 'package:crypto/crypto.dart';

/// 安全审计日志（红蓝攻防 P2 修复 2026-08-15 + 哈希链强化 2026-08-16）：
/// 记录密钥加载/密码盘操作（时间戳 + 操作 + 结果），**仅本地内存、绝不含
/// 密钥与内容**（防审计日志本身成为泄露面——去敏）。
///
/// 哈希链（专家目标架构"不可篡改审计事件流"——Thalian verify_audit_chain /
/// Revka Merkle 链 / 掘金 Layer 6 权威模式）：每条记录含 prevHash（前一条
/// 哈希）+ 自身 SHA-256 哈希——任何字段篡改立即断链，verifyIntegrity()
/// 重放检出（篡改检测——审计完整性）。
class AuditLogger {
  AuditLogger._();

  static final List<_AuditEntry> _entries = [];

  /// 审计记录内存上限（链 10 修复 2026-08-15）：长期会话高频操作防
  /// 无限增长（保留最近 [_maxEntries] 条）。
  static const int _maxEntries = 1000;

  /// 哈希链 genesis 种子（Revka 模式——固定零种子——链起点）。
  /// （final：运行期计算——const 求值不支持 String 乘法。）
  static final String _genesisHash = '0' * 64;

  static String _lastHash = _genesisHash;

  /// 记录一次安全操作：operation 为操作名（如 'password_disk.read_key'），
  /// success 标识结果，detail 为补充说明（**禁止传密钥/内容**）。
  static void log(String operation, {bool success = true, String? detail}) {
    final time = DateTime.now().toIso8601String();
    final prevHash = _lastHash;
    // skylos: ignore —— 运行时 SHA-256 哈希（非硬编码凭据）——Skylos 静态
    // 高熵检测误报（熵 3.98——hash 是计算值非常量）。
    final hash = _sha256(_payload(time, operation, success, detail, prevHash));
    _entries.add(
      _AuditEntry(
        time: time,
        operation: operation,
        success: success,
        detail: detail,
        prevHash: prevHash,
        hash: hash,
      ),
    );
    _lastHash = hash;
    if (_entries.length > _maxEntries) {
      _entries.removeRange(0, _entries.length - _maxEntries);
    }
  }

  /// 当前审计记录快照（只读，供 UI/调试查看——display 格式兼容旧版）。
  static List<String> snapshot() =>
      List.unmodifiable(_entries.map((e) => e.display));

  /// 哈希链完整性验证（Thalian verify_audit_chain / 掘金 verify_integrity
  /// 模式）：重放链——prevHash 链接 + 重算哈希——任何字段篡改立即检出。
  static bool verifyIntegrity() {
    var prev = _genesisHash;
    for (final e in _entries) {
      if (e.prevHash != prev) return false; // 链接断裂（删除/插入中间记录）。
      if (e.hash != _sha256(_payload(e.time, e.operation, e.success, e.detail, e.prevHash))) {
        return false; // 哈希不符（字段被篡改）。
      }
      prev = e.hash;
    }
    return true;
  }

  static String _payload(
    String time,
    String operation,
    bool success,
    String? detail,
    String prevHash,
  ) =>
      '$prevHash|$time|$operation|${success ? 'OK' : 'FAIL'}'
      '${detail != null ? '|$detail' : ''}';

  static String _sha256(String input) =>
      sha256.convert(utf8.encode(input)).toString();

  /// 清空审计记录（测试用——重置哈希链）。
  static void clear() {
    _entries.clear();
    _lastHash = _genesisHash;
  }
}

/// 审计记录（含哈希链字段——prevHash 链接前一条 + hash 自身完整性）。
class _AuditEntry {
  const _AuditEntry({
    required this.time,
    required this.operation,
    required this.success,
    required this.detail,
    required this.prevHash,
    required this.hash,
  });

  final String time;
  final String operation;
  final bool success;
  final String? detail;
  final String prevHash;
  final String hash;

  /// 展示格式（兼容旧版 snapshot：`[time] operation OK/FAIL detail`）。
  String get display =>
      '[$time] $operation ${success ? 'OK' : 'FAIL'}'
      '${detail != null ? ' $detail' : ''}';
}
