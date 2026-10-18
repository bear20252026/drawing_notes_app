import 'dart:io';

/// 单实例检测（ASM-02，第四轮台账 §24；同根判定 R51，台账 §35）。
///
/// **契约：任何输入都不阻止启动。** 这里曾经的做法是「探测到已有实例就直接
/// `return`」，用户反馈回来的原话是「应用打不开 / 工具栏全用不了」——残留锁文件
/// 或 PID 存活误判会让第二个实例永远起不来，而且是**静默**起不来。所以现策略是
/// 「并存 + 留审计 + 只在能说清的时候提醒」，把检测结果当**事实**上报，不当**闸门**。
/// 改成阻断档需要业主点名（那等于把那条历史投诉重新请回来）。
///
/// 三条要如实说的现状（不要因为本模块存在就当它已经能挡住什么）：
/// ① 锁文件在应用退出时**不会**被删除（`release()` 今天没有调用方——桌面端没有
///    可靠的退出钩子），下次启动靠「PID 已不存活」这条回收；
/// ② PID 会被操作系统回收复用，所以「锁文件里的 PID 还活着」**可能**是别的进程，
///    这是检测的固有误差，只够拿来留审计与提示，不够拿来对用户下结论；
/// ③ 锁文件路径是**应用全局**的（`<ApplicationSupport>/app.lock`），不是数据根级 ⇒
///    光看锁在不在，两个各开各数据根的实例也会被判成「同一个」。R51 起锁内容第二行写
///    数据根路径，于是能分出「同一个数据根的第二个实例」（这才值得提醒用户）与
///    「另一个数据根的实例」（不该提醒）。老版本写的锁只有 PID 一行 ⇒ 根**未知**，
///    这种归 [SingleInstanceStatus.undetectable]：不猜，也不提醒。
enum SingleInstanceStatus {
  /// 本实例拿到了锁（含陈旧锁回收后重新拿到）。
  acquired,

  /// 锁里的 PID 确认仍存活，**且那份锁记的数据根与本实例同一个**。
  ///
  /// 只有这一格值得说给用户听：两边写的确实是同一批文件。
  sameDataRootRunning,

  /// 锁里的 PID 存活，但锁记的数据根与本实例**不同** ⇒ 各写各的，不构成冲突。
  otherDataRoot,

  /// 判不出来：锁内容不可解析、读写失败、进程探测失败，或**老格式锁没有根信息**。
  ///
  /// 它与 [SingleInstanceStatus.sameDataRootRunning] 分开，是为了不许把「我不知道」
  /// 说成「有人在动你这份数据」。
  undetectable,
}

/// 启动期一次性事实：`main()` 在 `runApp` 之前写入，UI 侧只读。
///
/// 为什么是个顶层变量而不是沿构造链传参：`AppShell` 的注入链要穿过 `DrawingNotesApp`
/// 与组合根三层才到得展示面，而这是一条**启动后再也不变**的事实——本仓同类先例是
/// `AppDataRoot.usesTestDataRoot` 与 `RootGuard`。写它的位置由
/// `test/core/utils/single_instance_lock_test.dart` 的「赋值点只有一处且在 main.dart」
/// 那条判据钉住：UI 或存储层里出现写它的代码 ⇒ 红。
/// 留 null 是刻意的：没跑过检测（例如测试里直接 pump AppShell）就不能显示任何提示，
/// 而不是显示一个猜出来的提示。
SingleInstanceStatus? instanceStatusAtLaunch;

/// 进程存活探测的返回值：`true` 存活 / `false` 确认不存活 / `null` 判不了。
///
/// `null` 必须存在：旧实现把「判不了」折进 `true`（保守不清锁，这个方向是对的），
/// 代价是调用方无法区分「确实有活实例」和「探测失败」，于是状态只能一律报
/// `alreadyRunning`——一个谎。拆成多态之后保守动作不变，说法变诚实了。
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

/// 两个数据根路径是不是同一个。
///
/// 归一化只做**必要的**三件事：分隔符统一、去掉尾部分隔符、Windows 下忽略大小写
/// （Windows 路径本身大小写不敏感，`C:\AppData` 与 `c:\appdata` 是同一个目录）。
/// 不做符号链接解析、不做 `..` 折叠：本仓的数据根来自 `path_provider` + 一个固定子目录名，
/// 出现这两种形状的路径需要先改 `AppDataRoot` 的解析，那不在这条判据的范围里。
bool isSameDataRootPath(String a, String b) {
  String norm(String p) {
    var s = p.replaceAll('\\', '/');
    while (s.length > 1 && s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return Platform.isWindows ? s.toLowerCase() : s;
  }

  if (a.isEmpty || b.isEmpty) return false;
  return norm(a) == norm(b);
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
  ///
  /// [dataRootKey] 是本实例将要读写的**数据根路径**（`AppDataRoot.defaultRootDir()` 的
  /// `path`）。它写进锁的第二行，也是下一次启动判断「是不是同一个根」的依据——
  /// 传空串等于自愿放弃同根判定（结果只会是 `undetectable`）。
  Future<SingleInstanceStatus> acquire({
    required String dataRootKey,
    int? currentPid,
  }) async {
    final selfPid = currentPid ?? pid;
    try {
      if (lockFile.existsSync()) {
        final lines = (await lockFile.readAsString()).split('\n');
        final recorded = int.tryParse(lines.first.trim());
        // 第二行缺失 = 老版本写的锁 ⇒ 知道有活实例，但不知道是不是同一个根。
        final recordedRoot = lines.length > 1 ? lines[1].trim() : '';
        if (recorded == null) {
          // 空文件或垃圾内容：可能是别的实例刚 create 出来还来不及写 PID。
          // 不删（删别人可能正在写的锁是更坏的动作），也不下「有另一个实例」的结论。
          return SingleInstanceStatus.undetectable;
        }
        final alive = await _probe(recorded);
        if (alive == null) return SingleInstanceStatus.undetectable;
        if (alive) {
          // 两边任一侧的根不知道，就只能说「判不出来」：
          // 报 `otherDataRoot` 同样是在猜（「各写各的」并没有被证明）。
          if (recordedRoot.isEmpty || dataRootKey.isEmpty) {
            return SingleInstanceStatus.undetectable;
          }
          return isSameDataRootPath(recordedRoot, dataRootKey)
              ? SingleInstanceStatus.sameDataRootRunning
              : SingleInstanceStatus.otherDataRoot;
        }
        try {
          await lockFile.delete();
        } catch (_) {
          // 清不掉陈旧锁也不阻塞启动：下面 create 会失败，落成 undetectable。
        }
      }
      final created = await lockFile.create(exclusive: true);
      await created.writeAsString('$selfPid\n$dataRootKey', flush: true);
      _held = created;
      return SingleInstanceStatus.acquired;
    } catch (_) {
      // create 竞态失败（别人先建成了）或目录/权限问题——一律归为「判不出来」，
      // 启动照常。这里不许出现任何 rethrow：那会把「检测」变成「阻断」。
      return SingleInstanceStatus.undetectable;
    }
  }

  /// 锁文件里记的数据根（诊断与测试用；老格式锁返回空串）。
  Future<String> recordedDataRoot() async {
    try {
      if (!lockFile.existsSync()) return '';
      final lines = (await lockFile.readAsString()).split('\n');
      return lines.length > 1 ? lines[1].trim() : '';
    } catch (_) {
      return '';
    }
  }

  /// 释放锁。**今天没有调用方**（桌面端没有可靠的退出钩子，见模块文件头①）。
  Future<void> release() async {
    try {
      await _held?.delete();
    } catch (_) {
      // 删除失败忽略：下次启动的 PID 存活判定会回收它。
    }
    _held = null;
  }
}
