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
import 'package:drawing_notes_app/core/security/vault_key_service.dart';
import 'package:drawing_notes_app/core/storage/password_disk.dart';
import 'package:drawing_notes_app/core/storage/usb_reset_key_file.dart';
import 'package:drawing_notes_app/fix/security_and_sync_fix.dart'
    show UnlockFlow;

/// 应用锁设置页。
///
/// 开关状态以 [AppLockService] 为单一事实来源（ListenableBuilder 联动）：
/// 流程被用户取消时 service 状态不变，开关自动回弹，无需本地状态机。
class AppLockSettingsPage extends StatelessWidget {
  const AppLockSettingsPage({
    super.key,
    required this.service,
    this.vault,
    this.disk,
  });

  final AppLockService service;

  /// 主密钥保险库（批次①b）：与开屏密码共用同一位密码——
  /// 设置密码时同步建库、修改密码时同步重包裹；保险库已存在时
  /// 「关闭应用锁」被阻止（文件已用该密码加密，关闭将导致不可读）。
  final VaultKeyService? vault;

  /// 密码盘抽象（批次④）：绑定 U 盘恢复钥匙时选取 U 盘目录；
  /// null 时 Debug/测试用 Mock、Release 用 Real（createPasswordDisk 工厂）。
  final PasswordDisk? disk;

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
                  // 批次④：U 盘恢复钥匙（LUKS/BitLocker 多保护器模式——
                  // 忘记密码时可用 U 盘重设，主密钥副本不出设备）。
                  if (service.isConfigured && vault != null)
                    _buildUsbKeyTile(context),
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
                      service.isConfigured
                          ? '绑定 U 盘恢复钥匙后，忘记密码可用 U 盘重设；'
                                '未绑定时忘记密码将无法找回。'
                          : '开启应用锁后，可绑定 U 盘恢复钥匙以防忘记密码。',
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

  /// 批次④：U 盘恢复钥匙 tile（绑定状态异步查询，绑定/解除后刷新）。
  Widget _buildUsbKeyTile(BuildContext context) {
    final vault = this.vault!;
    return FutureBuilder<bool>(
      future: vault.hasUsbSlot(),
      builder: (context, snapshot) {
        final bound = snapshot.data ?? false;
        return ListTile(
          leading: const Icon(Icons.usb_rounded),
          title: const Text('U 盘恢复钥匙'),
          subtitle: Text(
            snapshot.hasError
                ? '状态未知（保险库读取失败）'
                : bound
                ? '已绑定（忘记密码时可用 U 盘重设）'
                : '未绑定（忘记密码将无法找回）',
          ),
          trailing: TextButton(
            onPressed: () => bound
                ? _startUnbindUsbFlow(context, vault)
                : _startBindUsbFlow(context, vault),
            child: Text(bound ? '解除绑定' : '绑定'),
          ),
        );
      },
    );
  }

  /// 批次④：绑定 U 盘恢复钥匙。
  ///
  /// 链路：验证当前密码（顺带确保保险库解锁）→ 选 U 盘 → 写入
  /// vault_reset.frogkey（随机 32B 钥匙，不含任何主密钥副本）→
  /// 保险库槽 2 以该钥匙包裹主密钥。
  Future<void> _startBindUsbFlow(
    BuildContext context,
    VaultKeyService vault,
  ) async {
    // 验证当前密码（identity gate；失败计入防爆破守卫——合理的防滥用）。
    final pin = await UnlockFlow.show(
      context,
      title: '验证当前密码',
      onVerify: (p) => service.verify(p),
    );
    if (pin == null || !context.mounted) return;
    try {
      if (!vault.isUnlocked) await vault.unlock(pin);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('保险库解锁失败，请重试')));
      return;
    }

    // 选取 U 盘目录。
    final disk = this.disk ?? createPasswordDisk();
    final dir = await disk.pickDirectory();
    if (dir == null || !context.mounted) return;

    // 写入恢复钥匙文件 + 建立槽 2。
    try {
      final externalKey = await UsbResetKeyFile.writeTo(dir);
      await vault.addUsbKeySlot(externalKey: externalKey);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('绑定失败：${e.runtimeType}')));
      return;
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          '已绑定。请妥善保管 U 盘：U 盘丢失将无法重置密码，'
          'U 盘上的 vault_reset.frogkey 文件请勿删除',
        ),
        duration: Duration(seconds: 5),
      ),
    );
  }

  /// 批次④：解除绑定（只删设备侧槽 2；U 盘上的钥匙文件须用户自行删除）。
  Future<void> _startUnbindUsbFlow(
    BuildContext context,
    VaultKeyService vault,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('解除 U 盘恢复钥匙'),
        content: const Text(
          '解除后，忘记密码将无法重置。\n\n'
          'U 盘上的 vault_reset.frogkey 文件不会被删除，请自行删除。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('解除绑定'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await vault.removeUsbKeySlot();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('解除失败：${e.runtimeType}')));
      return;
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已解除绑定')));
  }

  /// 先选密码长度（4–12 位），再走两步设置：设置 → 确认（一致才生效）。
  ///
  /// [oldPinForVault] 非空表示「修改密码」流程：保险库以旧 PIN 换盐
  /// 重包裹（主密钥不变，已加密文件无需迁移）。
  Future<void> _startEnableFlow(
    BuildContext context, {
    String? oldPinForVault,
  }) async {
    final length = await _pickPinLength(context);
    if (length == null || !context.mounted) return;
    final pin = await UnlockFlow.show(
      context,
      title: '设置密码',
      pinLength: length,
    );
    if (pin == null || !context.mounted) return;
    final confirm = await UnlockFlow.show(
      context,
      title: '确认密码',
      pinLength: length,
    );
    if (confirm == null || !context.mounted) return;
    if (confirm != pin) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('两次输入不一致，请重新设置')));
      return;
    }
    await service.setPin(pin);
    // 批次①b：保险库与开屏密码同步生命周期。
    final vault = this.vault;
    if (vault != null) {
      try {
        if (oldPinForVault != null && await vault.isConfigured()) {
          await vault.changePin(oldPin: oldPinForVault, newPin: pin);
        } else if (!await vault.isConfigured()) {
          await vault.initialize(pin);
        }
      } catch (_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('文件加密同步失败，请重试或联系开发者')));
        return;
      }
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('应用锁已开启')));
  }

  /// 验证旧密码后关闭应用锁。
  ///
  /// 批次①b 起文件以开屏密码加密：保险库已存在时关闭被阻止
  /// （fail-closed——关掉锁不能让密文变成不可管理的孤儿）。
  Future<void> _startDisableFlow(BuildContext context) async {
    final vault = this.vault;
    if (vault != null && await vault.isConfigured()) {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('无法关闭应用锁'),
          content: const Text(
            '你的文件已使用开屏密码加密保护，关闭应用锁会导致加密文件'
            '无法解锁读取。\n\n如需更换密码，请使用「修改密码」。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    }
    if (!context.mounted) return; // isConfigured 为异步操作，跨缺口再查一次
    final pin = await UnlockFlow.show(
      context,
      title: '验证当前密码',
      pinLength: service.pinLength,
      onVerify: (p) => service.verify(p),
    );
    if (pin == null || !context.mounted) return; // 取消（或验证失败后放弃）
    await service.disable();
    if (!context.mounted) return; // disable 为异步操作，跨异步缺口再查一次
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('应用锁已关闭')));
  }

  /// 验证旧密码后走两步设置新密码。
  Future<void> _startModifyFlow(BuildContext context) async {
    final oldPin = await UnlockFlow.show(
      context,
      title: '验证当前密码',
      pinLength: service.pinLength,
      onVerify: (p) => service.verify(p),
    );
    if (oldPin == null || !context.mounted) return;
    await _startEnableFlow(context, oldPinForVault: oldPin);
  }

  /// 密码长度选择器：Slider 4–12 位，默认沿用当前长度（无则 4）。
  Future<int?> _pickPinLength(BuildContext context) async {
    var selected = service.pinLength;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('密码长度'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$selected 位',
                style: Theme.of(dialogContext).textTheme.headlineSmall,
              ),
              Slider(
                value: selected.toDouble(),
                min: AppLockService.minPinLength.toDouble(),
                max: AppLockService.maxPinLength.toDouble(),
                divisions:
                    AppLockService.maxPinLength - AppLockService.minPinLength,
                label: '$selected',
                onChanged: (v) => setDialogState(() => selected = v.round()),
              ),
              Text(
                '建议 6 位以上，纯数字密码强度有限。',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(dialogContext).colorScheme.outline,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('下一步'),
            ),
          ],
        ),
      ),
    );
    return confirmed == true ? selected : null;
  }
}
