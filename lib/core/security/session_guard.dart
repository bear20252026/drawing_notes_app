import 'dart:async';

import 'package:flutter/widgets.dart';

/// 全局「失焦豁免窗口」——SessionGuard 与 AppLockGate 共用的单一事实来源。
///
/// 原生文件对话框 / 系统权限弹窗 / 打开外部查看器会抢走 OS 窗口焦点，
/// Flutter 据此投递 `inactive`（有时 `hidden`）；这并非用户主动切后台。
/// 若门把这些失焦信号当作切后台就会**假锁**。豁免窗口开启期间，两条
/// 锁定链路（SessionGuard 的媒体密钥锁定 + AppLockGate 的开屏锁定）都
/// 不据此加锁。
///
/// 为什么是进程内静态而非注入实例：
/// - 一台设备同时只有一个前台窗口，「此刻正有原生选择器打开」是全局事实；
/// - 原生选择器调用点散落在笔记导入 / 设置恢复 / U 盘绑定等多个页面，
///   它们拿不到挂在根的 AppLockGate 组件（SessionGuard 有注入点是因为它
///   只挂在笔记本页）。静态窗口让任一处 begin/end 都能同时约束两条链路。
///
/// 安全红线（与 SessionGuard 原豁免同思路，逐条对齐）：
/// - **默认不豁免**：计数 0 → [isActive] 恒 false，门照常锁定；
/// - **超时上界**：每次 [begin] 刷新 [ttl] 截止；调用方崩溃 / 漏 [end] 后
///   豁免到期自动失效，绝不无限期挂免死金牌；
/// - **单调钟**：截止用 Stopwatch 单调毫秒比对，系统时钟回拨无法延长豁免
///   （fail-closed，与防爆破守卫同一防调钟口径）；
/// - **计数配对**：嵌套选择器成对开关，一次 end 不会提前关闭他人豁免。
///
/// 释放途径有两条，且都会**同步通知** [addWindowClosedListener] 的监听者
/// （2026-10-06，台账 P2-1）：
/// - 末位 [end]：选择器正常关闭；
/// - TTL 就地失效：读到 [isActive] 时按单调秒表判定（惰性）。
///
/// **本窗口自己不挂定时器**：它是进程级静态，测试里一次未配对的 [begin]
/// 会把定时器留到用例结束，`testWidgets` 随即以「Pending timers」判红
/// （AW15 首推即在 `editor_insert_image_entry_test` 撞上，2219 通过 1 红）。
/// 「到点主动暴露」的责任放在消费者侧——AppLockGate 用随组件释放的看门表
/// 定时来读 [isActive]，读到的那一刻惰性失效并通知。既不留全局定时器，
/// 也不再依赖「恰好有人来查」。
///
/// 通知只交付「窗口没了」这个事实，**不替调用方决定要不要置锁**：判定留在
/// AppLockGate（它才知道当前生命周期态与宽限期），避免在焦点马上就回来的
/// 路径上闪一下锁屏。
class LockExemption {
  LockExemption._();

  /// 超时上界：5 分钟。取一档远大于任何一次原生选择器人工耗时（含
  /// U 盘浏览 / 网络盘定位）的上限；超过即视为调用方漏 end，豁免过期，
  /// 门恢复「切后台即锁」。SessionGuard 原 TTL 同取 5 分钟，口径拉齐。
  static const Duration ttl = Duration(minutes: 5);

  /// 测试专用 TTL 覆盖（与 `AppLockService.testPinKdfOverride`、
  /// `KekSessionCache.bypassIsolateForTests` 同一先例）。
  ///
  /// 为什么需要：截止判定走**单调秒表（真实时间）**，而 `testWidgets` 的
  /// `tester.pump()` 只推进假时钟——不注入短 TTL 的话，任何「等豁免到期」的
  /// 用例都只能在真实 5 分钟后再断言（同一条用例里的秒表读数永远追不上）。
  /// 生产恒为 null ⇒ 走 [ttl]。
  @visibleForTesting
  static Duration? ttlOverrideForTest;

  /// 单调秒表（进程生命周期常驻）——截止只相对它读数，免疫系统时钟调整。
  static final Stopwatch _mono = Stopwatch()..start();

  static int _depth = 0;
  static int _untilMonoMs = 0;
  static final List<void Function(bool ttlExpired)> _closedListeners = [];

  /// 当前是否处于豁免窗口内（计数 > 0 且未超 TTL）。
  static bool get isActive {
    if (_depth <= 0) return false;
    if (_mono.elapsedMilliseconds >= _untilMonoMs) {
      _clear(ttlExpired: true); // TTL 到期：就地失效（免死金牌不会永续）。
      return false;
    }
    return true;
  }

  /// 开启一层豁免（刷新 TTL 截止）。与 [end] 严格配对。
  static void begin() {
    _depth++;
    final window = ttlOverrideForTest ?? ttl;
    _untilMonoMs = _mono.elapsedMilliseconds + window.inMilliseconds;
  }

  /// 关闭一层豁免；末位关闭即清空窗口。
  static void end() {
    if (_depth > 0) _depth--;
    if (_depth == 0) _clear();
  }

  /// 作用域式豁免：[fn] 执行期间豁免（含抛异常，finally 保证配对复位）。
  static Future<T> run<T>(Future<T> Function() fn) async {
    begin();
    try {
      return await fn();
    } finally {
      end();
    }
  }

  /// 订阅「豁免窗口关闭」事件（参数 = 是否因 TTL 到期而关闭）。
  ///
  /// 与豁免本身同样是进程级静态：一台设备只有一个前台窗口，而原生选择器的
  /// 调用点散落在多个页面、拿不到挂在根的 AppLockGate。监听者必须自己配对
  /// 移除（门的 `dispose` 里），否则跨用例、跨路由串味。
  static void addWindowClosedListener(
    void Function(bool ttlExpired) listener,
  ) => _closedListeners.add(listener);

  static void removeWindowClosedListener(
    void Function(bool ttlExpired) listener,
  ) => _closedListeners.remove(listener);

  static void _clear({bool ttlExpired = false}) {
    // 窗口「开着」的判据不能只看 `_depth`：`end()` 是先自减再调本函数，
    // 末位释放时 `_depth` 已经是 0，而截止位还在 ⇒ 用两者取或。
    final wasOpen = _depth > 0 || _untilMonoMs != 0;
    _depth = 0;
    _untilMonoMs = 0;
    if (!wasOpen) return;
    // 回调前拍快照：监听者可能在回调里摘除自己（remove 会让边遍历边改出问题）。
    for (final listener in List.of(_closedListeners)) {
      listener(ttlExpired);
    }
  }

  /// 当前剩余豁免时长（不在窗口内为 0；诊断 / 测试用）。
  static Duration get remaining => Duration(
    milliseconds: _depth > 0
        ? (_untilMonoMs - _mono.elapsedMilliseconds).clamp(0, 1 << 30)
        : 0,
  );

  /// 测试复位（清空计数、截止与监听者）——避免用例间全局窗口串味。
  @visibleForTesting
  static void resetForTest() {
    _clear();
    _closedListeners.clear();
    ttlOverrideForTest = null;
  }
}

/// 会话守卫（专家审计最优先③——SessionGuard + PolicyEngine + Capability，
/// 2026-08-16 落地）。
///
/// 自动锁定/再认证（Flutter 官方 AppLifecycleListener + private_notes_light
/// SessionLifecycleObserver 权威模式）：onInactive（失去焦点——切后台/锁屏）
/// 立即锁定（清除媒体密钥）；文件选择器运行期间豁免（防导入/导出误锁——
/// private_notes_light filePickerRunning 模式）；onResume 若已锁定则触发
/// 再认证回调（导航回解锁页）。安全检查集中单一服务（Flutter 安全指南
/// "Centralize your checks"）。
///
/// 豁免实现已收口到进程级 [LockExemption]（2026-10-04「切后台全量锁定」）：
/// 与 AppLockGate 的开屏锁共用同一窗口，一次 [runWithExemption] 同时按住
/// 两条锁定链路——否则门新处理 `inactive` 后，笔记本导入选择器会假锁开屏。
class SessionGuard {
  SessionGuard({
    this.onLock,
    this.onReauthenticateRequired,
    this.graceDuration = defaultExemptionCloseGrace,
    this.lifecycleStateProvider,
  }) {
    _listener = AppLifecycleListener(
      onInactive: onInactive,
      onResume: onResume,
    );
    // P2-1 续项（2026-10-07）：订阅豁免窗口关闭事件——末位 end 与 TTL 惰性
    // 失效都同步通知。此前媒体密钥链路只认「下一次 onInactive」，而笔记本页
    // 在豁免期内本就处于 inactive，状态不变就没有新信号：用户在原生对话框
    // 期间离席 + 之后再无生命周期信号 ⇒ 密钥无限期驻留内存。与 AppLockGate
    // 同源同口径收口（判定留在本类——只有它知道生命周期态与宽限期）。
    LockExemption.addWindowClosedListener(_onExemptionWindowClosed);
  }

  /// 豁免窗口关闭后、人还没回前台时的宽限时长（默认 5 秒）。
  ///
  /// 为什么不是 0：桌面原生对话框关闭的瞬间，`end()` 与 `resumed` 的投递
  /// 顺序没有保证——就地置锁会把「选完文件焦点立刻回来」的正常路径打成
  /// 重新认证（恰是豁免窗口要防的假锁）。宽限只吸收信号时序，不是锁延时
  /// 特性：取一档远大于焦点交接耗时（毫秒级）、又远小于任何人工操作的值。
  static const Duration defaultExemptionCloseGrace = Duration(seconds: 5);

  /// 锁定回调（调用方清除媒体密钥——MediaCryptoService.clearSessionKey——
  /// 并标记 UI 锁定状态）。
  final VoidCallback? onLock;

  /// 再认证回调（onResume 时已锁定——导航回解锁/密码输入页）。
  final VoidCallback? onReauthenticateRequired;

  /// 豁免窗口关闭后的宽限时长（测试可注入短值，见
  /// [defaultExemptionCloseGrace]）。
  final Duration graceDuration;

  /// 当前生命周期态读取器（测试注入固定态用；生产走 WidgetsBinding）。
  final AppLifecycleState? Function()? lifecycleStateProvider;

  AppLifecycleState? get _lifecycleState {
    final provider = lifecycleStateProvider;
    if (provider != null) return provider();
    return WidgetsBinding.instance.lifecycleState;
  }

  late final AppLifecycleListener _listener;

  bool _locked = false;

  /// 豁免 TTL 看门表：**必须挂在本类实例上而不是 `LockExemption` 静态里**
  /// （AW15b 教训——进程级定时器会被任何一次未配对的 begin 带进
  /// `testWidgets` 并以「Pending timers」判红）。豁免期间的失焦信号按
  /// `LockExemption.remaining` 起表，到点读一次 [LockExemption.isActive]；
  /// 本实例 dispose 时取消。
  Timer? _exemptionWatchTimer;

  /// 豁免窗口关闭、人未回前台时的宽限定时器（随实例 dispose 取消）。
  Timer? _graceDeadlineTimer;
  bool _gracePending = false;

  bool get isLocked => _locked;

  /// 当前是否处于文件选择器 / 系统弹窗豁免窗口内（委托 [LockExemption]）。
  bool get _exempted => LockExemption.isActive;

  /// 文件选择器状态（导入/导出期间 inactive 不触发锁定——防误锁）。
  /// 新代码优先用 [runWithExemption]（try/finally 自动配对）；本方法保留
  /// 做兼容，true 刷新 TTL 上界。
  void setFilePickerActive(bool active) {
    if (active) {
      LockExemption.begin();
    } else {
      LockExemption.end();
    }
  }

  /// 作用域式豁免：[fn] 执行期间 inactive 不锁定，结束（或抛异常）自动
  /// 复位——调用方无需手写 try/finally，也不会因异常泄漏永久豁免。
  Future<T> runWithExemption<T>(Future<T> Function() fn) =>
      LockExemption.run(fn);

  /// onInactive：失去输入焦点（切后台/锁屏）——文件选择器运行中豁免——
  /// 否则立即锁定（密钥即刻清除——private_notes_light 模式）。
  void onInactive() {
    if (_exempted) {
      // 豁免期间：不置锁，但约定到点再来读一次 [LockExemption.isActive]——
      // TTL 惰性失效由此变成有明确时刻的事件，不再依赖「恰好有新信号」。
      _armExemptionWatch();
      return;
    }
    // 真实后台信号接管：挂起的宽限判定作废（与门组件同语义——两条计时
    // 不抢同一次宽限资格），直接锁定。
    _cancelPendingGrace();
    _lock();
  }

  /// 豁免窗口关闭（末位 end 或 TTL 到点）：人还没回前台 ⇒ 认定离席，
  /// 走宽限期落锁；TTL 到期视为调用方漏 end，**不给宽限资格**直接落锁。
  ///
  /// 人已回前台（`resumed`，或拿不到生命周期态）不构成离席，维持现状。
  void _onExemptionWindowClosed(bool ttlExpired) {
    _cancelExemptionWatch();
    if (_locked) return;
    final state = _lifecycleState;
    if (state == null || state == AppLifecycleState.resumed) return;
    if (ttlExpired) {
      _cancelPendingGrace();
      _lock();
      return;
    }
    _beginPendingGrace();
  }

  void _armExemptionWatch() {
    _exemptionWatchTimer?.cancel();
    final remaining = LockExemption.remaining;
    if (remaining <= Duration.zero) return; // 已经过期，下一读即失效
    _exemptionWatchTimer = Timer(remaining, _onExemptionWatchTick);
  }

  void _onExemptionWatchTick() {
    _exemptionWatchTimer = null;
    // 读 isActive 就是「到点复核」本身：过期 ⇒ 内部惰性清空并同步通知
    // [_onExemptionWindowClosed]；仍有效 ⇒ 期间有新的 begin 刷新过，重锚。
    if (LockExemption.isActive) _armExemptionWatch();
  }

  void _cancelExemptionWatch() {
    _exemptionWatchTimer?.cancel();
    _exemptionWatchTimer = null;
  }

  void _beginPendingGrace() {
    _cancelPendingGrace();
    if (graceDuration <= Duration.zero) {
      _lock();
      return;
    }
    _gracePending = true;
    _graceDeadlineTimer = Timer(graceDuration, _onGraceDeadline);
  }

  void _onGraceDeadline() {
    _graceDeadlineTimer = null;
    if (!_gracePending || _locked) return;
    _gracePending = false;
    _lock();
  }

  void _cancelPendingGrace() {
    _gracePending = false;
    _graceDeadlineTimer?.cancel();
    _graceDeadlineTimer = null;
  }

  void _lock() {
    if (_locked) return;
    _locked = true;
    onLock?.call();
  }

  /// onResume：回到前台——宽限内回来撤销挂起判定（P2-1 续项：`resumed`
  /// 先于宽限定时器到达 ⇒ 人已回来，媒体密钥不锁）；已锁定则触发再认证
  /// （环境可能已变化——不盲目信任之前状态——Flutter 安全指南）。
  void onResume() {
    _cancelPendingGrace();
    if (_locked) onReauthenticateRequired?.call();
  }

  /// 解锁成功（重新认证后——重置锁定状态）。
  ///
  /// 约束（审计 N-H7）：仅允许在调用方自有再认证流程成功完成后调用
  /// （PIN/系统验证通过后）；禁止在 deep-link、通知、测试钩子等未认证
  /// 路径调用——本类不持有认证证明，证明责任在调用方。
  void unlock() => _locked = false;

  void dispose() {
    _listener.dispose();
    // 与构造器里的 addWindowClosedListener 严格配对（监听者须自配对移除）。
    LockExemption.removeWindowClosedListener(_onExemptionWindowClosed);
    _cancelExemptionWatch();
    _cancelPendingGrace();
  }
}
