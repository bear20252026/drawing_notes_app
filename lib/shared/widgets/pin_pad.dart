// iOS 风格九宫格数字密码盘核心（弹出层/启动锁屏共用）。
//
// 原 `lib/fix/security_and_sync_fix.dart` PART 2（M1 目录迁移，行为零变化）。

import 'dart:ui' as ui show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// PART 2 · PinPadUnlockSheet —— iOS 锁屏风格全屏数字密码盘
// ===========================================================================

/// iOS 锁屏密码界面 1:1 复刻（参照 iOS 7+ 锁屏「输入密码」屏）。
///
/// 视觉规格（对照截图）：
/// - 全屏：底层内容高斯模糊（BackdropFilter sigma 30）+ 深色渐变压暗；
/// - 顶部标题（白字）+ 四个空心圆点（输入后填充为实心白点）；
/// - 3×4 圆形键盘：半透明白色磨砂按键，大数字居中、
///   下方小号字母标注（2=ABC … 9=WXYZ，1/0 无字母）；
/// - 底部左右角：「紧急情况」「取消」白字按钮；
/// - 交互：触感震动、输满自动校验、输错整体抖动并清空。
///
/// 注意：与真实 iOS 一致，不设删除键——输错由抖动清空兜底。
/// 密码盘核心组件（公开）——弹出式密码盘与全屏启动锁屏共用的
/// 单一事实来源：毛玻璃背景 + 标题 + 进度圆点 + 3×4 圆形键盘。
///
/// 自带 Material 透明层，可嵌入任意上下文（对话框 / Stack 覆盖层）。
///
/// 固定长度模式（默认）：输满 [pinLength] 位后——
/// - [onVerify] 为空：立即回调 [onAccepted]（收集模式，如设置新密码）；
/// - [onVerify] 非空：异步校验，通过回调 [onAccepted]，失败整体抖动并清空。
///
/// 可变长度模式（批次②，[flexible] 为 true）：4–12 位任意长度，退格键 +
/// ✓ 确认键（补位原空键位）；输满 [flexibleMaxLength] 位或按 ✓ 提交，
/// 不足 [flexibleMinLength] 位按 ✓ 抖动提示。
///
/// 底部「紧急情况 / 取消」按钮按传入回调按需显示，均未传时整行隐藏
/// （全屏启动锁不允许退出，两个回调皆不传即可）。
class PinPadCore extends StatefulWidget {
  const PinPadCore({
    super.key,
    this.title = '输入密码',
    this.pinLength = 4,
    this.flexible = false,
    this.flexibleMinLength = 4,
    this.flexibleMaxLength = 12,
    this.onVerify,
    this.onAccepted,
    this.onEmergency,
    this.emergencyLabel = '紧急情况',
    this.onCancel,
  });

  final String title;

  /// 固定长度模式的圆点数。
  final int pinLength;

  /// 可变长度模式（批次②：4–12 位自定义密码，单文件密码输入用）。
  final bool flexible;
  final int flexibleMinLength;
  final int flexibleMaxLength;

  /// 输满后的异步校验回调；为空则输满直接回调 [onAccepted]。
  final Future<bool> Function(String pin)? onVerify;

  /// 校验通过（或无校验输满）时的接收回调。
  final ValueChanged<String>? onAccepted;

  /// 「紧急情况」按钮回调；不传则不显示该按钮。
  final VoidCallback? onEmergency;

  /// 「紧急情况」按钮文案（N4 批 2：文件密码解锁时复用为「忘记密码？」）。
  final String emergencyLabel;

  /// 「取消」按钮回调；不传则不显示该按钮。
  final VoidCallback? onCancel;

  @override
  State<PinPadCore> createState() => _PinPadCoreState();
}

class _PinPadCoreState extends State<PinPadCore>
    with SingleTickerProviderStateMixin {
  final StringBuffer _entered = StringBuffer();
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );

  /// 数字键对应的字母标注（iOS 电话键盘布局）。
  static const _keyLetters = <String, String>{
    '2': 'ABC',
    '3': 'DEF',
    '4': 'GHI',
    '5': 'JKL',
    '6': 'MNO',
    '7': 'PQRS',
    '8': 'TUV',
    '9': 'WXYZ',
  };

  bool get _isFlexible => widget.flexible;

  int get _maxLength =>
      _isFlexible ? widget.flexibleMaxLength : widget.pinLength;

  /// 圆点数：固定模式 = pinLength；可变模式 =
  /// 「至少最短长度、随输入逐位增长、封顶最大长度」。
  int get _dotCount => _isFlexible
      ? (_entered.length + 1).clamp(
          widget.flexibleMinLength,
          widget.flexibleMaxLength,
        )
      : widget.pinLength;

  void _tap(String digit) {
    if (_entered.length >= _maxLength) return;
    HapticFeedback.lightImpact();
    setState(() => _entered.write(digit));
    // 固定长度：输满自动提交；可变长度：等 ✓ 确认。
    if (!_isFlexible && _entered.length == widget.pinLength) _submit();
  }

  /// 可变长度模式：退格。
  void _backspace() {
    if (_entered.isEmpty) return;
    HapticFeedback.lightImpact();
    setState(() {
      final text = _entered.toString();
      _entered
        ..clear()
        ..write(text.substring(0, text.length - 1));
    });
  }

  /// 可变长度模式：✓ 确认提交（不足最短长度抖动提示）。
  Future<void> _submitFlexible() async {
    if (_entered.length < widget.flexibleMinLength) {
      HapticFeedback.heavyImpact();
      await _shake.forward(from: 0);
      return;
    }
    await _submit();
  }

  Future<void> _submit() async {
    final pin = _entered.toString();
    if (widget.onVerify == null) {
      widget.onAccepted?.call(pin);
      return;
    }
    final ok = await widget.onVerify!(pin);
    if (!mounted) return;
    if (ok) {
      widget.onAccepted?.call(pin);
    } else {
      HapticFeedback.heavyImpact();
      await _shake.forward(from: 0);
      if (mounted) setState(_entered.clear);
    }
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 自带 Material 透明层：既可在对话框中使用，也可嵌入 Stack 覆盖层
    // （InkWell/TextButton 需要 Material 祖先）。
    return Material(
      type: MaterialType.transparency,
      child: ClipRect(
        child: BackdropFilter(
          // U3 P1-11：sigma 30→18——视觉差异极小，GPU 模糊开销显著降低。
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            color: Colors.black.withValues(alpha: 0.38),
            child: SafeArea(
              child: Column(
                children: [
                  const Spacer(flex: 3),
                  Text(
                    widget.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 20),
                  AnimatedBuilder(
                    animation: _shake,
                    builder: (context, child) {
                      final dx = _shake.isAnimating
                          ? 12 *
                                (1 - _shake.value * 2) *
                                (_shake.value < 0.5 ? 1 : -1)
                          : 0.0;
                      return Transform.translate(
                        offset: Offset(dx, 0),
                        child: child,
                      );
                    },
                    // FittedBox：可变长度最多 12 个圆点，窄屏自动缩放防溢出。
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(_dotCount, (i) {
                                final filled = i < _entered.length;
                                return Container(
                                  width: 11,
                                  height: 11,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 13,
                                  ),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: filled
                                        ? Colors.white
                                        : Colors.transparent,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: filled ? 5.5 : 1.5,
                                    ),
                                  ),
                                );
                              }),
                            ),
                            if (_isFlexible) ...[
                              const SizedBox(height: 10),
                              Text(
                                '${_entered.length} / ${widget.flexibleMaxLength} 位'
                                '（${widget.flexibleMinLength}–'
                                '${widget.flexibleMaxLength} 位可选）',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  const Spacer(flex: 2),
                  _buildKeypad(),
                  const Spacer(flex: 2),
                  _buildBottomActions(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 底部操作区：「紧急情况 / 取消」按传入回调按需显示，
  /// 均未传时整行隐藏（全屏启动锁不允许退出）。
  Widget _buildBottomActions() {
    final emergency = widget.onEmergency;
    final cancel = widget.onCancel;
    if (emergency == null && cancel == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (emergency != null)
            _bottomAction(widget.emergencyLabel, emergency),
          if (cancel != null) _bottomAction('取消', cancel),
        ],
      ),
    );
  }

  Widget _bottomAction(String label, VoidCallback onPressed) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        textStyle: const TextStyle(fontSize: 17),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      ),
      child: Text(label),
    );
  }

  Widget _buildKeypad() {
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', ''];
    return SizedBox(
      width: 264,
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 1,
        children: [
          for (var i = 0; i < keys.length; i++)
            switch (keys[i]) {
              // 左下空槽：可变长度模式 = 退格键。
              '' when i == 9 && _isFlexible => _buildAuxKey(
                icon: Icons.backspace_outlined,
                onTap: _backspace,
              ),
              // 右下空槽：可变长度模式 = ✓ 确认键（accent 底色区分）。
              '' when i == 11 && _isFlexible => _buildAuxKey(
                icon: Icons.check_rounded,
                onTap: _submitFlexible,
                accent: true,
              ),
              '' => const SizedBox.shrink(),
              final k => _buildKey(k),
            },
        ],
      ),
    );
  }

  /// 可变长度模式的辅助键（退格 / ✓ 确认）。
  /// [accent] 为 true 时用强调底色突出确认键。
  Widget _buildAuxKey({
    required IconData icon,
    required VoidCallback onTap,
    bool accent = false,
  }) {
    return Material(
      color: accent
          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.85)
          : Colors.white.withValues(alpha: 0.14),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.white.withValues(alpha: 0.30),
        highlightColor: Colors.white.withValues(alpha: 0.16),
        child: Icon(icon, color: Colors.white, size: 26),
      ),
    );
  }

  /// 单个按键：半透明白色磨砂圆 + 居中大数字 + 底部小号字母标注。
  Widget _buildKey(String digit) {
    final letters = _keyLetters[digit];
    return Material(
      color: Colors.white.withValues(alpha: 0.22),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _tap(digit),
        splashColor: Colors.white.withValues(alpha: 0.30),
        highlightColor: Colors.white.withValues(alpha: 0.16),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(
              digit,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 33,
                fontWeight: FontWeight.w400,
              ),
            ),
            Positioned(
              bottom: 10,
              child: Text(
                letters ?? '',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.92),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2.5,
                  height: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
