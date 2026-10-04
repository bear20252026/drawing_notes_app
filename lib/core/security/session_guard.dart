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
/// 释放（末位 [end] 或到期）后不做额外动作：门在下一个生命周期信号
/// （回前台 `resumed` 或残留的后台信号）即按锚定的宽限期秒表判定，
/// 豁免期间不锚表 ⇒ 原生对话框停留时长不吃宽限期。
class LockExemption {
  LockExemption._();

  /// 超时上界：5 分钟。取一档远大于任何一次原生选择器人工耗时（含
  /// U 盘浏览 / 网络盘定位）的上限；超过即视为调用方漏 end，豁免过期，
  /// 门恢复「切后台即锁」。SessionGuard 原 TTL 同取 5 分钟，口径拉齐。
  static const Duration ttl = Duration(minutes: 5);

  /// 单调秒表（进程生命周期常驻）——截止只相对它读数，免疫系统时钟调整。
  static final Stopwatch _mono = Stopwatch()..start();

  static int _depth = 0;
  static int _untilMonoMs = 0;

  /// 当前是否处于豁免窗口内（计数 > 0 且未超 TTL）。
  static bool get isActive {
    if (_depth <= 0) return false;
    if (_mono.elapsedMilliseconds >= _untilMonoMs) {
      _clear(); // TTL 到期：就地失效（免死金牌不会永续）。
      return false;
    }
    return true;
  }

  /// 开启一层豁免（刷新 TTL 截止）。与 [end] 严格配对。
  static void begin() {
    _depth++;
    _untilMonoMs = _mono.elapsedMilliseconds + ttl.inMilliseconds;
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

  static void _clear() {
    _depth = 0;
    _untilMonoMs = 0;
  }

  /// 当前剩余豁免时长（不在窗口内为 0；诊断 / 测试用）。
  static Duration get remaining => Duration(
    milliseconds: _depth > 0
        ? (_untilMonoMs - _mono.elapsedMilliseconds).clamp(0, 1 << 30)
        : 0,
  );

  /// 测试复位（清空计数与截止）——避免用例间全局窗口串味。
  @visibleForTesting
  static void resetForTest() => _clear();
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
  SessionGuard({this.onLock, this.onReauthenticateRequired}) {
    _listener = AppLifecycleListener(
      onInactive: onInactive,
      onResume: onResume,
    );
  }

  /// 锁定回调（调用方清除媒体密钥——MediaCryptoService.clearSessionKey——
  /// 并标记 UI 锁定状态）。
  final VoidCallback? onLock;

  /// 再认证回调（onResume 时已锁定——导航回解锁/密码输入页）。
  final VoidCallback? onReauthenticateRequired;

  late final AppLifecycleListener _listener;

  bool _locked = false;

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
    if (_exempted) return;
    _lock();
  }

  void _lock() {
    if (_locked) return;
    _locked = true;
    onLock?.call();
  }

  /// onResume：回到前台——已锁定则触发再认证（环境可能已变化——不盲目
  /// 信任之前状态——Flutter 安全指南）。
  void onResume() {
    if (_locked) onReauthenticateRequired?.call();
  }

  /// 解锁成功（重新认证后——重置锁定状态）。
  ///
  /// 约束（审计 N-H7）：仅允许在调用方自有再认证流程成功完成后调用
  /// （PIN/系统验证通过后）；禁止在 deep-link、通知、测试钩子等未认证
  /// 路径调用——本类不持有认证证明，证明责任在调用方。
  void unlock() => _locked = false;

  void dispose() => _listener.dispose();
}
