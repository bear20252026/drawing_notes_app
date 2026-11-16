/// 会话级机密统一清理注册表（P1 安全修复 M-05/M-09）。
///
/// 背景：文件密码（`StorageService._sessionFilePasswords`）、笔记本密码
/// （`NotebookStorage._sessionNotebookPasswords`）、块文档 DEK
/// （`NoteBlockDocStore._sessionDeks`）均为内存态敏感材料，此前仅在
/// “显式移除/删除”时清理——切后台回锁（`AppLockGate.hidden`）时驻留，
/// 后台堆转储可恢复全部会话口令（KEK 缓存同期已被 `clear()`，口径不一）。
///
/// 设计：
/// - 持有者实现 [SessionSecretsHolder] 并在构造时 `SessionSecrets.register`；
/// - 注册表只存 [WeakReference]——实例回收后自动失效，不泄漏、不污染测试
///   进程（多实例测试各自独立，clearAll 顺手剪除已回收项）；
/// - `clearAll` 逐个调用、各自 try/catch——一家抛错不影响其他家清理。
library;

/// 会话机密持有者：实现 [clearAllSessionSecrets]（幂等、永不抛错——
/// 内部自行吞错；DEK 类字节材料须 fill(0) 后再移出）。
abstract class SessionSecretsHolder {
  void clearAllSessionSecrets();
}

/// 会话世代令牌（框架级收口 2026-11-15）：每次 [SessionSecrets.clearAll]
/// （回锁/切后台）递增。一切**跨 await 的密钥操作**在发起时捕获
/// [current]，完成时校验——世代已变即作废（不注入/不落盘/不用钥）。
///
/// 背景（审计 M-3/M-4 根源）：清零是「尽力而为」的广播，没有任何机制
/// 让在途异步操作在回锁后失效——ensure 落盘后无条件注钥、加解密 await
/// 期间密钥被清零，这类竞态是结构性必然。世代令牌把「会话已翻篇」变成
/// 可校验的事实，竞态被构造性消除，而不是靠调用方各自复查锁态。
class SessionEpoch {
  SessionEpoch._();

  static int _epoch = 0;

  /// 当前会话世代（发起慢操作前捕获）。
  static int get current => _epoch;

  /// 递增世代（仅 [SessionSecrets.clearAll] 调用——回锁即翻篇）。
  static void bump() => _epoch++;
}

/// 弱引用注册表（见文件头设计说明）。
class SessionSecrets {
  SessionSecrets._();

  static final List<WeakReference<SessionSecretsHolder>> _holders = [];

  static void register(SessionSecretsHolder holder) {
    _holders.add(WeakReference(holder));
  }

  /// 清空全部存活持有者的会话机密（AppLockGate.hidden 联动）。
  /// 先递增会话世代（在途密钥操作完成时校验作废），再逐家清零。
  static void clearAll() {
    SessionEpoch.bump();
    _holders.removeWhere((ref) => ref.target == null);
    for (final ref in List.of(_holders)) {
      try {
        ref.target?.clearAllSessionSecrets();
      } catch (_) {
        /* 尽力而为：单个持有者清空失败不阻断其余持有者（回锁联动热路径） */
      }
    }
  }

  /// 存活持有者数（测试观察用）。
  static int get liveCount =>
      _holders.where((ref) => ref.target != null).length;
}
