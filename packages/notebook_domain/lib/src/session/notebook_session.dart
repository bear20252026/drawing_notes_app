// notebook_domain——NotebookSession 状态机（批次 D——2026-08-18）。
//
// 专家方案批次 D：状态机、凭据验证、钥匙持有/清零、过期、锁定、权限校验。
// 遵循专家"NotebookSession：状态机、凭据验证、钥匙持有/清零、过期、锁定、
// 权限校验"——重写单元（当前锁定只清部分服务，页面仍保留可用凭据）。
//
// 纯 Dart——禁 Widget/BuildContext/Platform/File（R-02）。
library;

import 'key_handle.dart';
import 'lock_policy.dart';

/// 会话状态（枚举）。
enum SessionState {
  /// 未初始化（未打开笔记本）。
  uninitialized,

  /// 已解锁（有有效 KeyHandle——可执行编辑/保存/导出/媒体读取）。
  unlocked,

  /// 已锁定（无有效密钥——R-05 锁定阻断所有操作）。
  locked,

  /// 已过期（超过过期时间——需重新认证）。
  expired,
}

/// NotebookSession 状态机（批次 D——2026-08-18）。
///
/// 遵循专家方案：
/// - 每个已打开笔记本创建一个 scoped session
/// - KeyHandle 持有该笔记的密钥（scoped）
/// - 锁定时**清除所有 scoped 密钥**（R-05 锁定阻断渲染/编辑/保存/导出/媒体）
/// - 过期时需重新认证
/// - 解锁后创建新 session（I-008 验收）
class NotebookSession {
  NotebookSession({
    required this.notebookId,
    required this._lockPolicy,
  });

  final String notebookId;
  final LockPolicy _lockPolicy;

  SessionState _state = SessionState.uninitialized;
  KeyHandle? _keyHandle;
  DateTime? _unlockedAt;

  /// 当前会话状态。
  SessionState get state => _state;

  /// 是否已解锁。
  bool get isUnlocked => _state == SessionState.unlocked;

  /// 是否已锁定。
  bool get isLocked => _state == SessionState.locked;

  /// 当前 KeyHandle（已解锁时非 null——锁定/过期/未初始化时 null）。
  KeyHandle? get keyHandle => isUnlocked ? _keyHandle : null;

  /// 解锁（认证成功后——创建 KeyHandle——状态转 unlocked）。
  ///
  /// I-008 验收：锁定后解锁 = 创建新 session。
  void unlock(List<int> keyBytes) {
    _keyHandle = KeyHandle(notebookId: notebookId, keyBytes: keyBytes);
    _state = SessionState.unlocked;
    _unlockedAt = DateTime.now();
  }

  /// 锁定（R-05：**清除所有 scoped 密钥**——锁定后不能编辑/保存/导出/读取媒体）。
  ///
  /// I-008 验收：lock_clears_all_scoped_keys + locked_session_denies_all。
  void lock() {
    _keyHandle?.dispose();
    _keyHandle = null;
    _state = SessionState.locked;
    _unlockedAt = null;
  }

  /// 检查是否过期（调用方定期调用——过期时自动锁定）。
  ///
  /// 如果超过 lockPolicy.autoLockDuration——自动锁定并标记 expired。
  /// 不调用 lock()，直接内联锁定逻辑（避免 lock() 设置 locked 覆盖 expired）。
  bool checkExpiry() {
    if (_state != SessionState.unlocked) return false;
    if (_unlockedAt == null) return false;
    if (_lockPolicy.isExpired(_unlockedAt!)) {
      // 直接清理（不调用 lock()——避免 lock() 设置 _state = locked）。
      _keyHandle?.dispose();
      _keyHandle = null;
      _unlockedAt = null;
      _state = SessionState.expired; // 过期语义（不是 locked）
      return true;
    }
    return false;
  }

  /// 权限校验（R-05：锁定/过期/未初始化时拒绝所有操作）。
  ///
  /// 调用方在编辑/保存/导出/媒体读取前调用。
  bool canPerformAction() {
    checkExpiry(); // 先检查过期
    return isUnlocked;
  }

  /// 销毁会话（释放资源）。
  void dispose() {
    _keyHandle?.dispose();
    _keyHandle = null;
    _state = SessionState.uninitialized;
    _unlockedAt = null;
  }

  @override
  String toString() => 'NotebookSession($notebookId, state=$_state)';
}
