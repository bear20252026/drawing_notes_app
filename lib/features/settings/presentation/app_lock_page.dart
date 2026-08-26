import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/security/app_lock_service.dart';
import '../../../core/abstractions/router/app_router.dart';

/// 应用锁定页面 — 应用启动时的密码输入界面。
///
/// - 使用与 password_disk_page.dart 一致的视觉风格（Apple Pin Input）
/// - 支持连续失败阶梯锁定倒计时
/// - 支持生物识别（如果平台支持）
class AppLockPage extends StatefulWidget {
  const AppLockPage({super.key});

  @override
  State<AppLockPage> createState() => _AppLockPageState();
}

class _AppLockPageState extends State<AppLockPage>
    with SingleTickerProviderStateMixin {
  final AppLockService _service = AppLockService.instance;

  String _pin = '';
  String? _errorText;
  bool _loading = false;
  Timer? _countdownTimer;
  Duration _remainingLock = Duration.zero;

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
    if (_service.isLocked) {
      _updateRemainingLock();
      _countdownTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _updateRemainingLock(),
      );
    }
  }

  void _updateRemainingLock() {
    if (!_service.isLocked) {
      _countdownTimer?.cancel();
      setState(() {
        _remainingLock = Duration.zero;
        _errorText = null;
      });
      return;
    }

    setState(() {
      _remainingLock = _service.remainingLockTime;
      _errorText = _formatLockTime(_remainingLock);
    });
  }

  String _formatLockTime(Duration duration) {
    if (duration.inMinutes >= 60) {
      final h = duration.inHours;
      final m = duration.inMinutes % 60;
      return '已锁定，请 ${h}小时${m}分钟后重试';
    } else if (duration.inSeconds >= 60) {
      final m = duration.inMinutes;
      final s = duration.inSeconds % 60;
      return '已锁定，请 ${m}分${s}秒后重试';
    } else {
      return '已锁定，请 ${duration.inSeconds}秒后重试';
    }
  }

  void _onKeyPressed(String value) {
    if (_service.isLocked || _loading) return;

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

      // 输入 6 位后自动验证
      if (_pin.length == 6) {
        _verify();
      }
    }
  }

  Future<void> _verify() async {
    setState(() {
      _loading = true;
    });

    final success = await _service.verifyPassword(_pin);

    if (!mounted) return;

    setState(() {
      _loading = false;
    });

    if (success) {
      // 验证成功，跳转到首页
      context.go(RoutePaths.home);
    } else {
      // 验证失败
      _shakeController.forward(from: 0);
      setState(() {
        _pin = '';
        _errorText = '密码错误，请重试（${_service.failedAttempts}/${AppLockService.maxFailedAttempts}）';
      });

      // 检查是否触发锁定
      if (_service.isLocked) {
        _startCountdownIfNeeded();
      }
    }
  }

  Future<void> _authenticateBiometric() async {
    // TODO: 集成 local_auth 后实现生物识别验证
    // final localAuth = LocalAuthentication();
    // final didAuthenticate = await localAuth.authenticate(
    //   localizedReason: '请验证身份以解锁应用',
    //   options: const AuthenticationOptions(biometricOnly: true),
    // );
    // if (didAuthenticate) {
    //   _service.markBiometricAuthenticated();
    //   context.go(RoutePaths.home);
    // }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final pinDotsSize = screenWidth < 400 ? 10.0 : 12.0;
    final pinDotsSpacing = screenWidth < 400 ? 12.0 : 16.0;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ─── 锁图标 ───
                Icon(
                  Icons.lock_outline_rounded,
                  size: 64,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
                const SizedBox(height: 16),

                // ─── 标题 ───
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

                // ─── PIN 圆点 ───
                AnimatedBuilder(
                  animation: _shakeAnimation,
                  builder: (context, child) {
                    final offset = _service.isLocked
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
                            width: pinDotsSize,
                            height: pinDotsSize,
                            margin: EdgeInsets.symmetric(
                              horizontal: pinDotsSpacing / 2,
                            ),
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

                // ─── 错误/锁定提示 ───
                if (_errorText != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _errorText!,
                    style: TextStyle(
                      fontSize: 13,
                      color: _service.isLocked
                          ? const Color(0xFFFF9500)
                          : const Color(0xFFFF3B30),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],

                // ─── 加载指示器 ───
                if (_loading) ...[
                  const SizedBox(height: 24),
                  const CupertinoActivityIndicator(radius: 14),
                ],

                const SizedBox(height: 32),

                // ─── 数字键盘 ───
                if (!_service.isLocked && !_loading) _buildNumpad(),

                // ─── 生物识别按钮（预留） ───
                if (_service.biometricEnabled && !_service.isLocked) ...[
                  const SizedBox(height: 24),
                  TextButton.icon(
                    onPressed: _authenticateBiometric,
                    icon: const Icon(Icons.fingerprint, size: 28),
                    label: const Text('使用生物识别'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNumpad() {
    final keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', '⌫'],
    ];

    return Column(
      children: keys.map((row) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: row.map((key) {
              if (key.isEmpty) {
                return const SizedBox(width: 72, height: 72);
              }
              return _buildKey(key);
            }).toList(),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildKey(String value) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isDelete = value == '⌫';

    return GestureDetector(
      onTap: () => _onKeyPressed(value),
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
        ),
        alignment: Alignment.center,
        child: isDelete
            ? Icon(
                Icons.backspace_outlined,
                size: 24,
                color: isDark ? Colors.white70 : Colors.black54,
              )
            : Text(
                value,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w300,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
      ),
    );
  }
}
