// ============================================================================
// password_reset_common.dart —— 重置密码盘重置流公共步骤（N4 批 3）
// ============================================================================
//
// FilePasswordResetFlow（画作）与 NotebookPasswordResetFlow（分页画布）
// 共用的流程骨架：说明确认 → 插盘读钥匙 → 新密码两遍 → 提示原语。
// 两条流只保留各自的「未绑定检查 + 重置调用」差异部分。

import 'package:flutter/material.dart';

import 'package:drawing_notes_app/core/security/app_lock_service.dart';
import 'package:drawing_notes_app/core/storage/password_reset_disk.dart';
import 'package:drawing_notes_app/shared/widgets/glass_dialog.dart';
import 'package:drawing_notes_app/shared/widgets/unlock_sheets.dart';

abstract final class PasswordResetSteps {
  /// 步骤 1：说明确认。返回 true = 用户同意继续。
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String message,
    String actionLabel = '使用重置密码盘',
  }) async {
    return GlassDialog.confirm(
      context,
      title: title,
      content: message,
      confirmText: actionLabel,
    );
  }

  /// 步骤 2：选盘读钥匙（password_reset_disk.key，兼容旧名）。
  /// 失败已就地提示；返回 null = 中止。
  static Future<List<int>?> pickAndReadDisk(BuildContext context) async {
    final dir = await ResetDiskFile.pickDirectory();
    if (dir == null || !context.mounted) return null;
    final usbKey = await ResetDiskFile.readFrom(dir);
    if (usbKey == null) {
      if (!context.mounted) return null;
      await alert(
        context,
        '未找到有效钥匙',
        '所选位置未找到有效的重置密码盘文件（password_reset_disk.key）。',
      );
      return null;
    }
    return usbKey;
  }

  /// 步骤 3：新密码两遍（与开屏密码同码直接拒绝——与设密口径一致）。
  /// 返回 null = 中止（原因已就地提示）。
  static Future<String?> collectNewPassword(
    BuildContext context, {
    required String label,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    void snack(String message) =>
        messenger?.showSnackBar(SnackBar(content: Text(message)));

    final pin = await UnlockFlow.show(
      context,
      title: '设置新文件密码',
      flexible: true,
    );
    if (pin == null || !context.mounted) return null;
    if (await AppLockService.matchesAppLockPin(pin)) {
      snack('$label不能与开屏密码相同');
      return null;
    }
    if (!context.mounted) return null;
    final confirmPin = await UnlockFlow.show(
      context,
      title: '确认新文件密码',
      flexible: true,
    );
    if (confirmPin == null || !context.mounted) return null;
    if (confirmPin != pin) {
      snack('两次输入不一致，请重试');
      return null;
    }
    return pin;
  }

  static Future<void> alert(
    BuildContext context,
    String title,
    String message,
  ) {
    return GlassDialog.show<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  static void snack(BuildContext context, String message) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }
}
