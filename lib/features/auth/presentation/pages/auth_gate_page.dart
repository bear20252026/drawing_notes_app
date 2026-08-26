import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../application/auth_service.dart';
import '../../application/biometric_service.dart';
import '../widgets\pin_pad.dart';

/// 认证门控页面 — 应用启动时的密码输入界面。
///
/// 替代原有的 AppLockPage，作为统一的认证入口。
class AuthGatePage extends StatefulWidget {
  final AuthService authService;
  final BiometricService biometricService;

  const AuthGatePage({
    super.key,
    required this.authService,
    required this.biometricService,
  });

  @override
  State<AuthGatePage> createState() => _AuthGatePageState();
}

class _AuthGatePageState extends State<AuthGatePage>
    with SingleTickerProviderStateMixin {
  String _pin = '';
  String? _errorText;
  bool _loading = false;
  Timer? _countdownTimer;
  int _remainingLockSeconds = 0;

  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticOut),
    );

    _startCountdownIfNeeded();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _shakeController.dispose();
    super.dispose();
  }

  void _startCountdownIfNeeded() {
    if (widget.authService.session.isLocked) {
      _updateRemainingLock();
      _countdownTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _updateRemainingLock(),
      );
    }
  }

  void _updateRemainingLock() {
    final remaining = widget.authService.session.remainingLockSeconds;
    if (remaining == null || remaining <= 0) {
      _countdownTimer?.cancel();
      setState(() {
        _remainingLockSeconds = 0;
        _errorText = null;
      });
      return;
    }

    setState(() {
      _remainingLockSeconds = remaining;
      _errorText = _formatLockTime(remaining);
    });
  }

  String _formatLockTime(int seconds) {
    if (seconds >= 3600) {
      final h = seconds ~/ 3600;
      final m = (seconds % 3600) ~/ 60;
      return '已锁定，请 ${h}小时${m}分钟后重试';
    } else if (seconds >= 60) {
      final m = seconds ~/ 60;
      final s = seconds % 60;
      return '已锁定，请 ${m}分${s}秒后重试';
    } else {
      return '已锁定，请 ${seconds}秒后重试';
    }
  }

  void _onKeyPressed(String value) {
    if (widget.authService.session.isLocked || _loading) return;

    setState(() {
      _errorText = null;
    });

    if (value == '⌫') {
      if (_pin.isNotEmpty) {
        setState(() {
          _pin = _pin.substring(0, _pin.length - 1);
        });
      }
      return;
    }

    if (_pin.length < 6) {
      setState(() {
        _pin += value;
      });

      if (_pin.length == 6) {
        _verify();
      }
    }
  }

  Future<void> _verify() async {
    setState(() {
      _loading = true;
    });

    final result = await widget.authService.verifyPassword(_pin);

    if (!mounted) return;

    setState(() {
      _loading = false;
    });

    if (result.isSuccess) {
      context.go('/');
    } else {
      _shakeController.forward(from: 0);
      setState(() {
        _pin = '';
        final attempts = widget.authService.session;
        final failedCount = attempts is UnauthenticatedSession
            ? attempts.failedAttempts
            : 0;
        _errorText = '密码错误，请重试（${failedCount}/5）';
      });

      if (widget.authService.session.isLocked) {
        _startCountdownIfNeeded();
      }
    }
  }

  Future<void> _authenticateBiometric() async {
    final result = await widget.biometricService.authenticate(
      reason: '请验证身份以解锁应用',
    );

    if (result.isSuccess) {
      widget.authService.markBiometricAuthenticated();
      if (mounted) context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isLocked = widget.authService.session.isLocked;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  size: 64,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
                const SizedBox(height: 16),
                Text(
                  '应用已锁定',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '请输入密码以解锁应用',
                  style: TextStyle(
                    fontSize: 15,
                    color: isDark ? Colors.white54 : Colors.black38,
                  ),
                ),
                const SizedBox(height: 40),

                // PIN 圆点
                AnimatedBuilder(
                  animation: _shakeAnimation,
                  builder: (context, child) {
                    final offset = isLocked
                        ? 0.0
                        : (1 - _shakeAnimation.value) * 8 *
                            ((_shakeController.value * 2).floor() % 2 == 0
                                ? 1
                                : -1);
                    return Transform.translate(
                      offset: Offset(offset, 0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(6, (index) {
                          final filled = index < _pin.length;
                          return Container(
                            width: 12,
                            height: 12,
                            margin: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: filled
                                  ? (isDark ? Colors.white : Colors.black)
                                  : (isDark ? Colors.white24 : Colors.black12),
                            ),
                          );
                        }),
                      ),
                    );
                  },
                ),

                if (_errorText != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _errorText!,
                    style: TextStyle(
                      fontSize: 13,
                      color: isLocked
                          ? const Color(0xFFFF9500)
                          : const Color(0xFFFF3B30),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],

                if (_loading) ...[
                  const SizedBox(height: 24),
                  const CupertinoActivityIndicator(radius: 14),
                ],

                const SizedBox(height: 32),

                if (!isLocked && !_loading)
                  PinPad(
                    onKeyPressed: _onKeyPressed,
                    disabled: isLocked,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
