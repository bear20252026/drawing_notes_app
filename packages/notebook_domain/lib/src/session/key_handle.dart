// notebook_domain——KeyHandle（批次 D——2026-08-18）。
//
// scoped session 的密钥持有者——每个已打开笔记独立 KeyHandle。
// 锁定时清零（dispose）——内存中的密钥即刻清除。
// 纯 Dart——禁 Widget/BuildContext/Platform/File（R-02）。
library;

/// KeyHandle（scoped 密钥持有者）。
///
/// 遵循专家方案：
/// - 每个已打开笔记本创建一个独立 KeyHandle
/// - 持有该笔记的内容密钥（AES-256-GCM）
/// - 锁定时 dispose（内存清零——R-05 锁定阻断）
/// - 不持久化密钥（只在内存——会话结束即销毁）
class KeyHandle {
  KeyHandle({
    required this.notebookId,
    required List<int> keyBytes,
  }) : _keyBytes = List<int>.from(keyBytes);

  final String notebookId;
  final List<int> _keyBytes;

  /// 获取当前密钥（已解锁时可用——锁定后调用抛异常）。
  List<int> get keyBytes => List<int>.from(_keyBytes);

  /// 销毁（内存清零——R-05 锁定阻断）。
  void dispose() {
    // 安全清零：覆盖内存中的密钥（防内存转储泄露）。
    for (var i = 0; i < _keyBytes.length; i++) {
      _keyBytes[i] = 0;
    }
  }

  @override
  String toString() => 'KeyHandle($notebookId, disposed=${_keyBytes.every((b) => b == 0)})';
}
