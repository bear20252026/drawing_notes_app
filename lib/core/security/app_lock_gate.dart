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
import 'package:drawing_notes_app/core/security/vault_key_service.dart';
import 'package:drawing_notes_app/core/storage/password_reset_disk.dart';
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
    required this.child,
  });

  final AppLockService service;

  /// 主密钥保险库（批次①b）：PIN 校验通过的同时解锁保险库（同一位
  /// 开屏密码派生 KEK），解锁瞬间自动完成：
  /// - 已有保险库 → unlock（密钥入内存，文档解密可用）；
  /// - 保险库不存在（老用户升级首解）→ initialize（自动补建加密底座）。
  final VaultKeyService? vault;

  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  bool _initialized = false;
  bool _locked = false;

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
    // 切后台即置锁：回到前台时锁屏已在最上层（iOS 同款行为）。
    if (state == AppLifecycleState.paused &&
        widget.service.isConfigured &&
        !_locked) {
      setState(() => _locked = true);
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
    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('忘记密码'),
        content: const Text(
          '使用之前绑定的重置密码盘（U 盘）重设密码。\n\n'
          '未绑定重置密码盘时，密码无法找回。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('选择 U 盘'),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;

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
                  // 忘记密码入口（冷却期与正常锁屏均可用——
                  // 被锁 24 小时干等没有意义，重置密码盘正是为此而设）。
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 28,
                    child: Center(
                      child: TextButton(
                        onPressed: _startForgotPassword,
                        child: Text(
                          '忘记密码？',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.75),
                            fontSize: 14,
                          ),
                        ),
                      ),
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

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (!widget.service.isLockedOut) {
        widget.onExpired();
      } else {
        setState(() {}); // 刷新倒计时
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String get _remainingText {
    final remaining = widget.service.lockoutRemaining;
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
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
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
                Text(
                  '请在 $_remainingText 后重试',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontSize: 15,
                  ),
                ),
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
