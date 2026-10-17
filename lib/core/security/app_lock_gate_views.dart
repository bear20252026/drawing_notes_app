part of 'app_lock_gate.dart';

// 锁屏 UI 段（从 app_lock_gate.dart 搬出，2026-10-16 R26 纯搬运，语义零改动）：
// 桌面物理键盘密码槽 / 冷却倒计时面板 / 倒计时文本。判据与状态机仍留在门组件里，
// 本文件只承载渲染。part 文件不能带 import，新符号必须在库本体引入。


/// 桌面物理键盘密码槽（P2 可达性修复，2026-10-03）。
///
/// 嵌在 [PinPadCore] 标题/圆点区之下、九宫格之上，只补「物理键盘直接敲
/// 密码」这一条通道——九宫格仍在原位，鼠标点按与触屏点按零改动（三输入
/// 并行，不删任何入口）。语义严格对齐九宫格：
/// - 纯数字（digitsOnly）+ 长度上限 = 当前开屏 PIN 长度（4–12），输满自动
///   提交（与九宫格「输满即校验」同拍）；
/// - 提交一律经 [onSubmit] → `AppLockService.verify`：防爆破失败计数与
///   指数冷却照常生效，键盘路径**不构成旁路**；
/// - 校验失败原地清空 + 显示错误，锁屏不关闭（错误凭据不可能被上层当成
///   已验证）；
/// - 空串/长度不足就地提示，不发校验（不白耗一次失败计数）。
///
/// 「失去焦点立即锁定」的会话守卫（[SessionGuard] 走 AppLifecycleListener
/// onInactive，即窗口/应用级失焦）与本组件的焦点无关：TextField 内部焦点
/// 不会触发 onInactive，故新增输入框不改变该交互。
class _DesktopPinField extends StatefulWidget {
  const _DesktopPinField({required this.pinLength, required this.onSubmit});

  final int pinLength;
  final Future<bool> Function(String pin) onSubmit;

  @override
  State<_DesktopPinField> createState() => _DesktopPinFieldState();
}

class _DesktopPinFieldState extends State<_DesktopPinField> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  String? _errorText;

  /// 在途校验标记：输满自动提交与「解锁」按钮可能同帧撞车，重复提交会
  /// 让同一凭据走两次 verify（= 白耗一次失败计数）。
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    // 锁屏出现即聚焦（与桌面解锁对话框同纪律）。post-frame 回调可能在
    // 同帧拆树之后才跑（如解锁瞬间撤锁屏），届时 _focus 已 dispose。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final pin = _controller.text;
    final l10n = AppLocalizations.of(context);
    if (pin.isEmpty) {
      setState(() => _errorText = l10n?.passwordEmptyHint ?? '密码不能为空');
      return;
    }
    if (pin.length != widget.pinLength) {
      setState(
        () => _errorText =
            l10n?.pinDigitsCount(
              pin.length,
              widget.pinLength,
              widget.pinLength,
            ) ??
            '密码长度不足',
      );
      return;
    }
    _submitting = true;
    final ok = await widget.onSubmit(pin);
    if (!mounted) return;
    _submitting = false;
    _controller.clear();
    if (ok) return; // 门组件随即撤掉锁屏
    setState(() => _errorText = l10n?.unlockPasswordWrong ?? '密码不正确');
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            focusNode: _focus,
            obscureText: true,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(widget.pinLength),
            ],
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            // 输满即校验（与九宫格同一拍），中途不校验（否则每次都记失败）。
            onChanged: (value) {
              setState(() => _errorText = null);
              if (value.length == widget.pinLength) _submit();
            },
            style: AppleType.bodyStyle(Colors.white),
            decoration: InputDecoration(
              hintText: AppLocalizations.of(context)?.commonPassword ?? '密码',
              errorText: _errorText,
              errorStyle: AppleType.captionStyle(const Color(0xFFFF6B6B)),
              counterText: AppLocalizations.of(context)?.pinDigitsCount(
                _controller.text.length,
                widget.pinLength,
                widget.pinLength,
              ),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.14),
              border: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(AppleRadius.xs)),
              ),
              enabledBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(AppleRadius.xs)),
                borderSide: BorderSide(color: Colors.white24),
              ),
              focusedBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(AppleRadius.xs)),
                borderSide: BorderSide(color: Colors.white54),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppleSpacing.xs),
        // 鼠标/触屏等价入口（三输入硬性要求）：≥44 高。
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.primary,
            minimumSize: const Size(88, 44),
          ),
          child: Text(
            AppLocalizations.of(context)?.unlock ?? '解锁',
            style: AppleType.bodyStyle(Colors.white),
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
                const SizedBox(height: AppleSpacing.md),
                // 19 无档位：titleStyle 基底 + copyWith 保留原字号。
                Text(
                  AppLocalizations.of(context)?.lockTooManyAttempts ?? '尝试次数过多',
                  style: AppleType.titleStyle(Colors.white)
                      .copyWith(fontSize: 19),
                ),
                const SizedBox(height: AppleSpacing.xs),
                _RemainingText(service: widget.service, tick: _tick),
                const SizedBox(height: AppleSpacing.xxs),
                Text(
                  AppLocalizations.of(context)?.lockTemporarilyLocked ??
                      '为防止暴力猜测，密码验证已暂时锁定',
                  style: AppleType.captionStyle(
                    Colors.white.withValues(alpha: 0.55),
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

  String _format(BuildContext context, Duration remaining) {
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds % 60;
    if (minutes >= 60) {
      final hours = remaining.inHours;
      final mins = minutes % 60;
      return AppLocalizations.of(context)?.lockDurHoursMins(hours, mins) ??
          '$hours 小时 $mins 分';
    }
    return AppLocalizations.of(context)?.lockDurMinsSecs(minutes, seconds) ??
        '$minutes 分 $seconds 秒';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: tick,
      builder: (context, _, _) {
        return Text(
          AppLocalizations.of(
                context,
              )?.lockRetryAfter(_format(context, service.lockoutRemaining)) ??
              '请在 ${_format(context, service.lockoutRemaining)} 后重试',
          style: AppleType.bodyStyle(Colors.white.withValues(alpha: 0.82)),
        );
      },
    );
  }
}
