// ============================================================================
// security_and_sync_fix.dart —— 独立修复补丁文件（2026-09-01）
// ============================================================================
//
// 本文件为独立补丁，不修改任何原有源码文件。包含四部分：
//   PART 1. SyncFix —— 同步刷新修复（首页不更新问题）
//   PART 2. PinPadCore —— iOS 风格九宫格数字密码盘核心（弹出层/启动锁屏共用）
//   PART 2b. PinPadUnlockSheet —— 弹出式密码盘（对话框形态复用 PinPadCore）
//   PART 3. DesktopUnlockField —— 桌面端键盘密码输入
//   PART 4. HomeLockButton —— 首页置顶解锁按钮（像苹果手机解锁一样一键直达）
//
// ----------------------------------------------------------------------------
// 【集成指南】（只需在原有文件中加入几行调用，不改原有逻辑）
//
// ① 修复同步（app_shell.dart 或调用点）：
//    - 笔记本内新建/删除/保存成功后，调用：
//        SyncFix.notifyDataChanged(_services.bumpDataVersion);
//      即等价于 _services.bumpDataVersion();
//    - 给 HomePage 增加可见性兜底刷新：将 HomePage 包进
//        SyncFixRouteObserver.dependOnRouteAware(state, SyncFix.routeObserver)
//      并在 main.dart 的 MaterialApp navigatorObservers 中加入
//        SyncFix.routeObserver
//
// ② 首页解锁按钮（home_page.dart 的 AppBar actions 中加入）：
//        HomeLockButton(
//          onUnlockRequested: () async {
//            final pin = await PinPadUnlockSheet.show(context);
//            if (pin != null) { /* 用 pin 解锁加密笔记本 */ }
//          },
//        )
//
// ③ 九宫格密码盘直接可用：
//        final pin = await PinPadUnlockSheet.show(context); // 手机端
//        final pin = await DesktopUnlockField.show(context); // 电脑端
//    平台自适应入口（推荐）：
//        final pin = await UnlockFlow.show(context);
// ============================================================================
library;

import 'dart:io' show Platform;
import 'dart:ui' as ui show ImageFilter;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ===========================================================================
// PART 1 · SyncFix —— 同步刷新修复
// ===========================================================================

/// 同步修复工具集。
///
/// 根因：首页只监听 `AppServices.dataVersion`（ValueNotifier），
/// 而笔记本页内部的新建/保存路径没有调用 `bumpDataVersion`，
/// 且首页在 IndexedStack 中保活，切回时也不刷新。
abstract final class SyncFix {
  /// 全局路由观察者。注册到 MaterialApp.navigatorObservers 后，
  /// 首页可通过 [SyncFixRouteAware] 在重新可见时自动刷新。
  static final RouteObserver<ModalRoute<void>> routeObserver =
      RouteObserver<ModalRoute<void>>();

  /// 数据变更统一通知入口。
  ///
  /// 所有"新建 / 修改 / 删除"落盘成功后调用一次；传入项目现有的
  /// `services.bumpDataVersion`（-tear-off）即可，不引入新状态源。
  static void notifyDataChanged(VoidCallback? bumpDataVersion) {
    bumpDataVersion?.call();
  }
}

/// 首页（或任意保活页面）混入后，页面重新可见时自动回调 [onPageVisibleAgain]。
///
/// 用法（在 HomePage State 中）：
///   `class _HomePageState extends State<HomePage> with SyncFixRouteAware` {
///     @override
///     void onPageVisibleAgain() => _refresh();
///     @override
///     void didChangeDependencies() {
///       super.didChangeDependencies();
///       SyncFix.routeObserver.subscribe(
///           this, ModalRoute.of(context)! as PageRoute);
///     }
///     @override
///     void dispose() {
///       SyncFix.routeObserver.unsubscribe(this);
///       super.dispose();
///     }
///   }
mixin SyncFixRouteAware<T extends StatefulWidget> on State<T>
    implements RouteAware {
  void onPageVisibleAgain();

  @override
  void didPopNext() => onPageVisibleAgain();

  @override
  void didPush() {}

  @override
  void didPop() {}

  @override
  void didPushNext() {}
}

// ===========================================================================
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
          filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
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
                      fontWeight: FontWeight.w500,
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
          if (emergency != null) _bottomAction(widget.emergencyLabel, emergency),
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

/// iOS 锁屏密码盘弹出入口：以全屏对话框形态打开 [PinPadCore]，
/// 返回用户输入的 PIN（取消返回 null）。视觉与交互完全一致。
class PinPadUnlockSheet extends StatelessWidget {
  const PinPadUnlockSheet({
    super.key,
    this.title = '输入密码',
    this.pinLength = 4,
    this.flexible = false,
    this.flexibleMinLength = 4,
    this.flexibleMaxLength = 12,
    this.onVerify,
    this.onEmergency,
    this.emergencyLabel = '紧急情况',
  });

  final String title;
  final int pinLength;

  /// 可变长度模式（单文件密码 4–12 位）。
  final bool flexible;
  final int flexibleMinLength;
  final int flexibleMaxLength;

  /// 传入校验回调时：输完自动校验，通过关闭并回传 PIN，失败抖动清空；
  /// 不传则输满即回传 PIN。
  final Future<bool> Function(String pin)? onVerify;

  /// 「紧急情况」按钮回调；不传时行为与取消相同（关闭并返回 null）。
  /// N4 批 2：点击时先关闭密码盘再执行回调（忘记密码→重置流需要全屏
  /// 文件选择器，密码盘不先关会叠在选取器上面）。
  final VoidCallback? onEmergency;

  /// 「紧急情况」按钮文案。
  final String emergencyLabel;

  /// 全屏打开密码盘并返回用户输入的 PIN（取消返回 null）。
  static Future<String?> show(
    BuildContext context, {
    String title = '输入密码',
    int pinLength = 4,
    bool flexible = false,
    int flexibleMinLength = 4,
    int flexibleMaxLength = 12,
    Future<bool> Function(String pin)? onVerify,
    VoidCallback? onEmergency,
    String emergencyLabel = '紧急情况',
  }) {
    return showGeneralDialog<String>(
      context: context,
      // 不遮死背景：DialogRoute 非 opaque，下层页面保持可见，
      // 页内 BackdropFilter 才能把真实内容模糊成「锁屏壁纸」效果。
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      barrierLabel: '密码锁',
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, _, _) => PinPadUnlockSheet(
        title: title,
        pinLength: pinLength,
        flexible: flexible,
        flexibleMinLength: flexibleMinLength,
        flexibleMaxLength: flexibleMaxLength,
        onVerify: onVerify,
        onEmergency: onEmergency,
        emergencyLabel: emergencyLabel,
      ),
      transitionBuilder: (_, animation, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PinPadCore(
      title: title,
      pinLength: pinLength,
      flexible: flexible,
      flexibleMinLength: flexibleMinLength,
      flexibleMaxLength: flexibleMaxLength,
      onVerify: onVerify,
      onAccepted: (pin) => Navigator.of(context).pop(pin),
      onEmergency: onEmergency == null
          ? null
          : () {
              // 先关密码盘再执行回调（回调可能叠开文件选择器/新对话框）。
              Navigator.of(context).pop();
              onEmergency!();
            },
      emergencyLabel: emergencyLabel,
      onCancel: () => Navigator.of(context).pop(),
    );
  }
}

// ===========================================================================
// PART 3 · DesktopUnlockField —— 桌面端键盘密码输入
// ===========================================================================

/// 桌面端密码输入对话框：TextField + 回车确认，焦点自动聚焦。
///
/// 传入 [onVerify] 时（验证模式，如关闭/修改应用锁）：确认后先服务端校验，
/// 通过才关闭并回传 PIN；失败在原地显示错误并清空，对话框不关闭——
/// 保证「错误密码不可能被上层当成已验证凭据」。
class DesktopUnlockField extends StatefulWidget {
  const DesktopUnlockField({
    super.key,
    this.title = '输入密码',
    this.maxLength,
    this.onVerify,
    this.footerLabel,
    this.onFooterTap,
  });

  final String title;

  /// 最大长度（可变长度密码 4–12 位时传 12，附实时计数）。
  final int? maxLength;

  /// 验证回调；为空则为收集模式（直接回传输入值）。
  final Future<bool> Function(String pin)? onVerify;

  /// 左下角 footer 链接（N4 批 2：「忘记密码？」）。点击时先关闭本对话框
  /// 再执行回调（回调可能叠开文件选择器/新对话框）。
  final String? footerLabel;
  final VoidCallback? onFooterTap;

  static Future<String?> show(
    BuildContext context, {
    String title = '输入密码',
    int? maxLength,
    Future<bool> Function(String pin)? onVerify,
    String? footerLabel,
    VoidCallback? onFooterTap,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => DesktopUnlockField(
        title: title,
        maxLength: maxLength,
        onVerify: onVerify,
        footerLabel: footerLabel,
        onFooterTap: onFooterTap,
      ),
    );
  }

  @override
  State<DesktopUnlockField> createState() => _DesktopUnlockFieldState();
}

class _DesktopUnlockFieldState extends State<DesktopUnlockField> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _error = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final value = _controller.text;
    if (widget.onVerify != null) {
      final ok = await widget.onVerify!(value);
      if (!mounted) return;
      if (!ok) {
        setState(() => _error = true);
        _controller.clear();
        _focus.requestFocus();
        return;
      }
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final maxLength = widget.maxLength;
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        focusNode: _focus,
        obscureText: true,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          if (maxLength != null) LengthLimitingTextInputFormatter(maxLength),
        ],
        onSubmitted: (_) => _confirm(),
        onChanged: (_) => setState(() => _error = false),
        decoration: InputDecoration(
          hintText: '密码',
          errorText: _error ? '密码不正确' : null,
          counterText: maxLength == null
              ? null
              : '${_controller.text.length} / $maxLength 位（4–$maxLength 位可选）',
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        if (widget.footerLabel != null && widget.onFooterTap != null)
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              widget.onFooterTap!();
            },
            child: Text(widget.footerLabel!),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        // 验证模式 = 「解锁」；收集模式（设密等）= 「确定」。
        FilledButton(
          onPressed: _confirm,
          child: Text(widget.onVerify == null ? '确定' : '解锁'),
        ),
      ],
    );
  }
}

// ===========================================================================
// PART 4 · UnlockFlow / HomeLockButton —— 首页一键解锁入口
// ===========================================================================

/// 平台自适应解锁入口：手机端九宫格，桌面端键盘输入。
abstract final class UnlockFlow {
  static bool get _isMobile =>
      !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  static Future<String?> show(
    BuildContext context, {
    String title = '输入密码',
    int pinLength = 4,
    bool flexible = false,
    int flexibleMinLength = 4,
    int flexibleMaxLength = 12,
    Future<bool> Function(String pin)? onVerify,
    String? footerLabel,
    VoidCallback? onFooter,
  }) {
    if (_isMobile) {
      return PinPadUnlockSheet.show(
        context,
        title: title,
        pinLength: pinLength,
        flexible: flexible,
        flexibleMinLength: flexibleMinLength,
        flexibleMaxLength: flexibleMaxLength,
        onVerify: onVerify,
        // footer = 「紧急情况」槽位复用（N4 批 2：文件密码解锁挂「忘记密码？」）。
        onEmergency: onFooter,
        emergencyLabel: footerLabel ?? '紧急情况',
      );
    }
    return DesktopUnlockField.show(
      context,
      title: title,
      maxLength: flexible ? flexibleMaxLength : pinLength,
      onVerify: onVerify,
      footerLabel: footerLabel,
      onFooterTap: onFooter,
    );
  }
}

/// 首页 AppBar 置顶解锁按钮：未解锁显示 🔒，解锁后显示 🔓。
///
/// 用法（home_page.dart AppBar.actions 中）：
///   HomeLockButton(
///     isUnlocked: _unlocked,
///     onUnlockRequested: () async {
///       final pin = await UnlockFlow.show(context);
///       if (pin != null) setState(() => _unlocked = true);
///     },
///     onLockRequested: () => setState(() => _unlocked = false),
///   )
class HomeLockButton extends StatelessWidget {
  const HomeLockButton({
    super.key,
    required this.isUnlocked,
    required this.onUnlockRequested,
    this.onLockRequested,
  });

  final bool isUnlocked;
  final VoidCallback onUnlockRequested;
  final VoidCallback? onLockRequested;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: isUnlocked ? '锁定' : '解锁',
      icon: Icon(
        isUnlocked ? Icons.lock_open_rounded : Icons.lock_rounded,
        color: isUnlocked
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.outline,
      ),
      onPressed: isUnlocked
          ? (onLockRequested ?? onUnlockRequested)
          : onUnlockRequested,
    );
  }
}

// ===========================================================================
// PART 5（可选）· 生物识别钩子 —— 依赖 local_auth 时再启用
// ===========================================================================
//
// 项目 pubspec.yaml 中加入：  local_auth: ^2.3.0
// 取消下方注释即可像 iPhone 一样触摸/面容解锁：
//
// import 'package:local_auth/local_auth.dart';
//
// abstract final class BiometricUnlock {
//   static final _auth = LocalAuthentication();
//
//   static Future<bool> get isAvailable async {
//     final can = await _auth.canCheckBiometrics;
//     return can || await _auth.isDeviceSupported();
//   }
//
//   static Future<bool> authenticate({String reason = '解锁加密笔记'}) =>
//       _auth.authenticate(
//         localizedReason: reason,
//         options: const AuthenticationOptions(
//           stickyAuth: true,
//           biometricOnly: true,
//         ),
//       );
// }
//
// UnlockFlow.show 中可先尝试：
//   if (await BiometricUnlock.isAvailable && await BiometricUnlock.authenticate()) {
//     return 'biometric-ok';
//   }
// ===========================================================================
