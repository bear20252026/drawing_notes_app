// 批次⑤：第四界面「设置」——密码体系与通用设置的集中管理入口。
//
// 单一事实来源：密码类设置（应用锁/单文件密码）与通用设置
// （外观/WebDAV）此前散落在 HomePage 的 AppBar 图标与「更多」菜单里，
// 本页收编为唯一入口（HomePage 原入口随批次⑤移除，功能只搬家不删除）。
import 'package:flutter/material.dart';

import 'package:drawing_notes_app/core/security/app_lock_service.dart';
import 'package:drawing_notes_app/core/security/quick_unlock_service.dart';
import 'package:drawing_notes_app/core/security/vault_key_service.dart';
import 'package:drawing_notes_app/core/theme/app_theme_controller.dart';
import 'package:drawing_notes_app/features/notes/presentation/app_lock_settings_page.dart';
import 'package:drawing_notes_app/features/notes/presentation/webdav_sync_settings_page.dart';

/// 设置页：密码与安全 + 通用两大分组。
///
/// 注入均为可选（app_shell 组合根传入；测试装配可不传——对应分组
/// 自动隐藏或降级为提示，不崩溃）。
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    this.appLockService,
    this.vaultKeyService,
    this.quickUnlockService,
    this.themeController,
  });

  /// 应用锁服务（应用锁入口需要；null 时隐藏应用锁入口）。
  final AppLockService? appLockService;

  /// 主密钥保险库（U 盘恢复钥匙绑定需要；与开屏密码共用同一位密码）。
  final VaultKeyService? vaultKeyService;

  /// 系统验证快速解锁（批D1；null 时快速解锁开关不出现）。
  final QuickUnlockService? quickUnlockService;

  /// 外观控制器（外观入口需要；null 时隐藏外观入口）。
  final AppThemeController? themeController;

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outline;
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          const _PasswordLayersCard(),
          const SizedBox(height: 16),
          _SectionHeader(title: '密码与安全', outline: outline),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                if (appLockService != null)
                  ListTile(
                    leading: const Icon(Icons.lock_outline_rounded),
                    title: const Text('应用锁'),
                    subtitle: const Text('开屏密码 · 重置密码盘'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _openAppLock(context),
                  ),
                ListTile(
                  leading: const Icon(Icons.enhanced_encryption_rounded),
                  title: const Text('单文件密码'),
                  subtitle: const Text('个别画布的第二道锁（在画布卡片设置）'),
                  trailing: const Icon(Icons.help_outline_rounded),
                  onTap: () => _showFilePasswordHelp(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionHeader(title: '通用', outline: outline),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                if (themeController != null)
                  ListTile(
                    leading: Icon(
                      themeController!.mode == ThemeMode.dark
                          ? Icons.dark_mode_rounded
                          : Icons.light_mode_rounded,
                    ),
                    title: const Text('外观'),
                    subtitle: Text(_themeLabel(themeController!.mode)),
                    trailing: const Icon(Icons.sync_alt_rounded),
                    onTap: themeController!.cycle,
                  ),
                // 高对比度（平台域裁决 C2）：Windows 用户在系统设置里开了
                // 高对比度后，常规的 8% 发丝线会淡到看不见，这里提供
                // 手动三态开关（跟随系统 / 强制开 / 强制关）。
                // 注意：与「外观」同受 themeController 非空保护——设置页
                // 允许无控制器渲染（部分测试与嵌入场景直接构造）。
                if (themeController != null)
                  ListTile(
                    leading: Icon(
                      themeController!.highContrastOverride == true
                          ? Icons.contrast_rounded
                          : Icons.contrast_outlined,
                    ),
                    title: const Text('高对比度'),
                    subtitle: Text(themeController!.highContrastLabel),
                    trailing: const Icon(Icons.sync_alt_rounded),
                    onTap: () => themeController!.cycleHighContrast(),
                  ),
                ListTile(
                  leading: const Icon(Icons.cloud_sync_outlined),
                  title: const Text('WebDAV 同步'),
                  subtitle: const Text('本地优先，跨设备同步'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const WebDavSyncSettingsPage(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openAppLock(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AppLockSettingsPage(
          service: appLockService!,
          vault: vaultKeyService,
          quickUnlock: quickUnlockService,
        ),
      ),
    );
  }

  void _showFilePasswordHelp(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('单文件密码'),
        content: const Text(
          '在首页或全部文档页，点击画布卡片上的锁形按钮，可为单个画布'
          '设置独立密码。设置后打开该画布需要输入此密码，缩略图也会'
          '隐藏为锁形占位。\n\n'
          '单文件密码独立于开屏密码——即使有人解锁了你的应用，没有'
          '这个密码也打不开对应的画布。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  String _themeLabel(ThemeMode mode) => switch (mode) {
    ThemeMode.system => '跟随系统（点击切换为浅色）',
    ThemeMode.light => '浅色（点击切换为深色）',
    ThemeMode.dark => '深色（点击切换为跟随系统）',
  };
}

/// 密码体系展示卡：一眼看懂「谁保护谁」。
///
/// 两层锁 + 一把 U 盘（2026-09-02 命名体系定案）：
/// 第 1 层开屏密码护 App；第 2 层文件密码护单个文件；
/// 重置密码盘（U 盘）是两层「忘记密码」的统一重置通道。
class _PasswordLayersCard extends StatelessWidget {
  const _PasswordLayersCard();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.layers_rounded, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Text('密码体系', style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 10),
            _layer(
              context,
              icon: Icons.smartphone_rounded,
              title: '第 1 层 · 开屏密码',
              desc:
                  '解锁应用，同时解开主密钥保险库——保护全部画布与笔记。'
                  '忘记时可用重置密码盘重设。',
            ),
            _divider(scheme),
            _layer(
              context,
              icon: Icons.enhanced_encryption_rounded,
              title: '第 2 层 · 文件密码',
              desc:
                  '给单个画布/分页画布/笔记另设的独立密码，独立于开屏密码。'
                  '忘记时可用重置密码盘重设。',
            ),
            _divider(scheme),
            _layer(
              context,
              icon: Icons.usb_rounded,
              title: '重置密码盘（U 盘）',
              desc:
                  '插入 U 盘 → 点「忘记密码」→ 重置新密码。'
                  '开屏密码与文件密码通用同一把盘。',
            ),
          ],
        ),
      ),
    );
  }

  Widget _layer(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String desc,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: scheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 2),
              Text(
                desc,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.outline),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _divider(ColorScheme scheme) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Divider(height: 1, color: scheme.outlineVariant),
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.outline});

  final String title;
  final Color outline;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 0, 6),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(color: outline),
      ),
    );
  }
}
