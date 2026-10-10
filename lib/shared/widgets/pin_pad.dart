// iOS 风格九宫格数字密码盘核心（弹出层/启动锁屏共用）。
//
// 原 `lib/fix/security_and_sync_fix.dart` PART 2（M1 目录迁移，行为零变化）。
//
// D-15 豁免（DESIGN_SYSTEM §3.6）：本文件属**沉浸层**（深色遮罩上的锁屏），
// 全文件 `Colors.white*` 为功能性对比度设计，豁免于白系收编整改，保持原样。

import 'dart:ui' as ui show ImageFilter;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:drawing_notes_app/core/theme/apple_design.dart';
import 'package:drawing_notes_app/core/theme/apple_motion.dart';
import 'package:drawing_notes_app/core/theme/apple_focus.dart';
import 'package:drawing_notes_app/l10n/app_localizations.dart';

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
/// 文本切换模式（C-14 兑现，[enableTextInput] 为 true）：底部动作区出现
/// 「字母/数字」切换键——切到文本模式后圆点与九宫格替换为 obscure
/// TextField（任意字符、无长度上限），提交走与数字模式相同的校验管线。
/// 用途：文件密码域（[UnlockFlow] 的 flexible 场景）——密码可含字母，
/// 纯数字九宫格打不出字母密码。文本模式对**解锁**不做 min/max 长度约束
/// （既有超长/短密码不能被 UI 挡在门外，业务校验由 [onVerify] 与收集方的
/// 确认步骤承担）；收集模式（[onVerify] 为空）与数字模式同口径校验
/// [flexibleMinLength]，两端设出来的密码强度一致。
///
/// **凭据单一真源 = [_entered] 缓冲**（P1 修复，2026-10-03）：九宫格 tap
/// 与文本框 onChanged 都写它，提交一律取它，切换模式时把当前值同步进
/// [_textController]——旧实现在切文本时只 setState，已输入的 1234 被静默
/// 丢弃（`1234abcd` 变成 `abcd`：设成非预期密码/永远解不开）。
/// 模式切换不播动画（解锁/设密高频，频率闸门）。
///
/// 开屏 PIN（纯数字场景）不传 [enableTextInput]，行为零变化。
///
/// 底部「紧急情况 / 取消」按钮按传入回调按需显示，均未传时整行隐藏
/// （全屏启动锁不允许退出，两个回调皆不传即可）。
class PinPadCore extends StatefulWidget {
  const PinPadCore({
    super.key,

    /// i18n（E1 批 1）：null 时按 locale 取「输入密码」（默认参数无法
    /// 引用 l10n，运行时在使用处解析）。
    this.title,
    this.pinLength = 4,
    this.flexible = false,
    this.flexibleMinLength = 4,
    this.flexibleMaxLength = 12,
    this.onVerify,
    this.onAccepted,
    this.onEmergency,
    this.emergencyLabel,
    this.onCancel,
    this.enableTextInput = false,
    this.keyboardInput,
  });

  final String? title;

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
  /// null 时按 locale 取默认（i18n E1 批 1）。
  final String? emergencyLabel;

  /// 「取消」按钮回调；不传则不显示该按钮。
  final VoidCallback? onCancel;

  /// 文本切换模式开关（C-14 兑现）：true 时底部动作区出现「字母/数字」
  /// 切换键，文本模式提交与数字模式共用校验管线。仅文件密码域
  /// （flexible 场景）开启；开屏 PIN 保持纯数字。
  final bool enableTextInput;

  /// 桌面物理键盘输入槽（P2 可达性修复，2026-10-03）：非空时渲染在
  /// 标题/圆点区之下、九宫格之上——Windows 等桌面宿主上用户可直接用
  /// 物理键盘敲密码，**九宫格仍在**（鼠标/触屏通道不删，三输入并行）。
  /// 提交语义由调用方掌握（AppLockGate 走同一 verify 管线，防爆破计数
  /// 与冷却不因新增通道被绕过）；移动端不传（九宫格即主通道）。
  final Widget? keyboardInput;

  @override
  State<PinPadCore> createState() => _PinPadCoreState();
}

class _PinPadCoreState extends State<PinPadCore>
    with SingleTickerProviderStateMixin {
  final StringBuffer _entered = StringBuffer();
  late final AnimationController _shake = AnimationController(
    vsync: this,
    // 抖动 = 模态档时长（250ms；原 400ms 超出令牌表）。
    duration: AppleMotion.modal,
  );

  // ---- 文本切换模式（C-14 兑现）----
  // 凭据单一真源 = _entered（P1 修复）：九宫格与文本框都写它，切换时把
  // 当前值同步进 _textController——旧实现切换即丢弃已输入内容。
  // 文本控制器隐藏不销毁，往返切换输入内容不丢。模式切换不做过渡动画
  // （解锁/设密属高频操作，频率闸门）。
  bool _textMode = false;
  final TextEditingController _textController = TextEditingController();
  final FocusNode _textFocus = FocusNode();

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

  /// 当前凭据（单一真源）。
  String get _credential => _entered.toString();

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
      unawaited(HapticFeedback.heavyImpact());
      await _shake.forward(from: 0);
      return;
    }
    await _submit();
  }

  Future<void> _submit() async {
    final pin = _credential;
    if (widget.onVerify == null) {
      widget.onAccepted?.call(pin);
      return;
    }
    final ok = await widget.onVerify!(pin);
    if (!mounted) return;
    if (ok) {
      widget.onAccepted?.call(pin);
    } else {
      unawaited(HapticFeedback.heavyImpact());
      await _shake.forward(from: 0);
      // 失败清空两个视图（文本模式下控制器与缓冲都得归零）。
      if (mounted) {
        setState(() {
          _entered.clear();
          _textController.clear();
        });
      }
    }
  }

  /// 文本模式：切到字母键盘——把当前凭据搬进文本框（P1 修复：旧实现
  /// 只 setState，九宫格已输入的 1234 被静默丢弃）。切换不播动画。
  void _toggleTextMode() {
    HapticFeedback.lightImpact();
    final current = _credential;
    setState(() {
      _textMode = true;
      _textController.value = TextEditingValue(
        text: current,
        selection: TextSelection.collapsed(offset: current.length),
      );
    });
  }

  /// 数字模式：切回九宫格（缓冲即真源，内容不丢不串）。
  void _toggleDigitMode() {
    HapticFeedback.lightImpact();
    setState(() {
      _entered
        ..clear()
        ..write(_textController.text);
      _textMode = false;
    });
  }

  /// 文本模式提交：与数字模式同一管线、同一真源（_entered，onChanged
  /// 已把文本框内容写入）。空提交轻抖忽略（文本模式对解锁不做长度约束，
  /// 见 [PinPadCore.enableTextInput]）；收集模式（设密）按
  /// [PinPadCore.flexibleMinLength] 抖动拒绝——与九宫格 ✓ 同口径。
  Future<void> _submitText() async {
    final value = _credential;
    if (value.isEmpty) {
      unawaited(HapticFeedback.lightImpact());
      await _shake.forward(from: 0);
      return;
    }
    if (widget.onVerify == null &&
        _isFlexible &&
        value.length < widget.flexibleMinLength) {
      unawaited(HapticFeedback.heavyImpact());
      await _shake.forward(from: 0);
      return;
    }
    await _submit();
  }

  @override
  void dispose() {
    _shake.dispose();
    _textController.dispose();
    _textFocus.dispose();
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
              // 文本模式（C-14）：标题+ obscure 输入框+提交钮，键盘弹出经
              // viewInsets 避让、SingleChildScrollView 防小屏溢出。
              child: _textMode
                  ? _buildTextModeBody()
                  : _buildDigitModeBody(),
            ),
          ),
        ),
      ),
    );
  }

  /// 数字模式主体（九宫格）。
  ///
  /// P1 可达性修复（2026-10-03）：原实现是 `Column + Spacer`，矮视口
  /// （Android 横屏、Windows 压扁窗口）下 Spacer 分不到空间，`0`/退格/✓
  /// 直接被裁到屏外——既提交不了也退不了格。改为
  /// `LayoutBuilder + SingleChildScrollView + ConstrainedBox(minHeight:)`：
  /// 视口够用 ⇒ 留白按原 3:2:2 比例分配（视觉不变，触控目标仍 ≥44）；
  /// 视口不足 ⇒ 留白归零、整盘纵向可滚动，任何键都能滚进命中区。
  Widget _buildDigitModeBody() {
    final l10n = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final free = constraints.maxHeight - _digitContentEstimate;
        final gap = free <= 0 ? 0.0 : free / 7;
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              // 估算高度与实际内容的差额交居中吸收（比例留白仍按 3:2:2）。
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(height: gap * 3),
                Text(
                  widget.title ??
                      l10n?.unlockEnterPassword ??
                      '输入密码',
                  style: AppleType.titleStyle(Colors.white),
                ),
                const SizedBox(height: 24),
                AnimatedBuilder(
                  animation: _shake,
                  builder: (context, child) {
                    // 减弱动效三信号：抖动属位移类（前庭刺激），按规范
                    // 「更少更轻不是零」改为不位移——错误反馈仍由清空+
                    // 触感/颜色承担，只去掉横向晃动本身。
                    final shake = _shake.isAnimating &&
                        !AppleMotion.reduceMotionOf(context);
                    final dx = shake
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
                            const SizedBox(height: 8),
                            Text(
                              AppLocalizations.of(context)?.pinDigitsCount(
                                    _entered.length,
                                    widget.flexibleMinLength,
                                    widget.flexibleMaxLength,
                                  ) ??
                                  '${_entered.length} / ${widget.flexibleMaxLength} 位'
                                      '（${widget.flexibleMinLength}–'
                                      '${widget.flexibleMaxLength} 位可选）',
                              style: AppleType.captionStyle(
                                Colors.white.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                // 桌面物理键盘输入槽（P2 可达性）：九宫格保留，键鼠直输
                // 与点按并行——三输入同时可用。
                if (widget.keyboardInput != null) ...[
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: widget.keyboardInput!,
                  ),
                ],
                SizedBox(height: gap * 2),
                _buildKeypad(),
                SizedBox(height: gap * 2),
                _buildBottomActions(),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 数字模式内容自然高度估算（用于把「视口剩余留白」按原 Spacer 3:2:2
  /// 比例分下去）：标题 25 + 间距 24 + 圆点区 37 + 九宫格 351，按需再加
  /// 可变长度计数行 25、底部动作区 65、桌面键盘槽 64。
  ///
  /// 为什么按开关逐项累加：留白 = 视口高 − 本估算，估少了键会被顶到折叠线
  /// 之下（要滚才够得着），估多了只是留白偏小。差额由
  /// [MainAxisAlignment.center] 吸收，估高偏大不会裁键。
  double get _digitContentEstimate {
    var estimate = 437.0; // 标题 25 + 间距 24 + 圆点区 37 + 九宫格 351
    if (_isFlexible) estimate += 25;
    if (widget.enableTextInput ||
        widget.onEmergency != null ||
        widget.onCancel != null) {
      estimate += 65;
    }
    if (widget.keyboardInput != null) estimate += 64;
    return estimate;
  }

  /// 文本模式主体（C-14 兑现）：标题 + obscure TextField + 提交钮。
  /// 无 Spacer（键盘弹出时经 viewInsets 避让）；SingleChildScrollView
  /// 防小屏溢出；错误抖动复用同一 _shake 控制器。
  Widget _buildTextModeBody() {
    final l10n = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: AnimatedBuilder(
        animation: _shake,
        builder: (context, child) {
          // 与数字模式同一减弱动效门控（reduceMotionOf）。
          final shake = _shake.isAnimating &&
              !AppleMotion.reduceMotionOf(context);
          final dx = shake
              ? 12 * (1 - _shake.value * 2) * (_shake.value < 0.5 ? 1 : -1)
              : 0.0;
          return Transform.translate(offset: Offset(dx, 0), child: child);
        },
        child: Column(
          children: [
            const SizedBox(height: 48),
            Text(
              widget.title ??
                  l10n?.unlockEnterPassword ??
                  '输入密码',
              style: AppleType.titleStyle(Colors.white),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: TextField(
                controller: _textController,
                focusNode: _textFocus,
                obscureText: true,
                autofocus: true,
                onSubmitted: (_) => _submitText(),
                // 文本框内容即凭据真源：每次改动回写 _entered（P1 修复，
                // 与九宫格同一缓冲，跨模式不丢不串）。
                onChanged: (value) => setState(() {
                  _entered
                    ..clear()
                    ..write(value);
                }),
                style: AppleType.bodyStyle(Colors.white),
                cursorColor: Colors.white,
                decoration: InputDecoration(
                  hintText: l10n?.commonPassword ?? '密码',
                  helperText: l10n?.unlockTextInputHint ?? '可包含字母与符号',
                  helperStyle: AppleType.captionStyle(
                    Colors.white.withValues(alpha: 0.7),
                  ),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.14),
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(AppleRadius.md)),
                  ),
                  enabledBorder: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(AppleRadius.md)),
                    borderSide: BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(AppleRadius.md)),
                    borderSide: BorderSide(color: Colors.white54),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 验证模式 =「解锁」；收集模式（设密等）=「确定」——
            // 与桌面端 DesktopUnlockField 同一文案对。
            FilledButton(
              onPressed: _submitText,
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                minimumSize: const Size(140, 44),
              ),
              child: Text(
                widget.onVerify == null
                    ? l10n?.commonConfirm ?? '确定'
                    : l10n?.unlock ?? '解锁',
                style: AppleType.bodyStyle(Colors.white),
              ),
            ),
            const SizedBox(height: 8),
            _buildBottomActions(),
          ],
        ),
      ),
    );
  }

  /// 底部操作区：「紧急情况 / 取消」按传入回调按需显示，
  /// 均未传时整行隐藏（全屏启动锁不允许退出）。
  /// 文本切换模式（C-14）在最左侧加「字母/数字」切换键——行随其一可见。
  Widget _buildBottomActions() {
    final emergency = widget.onEmergency;
    final cancel = widget.onCancel;
    final showToggle = widget.enableTextInput;
    if (emergency == null && cancel == null && !showToggle) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      child: Row(
        children: [
          if (showToggle)
            _bottomAction(
              _textMode
                  ? l10n?.unlockKeyboardDigits ?? '数字'
                  : l10n?.unlockKeyboardText ?? '字母',
              _textMode ? _toggleDigitMode : _toggleTextMode,
            ),
          if (showToggle && emergency != null) const SizedBox(width: 4),
          if (emergency != null)
            _bottomAction(
              widget.emergencyLabel ?? l10n?.unlockEmergency ?? '紧急情况',
              emergency,
            ),
          const Spacer(),
          if (cancel != null)
            _bottomAction(l10n?.cancel ?? '取消', cancel),
        ],
      ),
    );
  }

  Widget _bottomAction(String label, VoidCallback onPressed) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        textStyle: AppleType.bodyStyle(Colors.white),
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
                label: AppLocalizations.of(context)?.pinBackspace ?? '退格',
              ),
              // 右下空槽：可变长度模式 = ✓ 确认键（accent 底色区分）。
              '' when i == 11 && _isFlexible => _buildAuxKey(
                icon: Icons.check_rounded,
                onTap: _submitFlexible,
                accent: true,
                label: AppLocalizations.of(context)?.pinConfirm ?? '确认',
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
    required String label,
    bool accent = false,
  }) {
    return Semantics(
      button: true,
      label: label,
      child: AppleFocusRing(borderRadius: AppleRadius.pill, child: Material(
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
      )),
    );
  }

  /// 单个按键：半透明白色磨砂圆 + 居中大数字 + 底部小号字母标注。
  Widget _buildKey(String digit) {
    final letters = _keyLetters[digit];
    return AppleFocusRing(borderRadius: AppleRadius.pill, child: Material(
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
              // 密码盘数字键：大号触控读数，梯子无 33 档；以 headline 为基。
              style: AppleType.headlineStyle(Colors.white).copyWith(
                fontSize: 33,
                fontWeight: FontWeight.w400,
                letterSpacing: 0,
              ),
            ),
            Positioned(
              bottom: 10,
              child: Text(
                letters ?? '',
                style:
                    AppleType.captionStyle(
                      Colors.white.withValues(alpha: 0.92),
                    ).copyWith(
                      fontWeight: FontWeight.w600,
                      letterSpacing: 2.5,
                      // D-08（审计 2026-09-27）：移除 height:1 覆写——
                      // 行高 1 低于全库 1.47 硬底线，承接 captionStyle
                      // 自带行高（三字母提示宽度增量可忽略）。
                    ),
              ),
            ),
          ],
        ),
      ),
    ));
  }
}
