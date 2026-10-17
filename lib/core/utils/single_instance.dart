import 'dart:io';

/// 单实例检测（ASM-02，第四轮台账 §24）。
///
/// **契约：任何输入都不阻止启动。** 这里曾经的做法是「探测到已有实例就直接
/// `return`」，用户反馈回来的原话是「应用打不开 / 工具栏全用不了」——残留锁文件
/// 或 PID 存活误判会让第二个实例永远起不来，而且是**静默**起不来。所以现策略是
/// 「并存 + 留审计」，把检测结果当**事实**上报，不当**闸门**。
/// 改成阻断档需要业主点名（那等于把那条历史投诉重新请回来）。
///
/// 三条要如实说的现状（不要因为本模块存在就当它已经能挡住什么）：
/// ① 锁文件在应用退出时**不会**被删除（`release()` 今天没有调用方——桌面端没有
///    可靠的退出钩子），下次启动靠「PID 已不存活」这条回收；
/// ② PID 会被操作系统回收复用，所以「锁文件里的 PID 还活着」**可能**是别的进程，
///    这是检测的固有误差，只够拿来留审计，不够拿来对用户下结论；
/// ③ 锁文件路径是应用全局的，不是数据根级的 ⇒ 两个实例即使各开各的数据根，
///    也会被判成「同机第二个实例」。
enum SingleInstanceStatus {
  /// 本实例拿到了锁（含陈旧锁回收后重新拿到）。
  acquired,

  /// 锁文件里的 PID 经探测**确认仍存活**。
  alreadyRunning,

  /// 判不出来：锁内容不可解析、读写失败、或进程探测本身失败。
  ///
  /// 它与 [alreadyRunning] 分开，是为了不许把「我不知道」说成「有另一个实例」。
  undetectable,
}

/// 进程存活探测的返回值：`true` 存活 / `false` 确认不存活 / `null` 判不了。
///
/// `null` 必须存在：旧实现把「判不了」折进 `true`（保守不清锁，这个方向是对的），
/// 代价是调用方无法区分「确实有活实例」和「探测失败」，于是状态只能一律报
/// `alreadyRunning`——一个谎。拆成三态之后，保守动作不变，说法变诚实了。
typedef ProcessAliveProbe = Future<bool?> Function(int pid);

/// 默认探测：Windows 用 `tasklist`，其余用 `kill -0`。
Future<bool?> systemProcessAlive(int pid) async {
  if (pid <= 0 || pid > 4194304) return false;
  try {
    if (Platform.isWindows) {
      final r = await Process.run('tasklist', ['/FI', 'PID eq $pid', '/NH']);
      // tasklist /NH 行如 `app.exe  1232 Console ...`——按词边界匹配。
      // 子串匹配会让 `2` 命中 `1232`（P2 修复②）。
      return RegExp('(^|\\s)$pid(\\s|\$)')
          .hasMatch(r.stdout.toString().replaceAll(',', ''));
    }
    final r = await Process.run('kill', ['-0', '$pid']);
    return r.exitCode == 0;
  } catch (_) {
    return null;
  }
}

/// 以「原子创建锁文件」为互斥的单实例检测（`File.create(exclusive: true)`）。
///
/// 不用 `RandomAccessFile.lock()`：它在 POSIX 上是**阻塞**语义而不是立即失败，
/// 会把启动挂住（评审发现 P3 的修复记录）。
class SingleInstanceLock {
  SingleInstanceLock({
    required this.lockFile,
    ProcessAliveProbe? isProcessAlive,
  }) : _probe = isProcessAlive ?? systemProcessAlive;

  final File lockFile;
  final ProcessAliveProbe _probe;
  File? _held;

  /// 本实例是否持有锁文件（诊断用）。
  bool get holdsLock => _held != null;

  /// 取锁。**永不抛异常**，也永不表示「别启动」。
  Future<SingleInstanceStatus> acquire({int? currentPid}) async {
    final selfPid = currentPid ?? pid;
    try {
      if (lockFile.existsSync()) {
        final recorded = int.tryParse((await lockFile.readAsString()).trim());
        if (recorded == null) {
          // 空文件或垃圾内容：可能是别的实例刚 create 出来还来不及写 PID。
          // 不删（删别人可能正在写的锁是更坏的动作），也不下「有另一个实例」的结论。
          return SingleInstanceStatus.undetectable;
        }
        final alive = await _probe(recorded);
        if (alive == null) return SingleInstanceStatus.undetectable;
        if (alive) return SingleInstanceStatus.alreadyRunning;
        try {
          await lockFile.delete();
        } catch (_) {
          // 清不掉陈旧锁也不阻塞启动：下面 create 会失败，落成 undetectable。
        }
      }
      final created = await lockFile.create(exclusive: true);
      await created.writeAsString(selfPid.toString(), flush: true);
      _held = created;
      return SingleInstanceStatus.acquired;
    } catch (_) {
      // create 竞态失败（别人先建成了）或目录/权限问题——一律归为「判不出来」，
      // 启动照常。这里不许出现任何 rethrow：那会把「检测」变成「阻断」。
      return SingleInstanceStatus.undetectable;
    }
  }

  /// 释放锁。**今天没有调用方**（桌面端没有可靠的退出钩子，见文件头①）。
  Future<void> release() async {
    try {
      await _held?.delete();
    } catch (_) {
      // 删除失败忽略：下次启动的 PID 存活判定会回收它。
    }
    _held = null;
  }
}
