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

import 'package:flutter/material.dart';

import 'package:drawing_notes_app/core/security/app_lock_service.dart';
import 'package:drawing_notes_app/fix/security_and_sync_fix.dart'
    show PinPadCore;

/// 应用启动锁门组件。
///
/// 用法（组合根）：
/// ```dart
/// home: AppLockGate(
///   service: _appLockService,
///   child: AppShell(...),
/// )
/// ```
class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key, required this.service, required this.child});

  final AppLockService service;
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
              child: PinPadCore(
                title: '输入密码',
                onVerify: (pin) => widget.service.verify(pin),
                onAccepted: (_) => _unlock(),
              ),
            ),
          ),
      ],
    );
  }
}
