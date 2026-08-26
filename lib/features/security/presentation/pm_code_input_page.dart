/// PM码（胁迫密码）输入页面 — 伪装模式入口。
///
/// 在密码盘页面中，用户可以长按或特殊手势进入PM码输入界面。
/// 输入正确的PM码后，应用进入伪装模式，显示假笔记数据。
///
/// 设计参考：
/// - CipherVault stealth mode (github.com/vipecoder228/CipherVault) — MIT
/// - pam_duress (github.com/rafket/pam_duress) — GPL-2.0
/// - Sanctum (github.com/Teycir/Sanctum) — 零信任伪装
///
/// 版权声明：本实现借鉴了上述开源项目的设计理念，遵循各自许可证要求。
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/pm_code_provider.dart';
import '../../../../core/security/interfaces/pm_code_service.dart';
import '../../../../core/theme/app_design.dart';
import '../../../../core/ui/widgets/apple_pin_input.dart';
import '../../../../core/ui/widgets/ios_dialog.dart';

/// PM码输入页面。
///
/// 进入伪装模式的入口。使用方式：
/// - 从密码盘页面长按Logo进入
/// - 从应用启动页的隐藏入口进入
/// - 伪装模式下所有数据操作都指向 Slot B（伪装数据）
class PmCodeInputPage extends ConsumerStatefulWidget {
  const PmCodeInputPage({super.key});

  /// 路由路径。
  static const String routePath = '/pm-code-input';

  @override
  ConsumerState<PmCodeInputPage> createState() => _PmCodeInputPageState();
}

class _PmCodeInputPageState extends ConsumerState<PmCodeInputPage>
    with SingleTickerProviderStateMixin {
  /// PIN 输入的 GlobalKey（用于触发错误动画）。
  final _pinInputKey = GlobalKey();

  /// 错误消息。
  String? _errorMessage;

  /// 渐进式延迟（连续错误后增加延迟）。
  int _retryCount = 0;

  /// 是否正在验证中。
  bool _isVerifying = false;

  /// PM码是否已配置。
  bool _isConfigured = true;

  /// Shake 动画控制器。
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: _ShakeCurve()),
    );

    _checkPmCodeConfigured();
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  Future<void> _checkPmCodeConfigured() async {
    final pmCodeService = ref.read(pmCodeServiceProvider);
    final configured = await pmCodeService.isConfigured();
    if (mounted) {
      setState(() => _isConfigured = configured);
    }
  }

  Future<void> _onPinCompleted(String pin) async {
    if (_isVerifying) return;

    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });

    // 渐进式延迟（连续错误后等待更长时间）
    if (_retryCount > 0) {
      final delay = Duration(seconds: _retryCount * 2);
      await Future<void>.delayed(delay);
    }

    final pmCodeService = ref.read(pmCodeServiceProvider);
    final (result, _) = await pmCodeService.verifyPmCode(pmCode: pin);

    if (!mounted) return;

    switch (result) {
      case PmCodeVerifyResult.success:
        _retryCount = 0;
        HapticFeedback.heavyImpact();
        _enterDecoyMode();

      case PmCodeVerifyResult.wrongPassword:
        _retryCount++;
        HapticFeedback.heavyImpact();
        setState(() {
          _errorMessage = 'PM码不正确';
          _isVerifying = false;
        });
        _shakeController.forward(from: 0);

      case PmCodeVerifyResult.notConfigured:
        setState(() {
          _errorMessage = 'PM码未设置';
          _isVerifying = false;
        });
        break;

      case PmCodeVerifyResult.corrupted:
        setState(() {
          _errorMessage = '数据已损坏';
          _isVerifying = false;
        });
        break;

      case PmCodeVerifyResult.rateLimited:
        setState(() {
          _errorMessage = '请稍后再试';
          _isVerifying = false;
        });
        break;
    }
  }

  void _enterDecoyMode() {
    showIosDialog<bool>(
      context,
      title: '伪装模式已激活',
      content: '当前显示的是伪装数据。\n\n'
          '提示：您看到的笔记内容为自动生成的伪装数据，\n'
          '与您的真实笔记完全独立。',
      actions: const [
        IosDialogAction(label: '了解', result: true, isDefault: true),
      ],
    ).then((_) {
      if (mounted) {
        // 在实际应用中导航到主页（伪装数据视图）
        // context.go('/home?mode=decoy');
        Navigator.of(context).pop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppDesign.surfaceBlack : AppDesign.canvasParchment,
      body: SafeArea(
        child: Column(
          children: [
            // ── 顶部返回按钮 ──
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 8, top: 8),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                  onPressed: () => context.pop(),
                ),
              ),
            ),

            const Spacer(flex: 2),

            // ── 图标 ──
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: isDark
                    ? AppDesign.appleOrange.withValues(alpha: 0.15)
                    : AppDesign.appleOrange.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.shield_outlined,
                size: 36,
                color: AppDesign.appleOrange,
              ),
            ),

            const SizedBox(height: 20),

            // ── 标题 ──
            Text(
              'PM码',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                color: isDark ? AppDesign.bodyOnDark : AppDesign.ink,
              ),
            ),

            const SizedBox(height: 8),

            // ── 副标题 ──
            Text(
              '输入胁迫密码以进入伪装模式',
              style: TextStyle(
                fontSize: 15,
                color: isDark ? AppDesign.bodyMuted : AppDesign.inkMuted48,
              ),
            ),

            const SizedBox(height: 40),

            // ── PIN 输入 ──
            AnimatedBuilder(
              animation: _shakeAnimation,
              builder: (context, child) {
                final t = _shakeAnimation.value;
                final offset = t < 0.5 ? t * 20 : (1 - t) * 20;
                return Transform.translate(
                  offset: Offset(offset, 0),
                  child: child,
                );
              },
              child: ApplePinInput(
                key: _pinInputKey,
                length: 6,
                obscureText: true,
                onCompleted: _onPinCompleted,
              ),
            ),

            const SizedBox(height: 16),

            // ── 错误消息 ──
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFFFF3B30),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

            // ── 渐进式延迟提示 ──
            if (_retryCount > 2)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '连续错误次数过多，请等待 ${_retryCount * 2} 秒',
                  style: TextStyle(
                    fontSize: 12,
                    color:
                        isDark ? AppDesign.bodyMuted : AppDesign.inkMuted48,
                  ),
                ),
              ),

            const Spacer(flex: 3),

            // ── 底部提示 ──
            if (!_isConfigured)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppDesign.appleOrange.withValues(alpha: 0.1),
                    borderRadius:
                        BorderRadius.circular(AppDesign.roundedMd),
                  ),
                  child: const Text(
                    'PM码尚未设置。请在 设置 → 加密与安全 → PM码 中配置。',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppDesign.appleOrange,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

/// Shake 动画曲线。
class _ShakeCurve extends Curve {
  @override
  double transformInternal(double t) {
    if (t < 0.1) return 0;
    if (t < 0.3) return -1.0;
    if (t < 0.5) return 1.0;
    if (t < 0.7) return -0.5;
    if (t < 0.85) return 0.5;
    return 0;
  }
}
