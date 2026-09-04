// ============================================================================
// notebook_password_reset_flow.dart —— 分页画布密码「忘记密码」重置流
// （N4 批 3）
// ============================================================================
//
// 前提：分页画布为 v5 双保护器载荷且已绑定重置密码盘（USB 槽位）。
// 流程骨架（公共步骤见 password_reset_common.dart）：说明确认 → 插盘
// 读钥匙 → 新密码两遍（≠开屏密码）→ resetNotebookPasswordWithUsb
// （LUKS 同款：USB 钥匙解出 DEK → 新盐重绕密码槽，payload 密文不动）。
// 成功后会话已缓存新密码——调用方可直接继续解锁打开。

import 'package:flutter/material.dart';

import 'package:drawing_notes_app/features/notes/infrastructure/notebook_storage.dart';
import 'package:drawing_notes_app/features/security/password_reset_common.dart';

abstract final class NotebookPasswordResetFlow {
  /// 运行完整重置流；返回 true = 重置成功（会话已缓存新密码）。
  static Future<bool> show(
    BuildContext context, {
    required NotebookStorage storage,
    required String notebookId,
    String notebookTitle = '',
  }) async {
    final name = notebookTitle.isEmpty ? '该分页画布' : '「$notebookTitle」';

    // 1. 说明确认。
    final proceed = await PasswordResetSteps.confirm(
      context,
      title: '忘记密码',
      message:
          '使用重置密码盘（U 盘）重置$name的密码。\n\n'
          '前提：该分页画布已绑定重置密码盘（设置密码或密码管理中绑定）。',
    );
    if (!proceed || !context.mounted) return false;

    // 2. 未绑定重置盘 → 无法重置（fail-closed，含旧格式提示）。
    if (!await storage.hasNotebookUsbSlot(notebookId)) {
      if (!context.mounted) return false;
      await PasswordResetSteps.alert(
        context,
        '无法重置',
        '$name未绑定重置密码盘（U 盘），无法通过重置盘重置密码。\n\n'
            '可在「设置/修改密码保护」后于菜单中选择「绑定重置密码盘」；'
            '旧版本设置的密码需先修改一次密码升级格式。',
      );
      return false;
    }

    // 3. 插盘读钥匙。
    if (!context.mounted) return false;
    final usbKey = await PasswordResetSteps.pickAndReadDisk(context);
    if (usbKey == null || !context.mounted) return false;

    // 4. 新密码两遍（与开屏密码同码直接拒绝——与设密口径一致）。
    final pin = await PasswordResetSteps.collectNewPassword(
      context,
      label: '密码',
    );
    if (pin == null || !context.mounted) return false;

    // 5. 重置（盘不匹配 / 损坏 → false，fail-closed）。
    final ok = await storage.resetNotebookPasswordWithUsb(
      notebookId,
      usbKey,
      pin,
    );
    if (!ok) {
      if (!context.mounted) return false;
      await PasswordResetSteps.alert(context, '重置失败', '重置密码盘不匹配或已损坏。');
      return false;
    }
    if (!context.mounted) return false;
    PasswordResetSteps.snack(context, '已用重置密码盘重置$name的密码');
    return true;
  }
}
