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

/// 弱引用注册表（见文件头设计说明）。
class SessionSecrets {
  SessionSecrets._();

  static final List<WeakReference<SessionSecretsHolder>> _holders = [];

  static void register(SessionSecretsHolder holder) {
    _holders.add(WeakReference(holder));
  }

  /// 清空全部存活持有者的会话机密（AppLockGate.hidden 联动）。
  static void clearAll() {
    _holders.removeWhere((ref) => ref.target == null);
    for (final ref in List.of(_holders)) {
      try {
        ref.target?.clearAllSessionSecrets();
      } catch (_) {}
    }
  }

  /// 存活持有者数（测试观察用）。
  static int get liveCount =>
      _holders.where((ref) => ref.target != null).length;
}
