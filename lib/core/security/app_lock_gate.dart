// ============================================================================
// app_lock_gate.dart —— 应用启动锁门（2026-09-01）
// ============================================================================
//
// 包裹应用根内容（AppShell），负责三件事：
//   1. 冷启动加锁：已配置 PIN 则进门先解锁（加载完成前短暂空白防闪内容）；
//   2. 切后台/失焦回锁：监听应用生命周期，`inactive`（窗口失焦——桌面
//      「焦点切走、窗口仍可见」的唯一信号）/`hidden`（最小化）/`paused`
//      任一即置锁，回到前台直接见锁屏；三平台一致（桌面从不投递 paused，
//      旧版只认 paused ⇒ 桌面「只给 inactive」的纯失焦此前根本不锁）。
//      ——宽限期（2026-09-06，2026-10-04 重锚）：**第一个**后台锁信号
//      （inactive/hidden  whichever first）起单调秒表，service.graceDuration
//      内回前台自动放行（任务视图扫一眼不弹锁屏）；同一后台会话内的重复
//      信号（如 inactive 后再 hidden/paused）**不**重锚秒表，否则连切两下
//      会把宽限期刷新成「免锁」；系统时钟回拨绕不过单调秒表；
//      ——原生选择器豁免（2026-10-04）：文件对话框/系统权限弹窗抢焦点期间
//      失焦不算切后台（LockExemption 窗口，默认不豁免、5 分钟 TTL 上界），
//      否则门处理 inactive 会在导入/导出时假锁开屏。豁免期间不锚秒表 ⇒
//      对话框停留时长不吃宽限期。**窗口一关（末位 end，或 TTL 到点由定时器
//      主动失效）而应用仍不在前台时，宽限期从那一刻起表；等满宽限仍未
//      resumed ⇒ 落锁且不给宽限资格**（P2-1，2026-10-06）。此前这里两条
//      途径都不动作：「豁免期内离席 + 之后再无生命周期信号」会永远不锁，
//      而 TTL 到期只在有人来读 isActive 时才惰性生效。
//   3. 关闭联动：设置页关闭应用锁后立即放行。
//
// 回前台一律走同一条 AppLockService.verify 管线（防爆破失败计数 / 指数冷却 /
// v1→v2 透明升级 / 保险库解锁 / 快速解锁语义全数保持，新路径不获任何旁路）。
//
// 锁屏 UI 复用 shared/widgets/pin_pad.dart 的 [PinPadCore]
// （iOS 锁屏同款密码盘，与笔记本解锁完全一致的单一事实来源）。

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show FilteringTextInputFormatter, LengthLimitingTextInputFormatter;

import 'package:drawing_notes_app/core/theme/apple_design.dart';
import 'package:drawing_notes_app/core/security/app_lock_service.dart';
import 'package:drawing_notes_app/core/security/audit_logger.dart';
import 'package:drawing_notes_app/core/security/kek_session_cache.dart';
import 'package:drawing_notes_app/core/security/session_guard.dart'
    show LockExemption;
import 'package:drawing_notes_app/core/security/session_secrets.dart';
import 'package:drawing_notes_app/core/security/quick_unlock_service.dart';
import 'package:drawing_notes_app/core/security/vault_key_service.dart';
import 'package:drawing_notes_app/core/storage/password_reset_disk.dart';
import 'package:drawing_notes_app/core/security/vault_error_messages.dart';
import 'package:drawing_notes_app/l10n/app_localizations.dart';
import 'package:drawing_notes_app/shared/widgets/app_snack.dart';
import 'package:drawing_notes_app/shared/widgets/glass_dialog.dart';
import 'package:drawing_notes_app/shared/widgets/pin_pad.dart' show PinPadCore;
import 'package:drawing_notes_app/shared/widgets/unlock_sheets.dart'
    show UnlockFlow;

part 'app_lock_gate_views.dart';


/// 应用启动锁门组件。
///
/// 用法（组合根）：
/// ```dart
/// home: AppLockGate(
///   service: _appLockService,
///   vault: _vaultKeyService,
///   child: AppShell(...),
/// )
/// ```
class AppLockGate extends StatefulWidget {
  const AppLockGate({
    super.key,
    required this.service,
    this.vault,
    this.quickUnlock,
    this.awayDurationReader,
    this.desktopKeyboardInput,
    required this.child,
  });

  final AppLockService service;

  /// 主密钥保险库（批次①b）：PIN 校验通过的同时解锁保险库（同一位
  /// 开屏密码派生 KEK），解锁瞬间自动完成：
  /// - 已有保险库 → unlock（密钥入内存，文档解密可用）；
  /// - 保险库不存在（老用户升级首解）→ initialize（自动补建加密底座）。
  final VaultKeyService? vault;

  /// 系统验证快速解锁（批D1，可选注入）：就绪时锁屏出现「系统验证解锁」
  /// 按钮——Windows Hello 通过即解锁开屏。**仅作用于开屏锁**；单文件密码
  /// 解锁路径不经过本门，天然不受影响（用户 2026-09-02 拍板口径）。
  final QuickUnlockService? quickUnlock;

  /// 后台驻留时长读取器（测试注入）：默认 null → 用内部单调秒表。
  /// 宽限判定需要「离开超过 30s」的可控场景，真实秒表无法快进。
  @visibleForTesting
  final Duration Function()? awayDurationReader;

  /// 锁屏是否附带**物理键盘**输入通道（P2 可达性修复，2026-10-03）：
  /// 原实现只嵌 [PinPadCore] 九宫格，Windows 上只能用鼠标点 12 次。
  /// 默认（null）= 非手机/非 Web 平台自动开启；开启时九宫格**仍然在场**
  /// （鼠标/触屏通道不删，三输入并行），键盘通道与九宫格共用同一条
  /// `service.verify` 管线——防爆破计数与冷却一律不被绕过。
  /// 传 true/false 可强制（测试跨宿主确定性）。
  @visibleForTesting
  final bool? desktopKeyboardInput;

  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

// 锁屏视图段（_LockScreenOverlay 起）的 `Colors.white*`：D-15 豁免
// （DESIGN_SYSTEM §3.6）——沉浸层功能性对比度设计，不收编域令牌。
class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  bool _initialized = false;
  bool _locked = false;

  /// 本次锁定是否由「切后台」触发（冷启动锁定不吃宽限期）。
  bool _lockedFromBackground = false;

  /// 后台驻留单调秒表：**第一个非豁免后台信号**（inactive/hidden whichever
  /// first）起表，resumed 读数后归档（2026-10-04 重锚：旧版锚在 paused，
  /// 桌面从不投递 paused ⇒ 桌面宽限期事实上从未正确起表）。
  Stopwatch? _awayStopwatch;

  /// 豁免窗口关闭时应用仍不在前台（P2-1，2026-10-06）：宽限期从**窗口关闭**
  /// 起表，等满 `graceDuration` 还没等到 `resumed` ⇒ 认定人已离席，直接落锁。
  ///
  /// 为什么不在窗口关闭那一刻就地置锁：桌面原生对话框期间窗口**仍然可见并有帧**
  /// （与真后台「无帧可渲染」不同），就地锁会让用户每次导出/导入都看见一下锁屏。
  /// 走宽限期既能吸收「选完文件焦点立刻回来」这条常见路径，又不再留下
  /// 「豁免期内离席 + 之后再无生命周期信号 ⇒ 永远不锁」的空档——那条空档正是
  /// 此前的实际行为：豁免期间的失焦信号既不置锁也不锚表，而 TTL 到期只在有人
  /// 来读 `isActive` 时才惰性生效。
  bool _gracePending = false;
  Timer? _graceDeadlineTimer;

  /// 豁免窗口到期看门表（P2-1，2026-10-06）：**必须挂在门上而不是
  /// `LockExemption` 静态里**——进程级定时器会被任何一次未配对的 `begin()`
  /// 带进 `testWidgets` 的假时钟并以「Pending timers」判红（AW15 首推实测：
  /// `editor_insert_image_entry_test` 一条红，2219 通过）。门随组件 dispose
  /// 取消，测试树拆掉就干净。
  Timer? _exemptionWatchTimer;

  /// 豁免窗口内收到后台信号：不置锁、不锚表（那不算用户切后台），
  /// 但要**约定到点再来读一次** `isActive`——惰性失效由此变成有明确时刻的事件，
  /// 不再依赖「恰好有人来查」。到点读取会触发 [LockExemption] 的同步通知，
  /// 判定统一走 `_onExemptionWindowClosed`。
  void _armExemptionWatch() {
    _exemptionWatchTimer?.cancel();
    final remaining = LockExemption.remaining;
    if (remaining <= Duration.zero) return; // 已经过期，下一读即失效
    _exemptionWatchTimer = Timer(remaining, _onExemptionWatchTick);
  }

  void _onExemptionWatchTick() {
    _exemptionWatchTimer = null;
    if (!mounted) return;
    // 读 isActive 就是「到点复核」这件事本身：过期 ⇒ 内部惰性清空并同步通知；
    // 仍有效 ⇒ 说明期间有新的 begin 刷新过截止，重锚看门表。
    if (LockExemption.isActive) _armExemptionWatch();
  }

  void _cancelExemptionWatch() {
    _exemptionWatchTimer?.cancel();
    _exemptionWatchTimer = null;
  }

  /// 豁免窗口关闭事件的订阅句柄（与 `addWindowClosedListener` 严格配对）。
  void _onExemptionWindowClosed(bool ttlExpired) {
    _cancelExemptionWatch();
    if (!mounted || !widget.service.isConfigured || _locked) return;
    // 人已经回到前台（或拿不到生命周期态）：不构成离席，维持现状。
    final state = WidgetsBinding.instance.lifecycleState;
    if (state == null || state == AppLifecycleState.resumed) return;
    if (ttlExpired) {
      // TTL 到期 = 调用方漏 end 或选择器挂了 5 分钟以上，两种都不是「人还在」。
      // 直接落锁，不给宽限资格（审计留痕见 [AuditLogger]）。
      _lockWithoutGrace(reason: 'lock.exemption_ttl_expired');
      return;
    }
    _beginPendingGrace();
  }

  /// 从豁免窗口关闭起锚宽限期秒表，并挂一个到期即锁的定时器。
  void _beginPendingGrace() {
    _cancelPendingGrace();
    _awayStopwatch = Stopwatch()..start();
    _gracePending = true;
    final grace = widget.service.graceDuration;
    if (grace <= Duration.zero) {
      // 宽限关闭：窗口一结束就锁，与「切后台即锁」口径一致。
      _lockWithoutGrace(reason: 'lock.exemption_closed_no_grace');
      return;
    }
    _graceDeadlineTimer = Timer(grace, _onGraceDeadline);
  }

  void _onGraceDeadline() {
    _graceDeadlineTimer = null;
    if (!_gracePending || !mounted) return;
    // 等满宽限期仍未回到前台 ⇒ 视为离席。
    final away = widget.awayDurationReader?.call() ?? _awayStopwatch?.elapsed;
    final grace = widget.service.graceDuration;
    if (away != null && away < grace) return; // 时钟源异常短，交给 resumed 判定
    _lockWithoutGrace(reason: 'lock.exemption_grace_elapsed');
  }

  /// 落锁且**不**给予宽限资格：回前台必须重新验证。
  void _lockWithoutGrace({required String reason}) {
    _cancelPendingGrace();
    _cancelExemptionWatch();
    if (_locked) return;
    AuditLogger.log(reason, success: false, detail: 'grace_or_ttl');
    setState(() {
      _locked = true;
      _lockedFromBackground = false;
    });
    // 与「超宽限」同一收口：主密钥掉锁，此后加密读写 fail-closed。
    widget.vault?.lock();
    unawaited(_refreshQuickUnlock());
  }

  void _cancelPendingGrace() {
    _gracePending = false;
    _graceDeadlineTimer?.cancel();
    _graceDeadlineTimer = null;
  }

  /// 批D1：快速解锁是否就绪（平台支持 + 开关开 + 副本存在）。
  /// 锁屏出现时查询一次；切后台回锁时再查（设置页可能中途改过开关）。
  bool _quickUnlockReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.service.addListener(_onServiceChanged);
    LockExemption.addWindowClosedListener(_onExemptionWindowClosed);
    _restoreLockState();
  }

  Future<void> _restoreLockState() async {
    await widget.service.load();
    if (!mounted) return;
    setState(() {
      _initialized = true;
      // 冷启动即锁：已配置 PIN，进门先解锁（像 iPhone 开机一样）。
      _locked = widget.service.isConfigured;
    });
    await _refreshQuickUnlock();
  }

  /// 重新查询快速解锁就绪态（异步缺口后 mounted 自查）。
  Future<void> _refreshQuickUnlock() async {
    final ready = widget.quickUnlock == null
        ? false
        : await widget.quickUnlock!.isReady();
    if (!mounted) return;
    if (_quickUnlockReady != ready) {
      setState(() => _quickUnlockReady = ready);
    }
  }

  void _onServiceChanged() {
    if (!mounted) return;
    // 设置页关闭应用锁 → 立即放行。
    // （设置新 PIN 不触发当场加锁：用户已在应用内验证过身份。）
    if (!widget.service.isConfigured) {
      if (_locked) setState(() => _locked = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // N3 提速 B 方案（2026-09-02 定案）：hidden 即清 KEK 会话缓存
    // （fill(0) 擦除），不做超时等待——切后台敏感派生材料零驻留。
    // P1 联动（审计 M-05/M-09）：文件/笔记本/块文档会话口令与 DEK
    // 同一时机一并失效（此前仅 KEK 被清，口令驻留——口径拉齐）。
    // 豁免窗口内不清（2026-10-04）：原生选择器/系统弹窗抢焦点触发的 hidden
    // 不算切后台——否则笔记本导入选择器会顺手清掉本页正在用的会话口令。
    if (state == AppLifecycleState.hidden && !LockExemption.isActive) {
      KekSessionCache.instance.clear();
      SessionSecrets.clearAll();
    }
    // 切后台/失焦即置锁：inactive（桌面纯失焦——「焦点切走、窗口仍可见」
    // 的唯一信号，桌面从不投递 paused）/hidden（最小化）/paused（移动端
    // 整切后台）三信号统一走本分支——把触发源从旧版「只认 paused」补全为
    // 三平台一致。是否「真锁」仍由 resumed 判定：真后台无帧可渲染，置锁与
    // 放行在回前台的同一帧合并，宽限内用户直接看到内容、无锁屏闪现。
    if (_isBackgroundSignal(state)) {
      _onBackgroundSignal();
    }
    // 豁免窗口关闭后的挂起判定（P2-1）：`resumed` 先于到期定时器到达
    // ⇒ 人立刻回来了，宽限内放行；等满宽限没人回来由 _onGraceDeadline 落锁。
    if (state == AppLifecycleState.resumed && _gracePending && !_locked) {
      final away = widget.awayDurationReader?.call() ?? _awayStopwatch?.elapsed;
      final grace = widget.service.graceDuration;
      _cancelPendingGrace();
      if (away == null || (grace > Duration.zero && away < grace)) {
        _awayStopwatch = null;
      } else {
        _lockWithoutGrace(reason: 'lock.exemption_grace_elapsed');
      }
    }
    // 宽限判定：仅「切后台导致的锁定」有资格；每次后台只评估一次，
    // 评估后即失去资格（超宽限的锁必须输 PIN，随后的快速再切不重置）。
    if (state == AppLifecycleState.resumed &&
        _locked &&
        _lockedFromBackground) {
      final grace = widget.service.graceDuration;
      final away = widget.awayDurationReader?.call() ?? _awayStopwatch?.elapsed;
      _lockedFromBackground = false;
      _awayStopwatch = null;
      if (away != null && grace > Duration.zero && away < grace) {
        setState(() => _locked = false);
      } else {
        // 超出宽限期（或宽限关闭）：保险库掉锁（主密钥清零）。此前 hidden
        // 只清 KEK 缓存，主密钥整会话驻留内存——「锁定」只是 UI 门（安全
        // 审计 P1-1，2026-09-06）。掉锁后 storage 的 keyProvider 返回 null，
        // 加密文档读写 fail-closed；重新解锁走 PIN/快速解锁正常路径
        // （_unlockVault 重新派生并注入主密钥）。
        widget.vault?.lock();
        // P3-1（审计 2026-10-05）：与 hidden 分支同口径——超宽限落锁时
        // KEK 缓存与文件会话口令一并失效。此前清理只挂 hidden，桌面纯
        // inactive（失焦）超宽限后派生材料整会话驻留内存。
        KekSessionCache.instance.clear();
        SessionSecrets.clearAll();
      }
    }
  }

  /// 是否为「离开前台」的生命周期信号（三平台口径统一：桌面失焦给
  /// inactive、最小化给 hidden、移动端整切后台给 paused，任一都须锁）。
  static bool _isBackgroundSignal(AppLifecycleState state) =>
      state == AppLifecycleState.inactive ||
      state == AppLifecycleState.hidden ||
      state == AppLifecycleState.paused;

  /// 后台锁信号处理（2026-10-04「切后台全量锁定」核心）。
  ///
  /// 宽限期锚点 = 第一个「非豁免」后台信号（inactive/hidden whichever
  /// first）：本函数只在 `!_locked` 时推进锁定，而锁定一旦发生即持续到有
  /// 资格人在 resumed 放行——所以同一后台会话内的后续信号（例如 Windows
  /// 最小化链 resumed→inactive→hidden→paused）只会命中**第一个**去锚表，
  /// 其余信号因 `_locked` 已真直接返回，**不重锚**——这正是「连续快切不
  /// 重置宽限期资格」既有断言的根据。冷启动锁 / 关闭宽限外的手动锁同样
  /// 因 `_locked` 已真不进入本分支，不吃宽限（`_lockedFromBackground` 保持
  /// false，resumed 侧据其拒绝放行）。
  ///
  /// LockExemption 窗口内（原生文件对话框 / 系统权限弹窗 / 外部查看器抢
  /// 走 OS 焦点）既不置锁也不锚表：这不算用户切后台，且对话框停留时长不
  /// 应吃掉宽限期；末位释放后由回前台 resumed 按已锚定的宽限期秒表判定。
  void _onBackgroundSignal() {
    if (!widget.service.isConfigured || _locked) return;
    if (LockExemption.isActive) {
      // 豁免期间：既不置锁也不锚表，但约定到点再来复核（见 [_armExemptionWatch]）。
      _armExemptionWatch();
      return;
    }
    // 真实后台信号接管宽限期锚点：挂起态（由豁免窗口关闭起表）作废，
    // 否则两条秒表会抢同一个「每次后台只评估一次」的宽限资格。
    _cancelPendingGrace();
    setState(() {
      _locked = true;
      _lockedFromBackground = true;
    });
    // 锚在第一个后台信号（见上）。
    _awayStopwatch = Stopwatch()..start();
    // 回锁时重查快速解锁就绪态（设置页可能中途开/关过开关）。
    // 生命周期回调非 async：fire-and-forget（就绪态刷新失败仅影响按钮显隐）。
    unawaited(_refreshQuickUnlock());
  }

  @override
  void didUpdateWidget(covariant AppLockGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service) {
      oldWidget.service.removeListener(_onServiceChanged);
      widget.service.addListener(_onServiceChanged);
    }
  }

  @override
  void dispose() {
    widget.service.removeListener(_onServiceChanged);
    LockExemption.removeWindowClosedListener(_onExemptionWindowClosed);
    _cancelPendingGrace();
    _cancelExemptionWatch();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 放行（走同一条 verify 管线成功后的唯一收口）：清锁屏，并把后台会话态
  /// （秒表 + 宽限资格）一并归档——防止残留的旧秒表让下一次切后台吃到错误
  /// 的宽限读数。
  void _unlock() {
    _awayStopwatch = null;
    _lockedFromBackground = false;
    _cancelPendingGrace();
    setState(() => _locked = false);
  }

  /// 手机端判定（与 UnlockFlow 同口径）：Web 视为桌面（有物理键盘）。
  static bool get _isMobilePlatform =>
      !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  /// 是否叠加桌面物理键盘输入槽（P2 可达性修复）。
  bool get _useDesktopKeyboardInput =>
      widget.desktopKeyboardInput ?? !_isMobilePlatform;

  /// 开屏 PIN 校验的**唯一**入口（九宫格与桌面键盘槽共用）。
  ///
  /// 安全自查（键盘通道新增时逐条核对）：一律走 [AppLockService.verify]，
  /// 失败计数、指数冷却、v1→v2 透明升级与保险库解锁全部原样生效——
  /// 键盘路径不获得任何旁路；失败后若已进入冷却，立即重建锁屏换成
  /// [_CooldownView]（键盘槽随之销毁，冷却期内敲不动）。
  Future<bool> _verifyLockPin(String pin) async {
    final ok = await widget.service.verify(pin);
    if (!ok) {
      if (mounted && widget.service.isLockedOut) setState(() {});
      return false;
    }
    await _unlockVault(pin);
    return true;
  }

  /// 系统验证快速解锁（批D1）：Windows Hello 通过 → OS 凭据库副本注入
  /// 保险库 → 放行。失败（取消/未通过/副本异常）只提示，锁屏原状——
  /// PIN 通道永远可用（fail-closed）。
  Future<void> _startQuickUnlock() async {
    final quickUnlock = widget.quickUnlock;
    final vault = widget.vault;
    if (quickUnlock == null || vault == null) return;
    final ok = await quickUnlock.authenticateAndUnlock(vault: vault);
    if (!mounted) return;
    if (ok) {
      _unlock();
    } else {
      _snack(
        AppLocalizations.of(context)?.lockQuickUnlockFail ?? '系统验证未通过，请输入密码解锁',
      );
    }
  }

  // 轻量反馈：样式/时长/行为收敛至 AppSnack（与原内联 SnackBar 一致）。
  void _snack(String message) {
    if (!mounted) return;
    AppSnack.show(context, message);
  }

  /// 忘记密码流程（重置密码盘，冷却期内同样可用）。
  ///
  /// 链路：说明 → 选 U 盘 → 读 password_reset_disk.key → 两步输入新 PIN →
  /// 保险库槽 2 解包重置槽 1 → 重设开屏 PIN 哈希 → 清防爆破记录 → 放行。
  /// 任何一步失败都保持原状态（fail-closed，重试即可）。
  Future<void> _startForgotPassword() async {
    final vault = widget.vault;
    if (vault == null) {
      _snack(AppLocalizations.of(context)?.lockNoResetSupport ?? '当前版本不支持密码找回');
      return;
    }
    // 步骤 1：说明确认（诚实告知需要已绑定的重置密码盘）。
    final proceed = await GlassDialog.confirm(
      context,
      title: AppLocalizations.of(context)?.lockForgotTitle ?? '忘记密码',
      content:
          AppLocalizations.of(context)?.lockForgotBody ??
          '使用之前绑定的重置密码盘（U 盘）重设密码。\n\n'
              '未绑定重置密码盘时，密码无法找回。',
      confirmText: AppLocalizations.of(context)?.lockPickUsb ?? '选择 U 盘',
    );
    if (!proceed || !mounted) return;

    // 步骤 2：选取 U 盘目录（取消即静默返回）。原生目录选择器抢焦点会投
    // inactive/hidden——本门已处理 inactive 全量锁定，须豁免这一抢焦点窗口，
    // 否则 hidden 侧的 KEK/会话口令清理会在重置流程中途被误触发。
    final dir = await LockExemption.run(ResetDiskFile.pickDirectory);
    if (dir == null || !mounted) return;

    // 步骤 3：读取重置钥匙（fail-closed：文件缺失/无效即止步）。
    final externalKey = await ResetDiskFile.readFrom(dir);
    if (!mounted) return;
    if (externalKey == null) {
      _snack(
        AppLocalizations.of(context)?.lockNoResetDisk ??
            '未找到有效的重置密码盘文件（password_reset_disk.key）',
      );
      return;
    }

    // 步骤 4：两步输入新密码（长度沿用当前设置，之后可在设置页改）。
    final pinLength = widget.service.pinLength;
    final newPin = await UnlockFlow.show(
      context,
      title: AppLocalizations.of(context)?.lockSetNewPin ?? '设置新密码',
      pinLength: pinLength,
    );
    if (newPin == null || !mounted) return;
    final confirm = await UnlockFlow.show(
      context,
      title: AppLocalizations.of(context)?.lockConfirmNewPin ?? '确认新密码',
      pinLength: pinLength,
    );
    if (confirm == null || !mounted) return;
    if (confirm != newPin) {
      _snack(AppLocalizations.of(context)?.lockPinMismatch ?? '两次输入不一致，请重试');
      return;
    }

    // 步骤 5：执行重置。先重置保险库（核心，失败即止保持一致性），
    // 再重设开屏 PIN 哈希并清防爆破记录（纯偏好写入，失败概率极低；
    // 万一失败可用 U 盘再重置一次——重置通道本身可修复不一致）。
    try {
      await vault.resetPinWithUsbKey(externalKey: externalKey, newPin: newPin);
      await widget.service.setPin(newPin);
      await widget.service.resetGuard();
    } on VaultUnlockException catch (e) {
      if (!mounted) return;
      _snack(describeVaultError(e, AppLocalizations.of(context)));
      return;
    } catch (_) {
      if (!mounted) return;
      _snack(AppLocalizations.of(context)?.lockResetFail ?? '重置失败，请重试');
      return;
    }
    if (!mounted) return;
    _snack(AppLocalizations.of(context)?.lockResetOk ?? '密码已重置');
    _unlock();
  }

  /// 解锁 / 自动补建保险库（批次①b）。保险库异常不阻塞进入 UI——
  /// 加密文件读取仍需密钥（存储层 fail-closed），此处只影响体验。
  Future<void> _unlockVault(String pin) async {
    final vault = widget.vault;
    if (vault == null) return;
    try {
      if (await vault.isConfigured()) {
        if (!vault.isUnlocked) await vault.unlock(pin);
      } else if (await vault.hasOrphanBackupOnDisk()) {
        // STO-001 的默认阻断半边（业主 2026-10-16 点名「补建需显式确认」那一档）。
        // 先按**旧那一世**试解：`_readDoc` 有 `.bak` 回退腿，同一个密码很可能直接
        // 就能解开旧库——解得开就一支新密钥都不用生成。解不开才去问用户，因为
        // [VaultKeyService.initialize] 生成的是全新随机主密钥，落笔之后既有密文
        // 全部永久解不开（`.bak` 也会在下一次保险库写入时被盖掉）。
        if (!await _tryUnlockOldGeneration(vault, pin)) {
          if (!await _confirmRebuildOverOrphanBackup()) return;
          await _initializeVaultAndReport(vault, pin);
        }
      } else {
        // 老用户升级：已有 PIN 但尚无保险库 → 以同一位 PIN 补建。
        await _initializeVaultAndReport(vault, pin);
      }
    } catch (error) {
      // 不阻塞进入 UI（保险库异常时应用仍可读明文），但**必须让用户看见**：
      // 这是「PIN 校验通过、密钥却没到手」的唯一入口，该状态下一切加密写入
      // 都会 fail-closed 失败、密文读取读不出来、列表按 fail-closed 跳过
      // （表现为素材「看起来空了」）。此前 `catch (_) {}` 全静默，等于把一个
      // 可致丢数据的状态藏进不可观测的黑盒（2026-10-06 审计定性「先让它
      // 可见」）；AW13 已让下游保存失败可见，本条把根因提示补在入口处。
      // 只记错误类型，不带 message/堆栈（H-04「绝不落凭据」同口径）。
      AuditLogger.log(
        'app_lock.vault_unlock_failed',
        success: false,
        detail: error.runtimeType.toString(),
      );
      // 文案复用设置页解锁失败同款 arb 键（术语一致，零新增翻译）。
      // 不阻塞进入的取舍如实声明：拒绝放行会让保险库文件损坏的用户连
      // 导出/恢复的入口都没有——降级进入 + 可见警示优于不可恢复的锁死。
      if (!mounted) return;
      _snack(
        AppLocalizations.of(context)?.lockVaultUnlockFailed ??
            '保险库解锁失败，请重试',
      );
    }
  }

  /// 用当前 PIN 试解盘上那份**旧那一世**的保险库（走 `_readDoc` 的 `.bak` 回退腿）。
  /// 解得开 ⇒ 主密钥到手、一支新密钥都不生成；解不开 ⇒ false，由调用方去问用户。
  /// 只吞 [VaultUnlockException]（那正是「PIN 与旧副本不匹配」的判据本身），其余
  /// 异常照旧上抛给 `_unlockVault` 的 catch——IO 错误不能伪装成「密码不对」。
  Future<bool> _tryUnlockOldGeneration(
    VaultKeyService vault,
    String pin,
  ) async {
    try {
      await vault.unlock(pin);
      return true;
    } on VaultUnlockException {
      return false;
    }
  }

  /// 「以当前密码重建保险库」的显式确认——不可逆，默认拒绝。
  /// 用户不重建时仍放行进入 UI（与保险库异常同口径：连导出/恢复的入口都得留着）。
  Future<bool> _confirmRebuildOverOrphanBackup() async {
    if (!mounted) return false;
    final l10n = AppLocalizations.of(context);
    final proceed = await GlassDialog.confirm(
      context,
      title: l10n?.lockOrphanBackupTitle ?? '检测到旧保险库备份',
      content: l10n?.lockOrphanBackupBody ??
          '盘上有一份旧的保险库备份，但你刚输入的密码打不开它。\n\n'
              '以当前密码重建会生成一支全新主密钥：所有既有加密内容都将无法解开'
              '（旧备份会先另存一份保留件）。\n\n'
              '如果你还记得另一个密码，请选「先不重建」，之后可重试。',
      confirmText: l10n?.lockOrphanBackupConfirm ?? '确认重建',
      cancelText: l10n?.lockOrphanBackupCancel ?? '先不重建',
      dangerous: true,
    );
    if (proceed) return true;
    AuditLogger.log('app_lock.vault_rebuild_declined', success: false);
    if (mounted) {
      _snack(
        l10n?.lockOrphanBackupHeld ?? '已保留旧保险库，未重建；加密内容暂时解不开',
      );
    }
    return false;
  }

  /// 补建，并如实报告「这次补建盖住了另一世的主密钥」（STO-001 的可观测半边）。
  Future<void> _initializeVaultAndReport(
    VaultKeyService vault,
    String pin,
  ) async {
    final outcome = await vault.initialize(pin);
    if (outcome != VaultInitOutcome.preservedOrphanBackup) return;
    AuditLogger.log(
      'app_lock.vault_rebuilt_over_orphan_backup',
      success: false,
    );
    if (!mounted) return;
    _snack(
      AppLocalizations.of(context)?.lockVaultRebuiltOldBackupKept ??
          '已重新建立密码；检测到旧的保险库备份，已另存一份保留件',
    );
  }

  @override
  Widget build(BuildContext context) {
    // 初始化完成前保持空白：避免「先闪现内容、锁屏随后才盖上」。
    if (!_initialized) return const SizedBox.shrink();
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_locked)
          Positioned.fill(
            // 拦截 Android 系统返回键：锁屏状态下不允许绕过。
            child: PopScope(
              canPop: false,
              child: Stack(
                children: [
                  Positioned.fill(
                    // 批次③：冷却期内用倒计时面板替代密码盘（输不进去就不展示）。
                    // P2 可达性：冷却面板同样替换掉桌面键盘槽——键盘通道
                    // 不获得「冷却期继续猜」的能力（与九宫格同一闸门）。
                    child: widget.service.isLockedOut
                        ? _CooldownView(
                            service: widget.service,
                            onExpired: () => setState(() {}),
                          )
                        : PinPadCore(
                            title:
                                AppLocalizations.of(context)?.lockEnterPin ??
                                '输入密码',
                            // 开屏密码长度由设置页决定（批次②：4–12 位可选）。
                            pinLength: widget.service.pinLength,
                            onVerify: _verifyLockPin,
                            onAccepted: (_) => _unlock(),
                            // 桌面：九宫格之上叠加物理键盘输入槽（三输入并行，
                            // 九宫格不删——鼠标/触屏仍是可用通道）。
                            // 键盘槽只回「校验结果」，放行仍由本门做：与九宫格
                            // 的 onAccepted 同一收口（旧实现在这里只 verify 不
                            // _unlock，键盘输对密码锁屏不消失）。
                            keyboardInput: _useDesktopKeyboardInput
                                ? _DesktopPinField(
                                    pinLength: widget.service.pinLength,
                                    onSubmit: (pin) async {
                                      final ok = await _verifyLockPin(pin);
                                      if (ok) _unlock();
                                      return ok;
                                    },
                                  )
                                : null,
                          ),
                  ),
                  // 底部入口区（批D1）：快速解锁（就绪才显示）+ 忘记密码。
                  // 冷却期同样保留——系统验证不受防爆破冷却约束（它验的是
                  // 系统身份而非猜测 PIN），干等 24 小时没有意义。
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 28,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_quickUnlockReady && widget.vault != null)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppleSpacing.xxs,
                            ),
                            child: TextButton.icon(
                              onPressed: _startQuickUnlock,
                              icon: Icon(
                                Icons.fingerprint_rounded,
                                color: Colors.white.withValues(alpha: 0.9),
                                size: 22,
                              ),
                              label: Text(
                                AppLocalizations.of(context)
                                        ?.lockSystemUnlock ??
                                    '系统验证解锁',
                                style: AppleType.titleStyle(
                                  Colors.white.withValues(alpha: 0.9),
                                ),
                              ),
                            ),
                          ),
                        TextButton(
                          onPressed: _startForgotPassword,
                          child: Text(
                            AppLocalizations.of(context)?.lockForgotLink ??
                                '忘记密码？',
                            style: AppleType.controlStyle(
                              Colors.white.withValues(alpha: 0.75),
                              weight: FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}