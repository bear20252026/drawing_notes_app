import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';

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

  /// 滚动裁剪后的链起点锚（checkpoint）：被丢弃尾部之后、当前首条的
  /// prevHash。verifyIntegrity 从此处而非 genesis 重放——否则一旦裁剪过
  /// 就恒报「已篡改」（裁剪条目仍是新首条的 prevHash，genesis 重放必断）。
  static String _anchorPrevHash = _genesisHash;

  /// 累计被丢弃条数（内存内 checkpoint 分量）。本类**仅本地内存、无落盘**
  /// （见类注释——防审计日志自身成泄露面），重启即空链，故单独持久化
  /// checkpoint 无意义：不落盘、不新增文件 IO（保持公共 API 与内存设计兼容）。
  static int _droppedCount = 0;

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
      final drop = _entries.length - _maxEntries;
      _entries.removeRange(0, drop);
      // checkpoint：新链起点 = 裁剪后首条的 prevHash（即被丢弃尾部的末条 hash）。
      _droppedCount += drop;
      _anchorPrevHash = _entries.first.prevHash;
    }
  }

  /// 当前审计记录快照（只读，供 UI/调试查看——display 格式兼容旧版）。
  static List<String> snapshot() =>
      List.unmodifiable(_entries.map((e) => e.display));

  /// 哈希链完整性验证（Thalian verify_audit_chain / 掘金 verify_integrity
  /// 模式）：从**当前链真实起点**（_anchorPrevHash，未裁剪时即 genesis）重放
  /// ——prevHash 链接 + 重算哈希——任何字段篡改立即检出。滚动裁剪后从锚点起
  /// 重放，不再假装从 genesis 起（否则正常运行的长会话日志被误判为已篡改）。
  static bool verifyIntegrity() {
    var prev = _anchorPrevHash;
    for (final e in _entries) {
      if (e.prevHash != prev) return false; // 链接断裂（删除/插入中间记录）。
      if (e.hash !=
          _sha256(
            _payload(e.time, e.operation, e.success, e.detail, e.prevHash),
          )) {
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

  /// 累计被丢弃条数（仅测试观测 checkpoint 锚点是否生效——非生产 API）。
  @visibleForTesting
  static int get droppedCountForTest => _droppedCount;

  /// 仅供测试：篡改第 [index] 条留存记录的 detail 而**保留旧 hash**——模拟
  /// 真实篡改者无法重算链，verifyIntegrity 重算必不匹配。非生产路径。
  @visibleForTesting
  static void tamperEntryForTest(int index, {String detail = 'TAMPERED'}) {
    final e = _entries[index];
    _entries[index] = _AuditEntry(
      time: e.time,
      operation: e.operation,
      success: e.success,
      detail: detail,
      prevHash: e.prevHash,
      hash: e.hash,
    );
  }

  /// 清空审计记录（测试用——重置哈希链）。
  ///
  /// 语义：整条链归零——anchor 回到 genesis、dropped 归 0。clear 之后重放是
  /// 一条**全新的独立链**（首条 prevHash = genesis），不会与被裁剪/清空前的
  /// 历史续接，故无法把「新链」伪造成「历史连续」。生产路径从不调用 clear
  /// （仅测试 setUp 使用）。
  static void clear() {
    _entries.clear();
    _lastHash = _genesisHash;
    _anchorPrevHash = _genesisHash;
    _droppedCount = 0;
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
