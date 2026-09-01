// ============================================================================
// app_lock_settings_page.dart —— 应用锁设置页（2026-09-01）
// ============================================================================
//
// 应用启动锁的管理入口（首页「更多操作 → 应用锁」）：
// - 未配置：开启开关 → 设置密码 → 确认密码（两次一致即生效）；
// - 已配置：修改密码（先验证旧密码）/ 关闭应用锁（先验证旧密码）；
// - 忘记密码如实提示：首版无找回机制。

import 'package:flutter/material.dart';

import 'package:drawing_notes_app/core/security/app_lock_service.dart';
import 'package:drawing_notes_app/fix/security_and_sync_fix.dart'
    show UnlockFlow;

/// 应用锁设置页。
///
/// 开关状态以 [AppLockService] 为单一事实来源（ListenableBuilder 联动）：
/// 流程被用户取消时 service 状态不变，开关自动回弹，无需本地状态机。
class AppLockSettingsPage extends StatelessWidget {
  const AppLockSettingsPage({super.key, required this.service});

  final AppLockService service;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('应用锁')),
      body: ListenableBuilder(
        listenable: service,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      Icons.lock_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text('开启后，每次打开应用或切后台回来，都需要输入密码才能进入。'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    value: service.isConfigured,
                    onChanged: (on) {
                      if (on) {
                        _startEnableFlow(context);
                      } else {
                        _startDisableFlow(context);
                      }
                    },
                    title: const Text('应用锁'),
                    subtitle: Text(service.isConfigured ? '已开启' : '未开启'),
                  ),
                  if (service.isConfigured)
                    ListTile(
                      leading: const Icon(Icons.password_rounded),
                      title: const Text('修改密码'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _startModifyFlow(context),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '忘记密码将无法找回（首版无找回机制），请牢记密码。',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 两步设置新密码：设置 → 确认（一致才生效）。
  Future<void> _startEnableFlow(BuildContext context) async {
    final pin = await UnlockFlow.show(context, title: '设置密码');
    if (pin == null || !context.mounted) return;
    final confirm = await UnlockFlow.show(context, title: '确认密码');
    if (confirm == null || !context.mounted) return;
    if (confirm != pin) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('两次输入不一致，请重新设置')));
      return;
    }
    await service.setPin(pin);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('应用锁已开启')));
  }

  /// 验证旧密码后关闭应用锁。
  Future<void> _startDisableFlow(BuildContext context) async {
    final pin = await UnlockFlow.show(
      context,
      title: '验证当前密码',
      onVerify: (p) => service.verify(p),
    );
    if (pin == null || !context.mounted) return; // 取消（或验证失败后放弃）
    await service.disable();
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('应用锁已关闭')));
  }

  /// 验证旧密码后走两步设置新密码。
  Future<void> _startModifyFlow(BuildContext context) async {
    final oldPin = await UnlockFlow.show(
      context,
      title: '验证当前密码',
      onVerify: (p) => service.verify(p),
    );
    if (oldPin == null || !context.mounted) return;
    await _startEnableFlow(context);
  }
}
