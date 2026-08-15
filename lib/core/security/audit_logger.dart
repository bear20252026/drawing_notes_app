/// 安全审计日志（红蓝攻防 P2 修复 2026-08-15）：
/// 记录密钥加载/密码盘操作（时间戳 + 操作 + 结果），**仅本地内存、绝不含
/// 密钥与内容**（防审计日志本身成为泄露面）。报告建议"记录加密/解密/密钥
/// 加载操作（仅本地，不上传）"——最小可行实现：密钥加载审计（最有价值）。
class AuditLogger {
  AuditLogger._();

  static final List<String> _entries = [];

  /// 审计记录内存上限（链 10 修复 2026-08-15）：长期会话高频操作防
  /// 无限增长（保留最近 [_maxEntries] 条）。
  static const int _maxEntries = 1000;

  /// 记录一次安全操作：operation 为操作名（如 'password_disk.read_key'），
  /// success 标识结果，detail 为补充说明（**禁止传密钥/内容**）。
  static void log(String operation, {bool success = true, String? detail}) {
    final time = DateTime.now().toIso8601String();
    _entries.add(
      '[$time] $operation ${success ? 'OK' : 'FAIL'}'
      '${detail != null ? ' $detail' : ''}',
    );
    if (_entries.length > _maxEntries) {
      _entries.removeRange(0, _entries.length - _maxEntries);
    }
  }

  /// 当前审计记录快照（只读，供 UI/调试查看）。
  static List<String> snapshot() => List.unmodifiable(_entries);

  /// 清空审计记录（测试用）。
  static void clear() => _entries.clear();
}
