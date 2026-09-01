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
import 'package:drawing_notes_app/fix/security_and_sync_fix.dart'
    show PinPadCore;

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
