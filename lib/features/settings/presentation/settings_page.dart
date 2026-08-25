import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 设置页面 — 主题、语言、加密、备份等。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 外观
          _SectionHeader(title: '外观'),
          _SettingsTile(
            icon: Icons.brightness_6,
            title: '主题模式',
            subtitle: isDark ? '深色' : '浅色',
            trailing: Switch(
              value: isDark,
              onChanged: (v) {
                // TODO: 接入 ThemeNotifier
              },
            ),
          ),
          _SettingsTile(
            icon: Icons.language,
            title: '语言',
            subtitle: '中文',
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              // TODO: 语言选择器
            },
          ),
          const Divider(),

          // 加密与安全
          _SectionHeader(title: '加密与安全'),
          _SettingsTile(
            icon: Icons.lock_outline,
            title: '密码盘',
            subtitle: '管理密码盘认证',
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/password-disk'),
          ),
          _SettingsTile(
            icon: Icons.key,
            title: '主密码',
            subtitle: '更改主密码',
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              // TODO: 主密码修改
            },
          ),
          const Divider(),

          // 备份与同步
          _SectionHeader(title: '备份与同步'),
          _SettingsTile(
            icon: Icons.backup_outlined,
            title: '导出数据',
            subtitle: '导出所有笔记和画作',
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              // TODO: 导出功能
            },
          ),
          _SettingsTile(
            icon: Icons.restore,
            title: '导入数据',
            subtitle: '从备份文件恢复',
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              // TODO: 导入功能
            },
          ),
          const Divider(),

          // 关于
          _SectionHeader(title: '关于'),
          _SettingsTile(
            icon: Icons.info_outline,
            title: '版本',
            subtitle: 'drawing_notes_app v0.1.0',
          ),
          _SettingsTile(
            icon: Icons.gavel,
            title: '开源许可',
            subtitle: '查看第三方库许可',
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              showLicensePage(
                context: context,
                applicationName: 'Drawing Notes',
                applicationVersion: 'v0.1.0',
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8, left: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      trailing: trailing ?? const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
