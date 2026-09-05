// 密码盘弹出形态与平台自适应解锁入口。
//
// PinPadUnlockSheet（全屏对话框）+ DesktopUnlockField（桌面键盘）+
// UnlockFlow（平台自适应推荐入口）。原 `lib/fix/` PART 2b/3/4 + PART 5
// 注释（M1 目录迁移，行为零变化；PART 5 生物识别钩子仍为注释备用）。

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:drawing_notes_app/shared/widgets/glass_dialog.dart';
import 'package:drawing_notes_app/shared/widgets/pin_pad.dart';

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
    return GlassDialog.show<String>(
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
