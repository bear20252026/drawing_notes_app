// ============================================================================
// app_lock_gate.dart —— 应用启动锁门（2026-09-01）
// ============================================================================
//
// 包裹应用根内容（AppShell），负责三件事：
//   1. 冷启动加锁：已配置 PIN 则进门先解锁（加载完成前短暂空白防闪内容）；
//   2. 切后台回锁：监听应用生命周期，paused 即置锁，回到前台直接见锁屏；
//   3. 关闭联动：设置页关闭应用锁后立即放行。
//
// 锁屏 UI 复用 fix/security_and_sync_fix.dart 的 [PinPadCore]
// （iOS 锁屏同款密码盘，与笔记本解锁完全一致的单一事实来源）。

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:drawing_notes_app/core/security/app_lock_service.dart';
import 'package:drawing_notes_app/core/security/kek_session_cache.dart';
import 'package:drawing_notes_app/core/security/session_secrets.dart';
import 'package:drawing_notes_app/core/security/quick_unlock_service.dart';
import 'package:drawing_notes_app/core/security/vault_key_service.dart';
import 'package:drawing_notes_app/core/storage/password_reset_disk.dart';
import 'package:drawing_notes_app/core/theme/apple_design.dart';
import 'package:drawing_notes_app/fix/security_and_sync_fix.dart'
    show PinPadCore, UnlockFlow;

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

  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  bool _initialized = false;
  bool _locked = false;

  /// 批D1：快速解锁是否就绪（平台支持 + 开关开 + 副本存在）。
  /// 锁屏出现时查询一次；切后台回锁时再查（设置页可能中途改过开关）。
  bool _quickUnlockReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.service.addListener(_onServiceChanged);
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
    if (state == AppLifecycleState.hidden) {
      KekSessionCache.instance.clear();
      SessionSecrets.clearAll();
    }
    // 切后台即置锁：回到前台时锁屏已在最上层（iOS 同款行为）。
    if (state == AppLifecycleState.paused &&
        widget.service.isConfigured &&
        !_locked) {
      setState(() => _locked = true);
      // 回锁时重查快速解锁就绪态（设置页可能中途开/关过开关）。
      // 生命周期回调非 async：fire-and-forget（就绪态刷新失败仅影响按钮显隐）。
      unawaited(_refreshQuickUnlock());
    }
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
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _unlock() => setState(() => _locked = false);

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
      _snack('系统验证未通过，请输入密码解锁');
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// 忘记密码流程（重置密码盘，冷却期内同样可用）。
  ///
  /// 链路：说明 → 选 U 盘 → 读 password_reset_disk.key → 两步输入新 PIN →
  /// 保险库槽 2 解包重置槽 1 → 重设开屏 PIN 哈希 → 清防爆破记录 → 放行。
  /// 任何一步失败都保持原状态（fail-closed，重试即可）。
  Future<void> _startForgotPassword() async {
    final vault = widget.vault;
    if (vault == null) {
      _snack('当前版本不支持密码找回');
      return;
    }
    // 步骤 1：说明确认（诚实告知需要已绑定的重置密码盘）。
    final proceed = await AppleDialog.confirm(
      context,
      title: '忘记密码',
      content:
          '使用之前绑定的重置密码盘（U 盘）重设密码。\n\n'
          '未绑定重置密码盘时，密码无法找回。',
      confirmText: '选择 U 盘',
    );
    if (!proceed || !mounted) return;

    // 步骤 2：选取 U 盘目录（取消即静默返回）。
    final dir = await ResetDiskFile.pickDirectory();
    if (dir == null || !mounted) return;

    // 步骤 3：读取重置钥匙（fail-closed：文件缺失/无效即止步）。
    final externalKey = await ResetDiskFile.readFrom(dir);
    if (!mounted) return;
    if (externalKey == null) {
      _snack('未找到有效的重置密码盘文件（password_reset_disk.key）');
      return;
    }

    // 步骤 4：两步输入新密码（长度沿用当前设置，之后可在设置页改）。
    final pinLength = widget.service.pinLength;
    final newPin = await UnlockFlow.show(
      context,
      title: '设置新密码',
      pinLength: pinLength,
    );
    if (newPin == null || !mounted) return;
    final confirm = await UnlockFlow.show(
      context,
      title: '确认新密码',
      pinLength: pinLength,
    );
    if (confirm == null || !mounted) return;
    if (confirm != newPin) {
      _snack('两次输入不一致，请重试');
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
      _snack(e.reason);
      return;
    } catch (_) {
      _snack('重置失败，请重试');
      return;
    }
    if (!mounted) return;
    _snack('密码已重置');
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
      } else {
        // 老用户升级：已有 PIN 但尚无保险库 → 以同一位 PIN 补建。
        await vault.initialize(pin);
      }
    } catch (_) {
      // fail-closed 兜底在存储层；此处静默避免锁死 UI。
    }
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
                    child: widget.service.isLockedOut
                        ? _CooldownView(
                            service: widget.service,
                            onExpired: () => setState(() {}),
                          )
                        : PinPadCore(
                            title: '输入密码',
                            // 开屏密码长度由设置页决定（批次②：4–12 位可选）。
                            pinLength: widget.service.pinLength,
                            onVerify: (pin) async {
                              final ok = await widget.service.verify(pin);
                              if (!ok) return false;
                              await _unlockVault(pin);
                              return true;
                            },
                            onAccepted: (_) => _unlock(),
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
                            padding: const EdgeInsets.only(bottom: 4),
                            child: TextButton.icon(
                              onPressed: _startQuickUnlock,
                              icon: Icon(
                                Icons.fingerprint_rounded,
                                color: Colors.white.withValues(alpha: 0.9),
                                size: 22,
                              ),
                              label: Text(
                                '系统验证解锁',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        TextButton(
                          onPressed: _startForgotPassword,
                          child: Text(
                            '忘记密码？',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.75),
                              fontSize: 14,
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

/// 批次③：冷却倒计时面板（视觉与 PinPadCore 锁屏一致：模糊 + 深色底）。
/// 每秒自检；冷却结束回调父级切回密码盘。
class _CooldownView extends StatefulWidget {
  const _CooldownView({required this.service, required this.onExpired});

  final AppLockService service;
  final VoidCallback onExpired;

  @override
  State<_CooldownView> createState() => _CooldownViewState();
}

class _CooldownViewState extends State<_CooldownView> {
  Timer? _ticker;

  /// U3 P1-11：每秒跳动的 tick 计数——仅驱动内层 [_RemainingText]
  /// 重建，父层 BackdropFilter/ClipRect/Column 静态子树不再每秒重建。
  final ValueNotifier<int> _tick = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (!widget.service.isLockedOut) {
        widget.onExpired();
      } else {
        _tick.value++; // 刷新倒计时（原 setState 整层重建已下沉）
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _tick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        // U3 P1-11：sigma 30→18——视觉差异极小，GPU 模糊开销显著降低。
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          color: Colors.black.withValues(alpha: 0.38),
          child: SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.hourglass_top_rounded,
                  color: Colors.white,
                  size: 44,
                ),
                const SizedBox(height: 18),
                const Text(
                  '尝试次数过多',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                _RemainingText(service: widget.service, tick: _tick),
                const SizedBox(height: 6),
                Text(
                  '为防止暴力猜测，密码验证已暂时锁定',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 冷却倒计时文本（U3 P1-11：下沉为内部小 widget）。
///
/// 每秒 tick 只重建这一行 Text，不再拖动整个模糊面板。
class _RemainingText extends StatelessWidget {
  const _RemainingText({required this.service, required this.tick});

  final AppLockService service;
  final ValueNotifier<int> tick;

  String _format(Duration remaining) {
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds % 60;
    if (minutes >= 60) {
      final hours = remaining.inHours;
      final mins = minutes % 60;
      return '$hours 小时 $mins 分';
    }
    return '$minutes 分 $seconds 秒';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: tick,
      builder: (context, _, _) {
        return Text(
          '请在 ${_format(service.lockoutRemaining)} 后重试',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.82),
            fontSize: 15,
          ),
        );
      },
    );
  }
}
