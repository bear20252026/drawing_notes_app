import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_design.dart';

/// 设置页面 — Apple Inset Grouped 风格 + 大标题。
///
/// 参照 Apple HIG Settings 页面：
/// - SliverAppBar 浮动大标题
/// - Inset Grouped 卡片分组（圆角 18px）
/// - 左侧图标 + 标题 + 右侧 chevron
/// - hairline 分隔线
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppDesign.surfaceBlack : AppDesign.canvasParchment,
      body: CustomScrollView(
        slivers: [
          // ─── 大标题 SliverAppBar ─────────────────────────────────
          SliverAppBar(
            floating: true,
            backgroundColor: isDark ? AppDesign.surfaceBlack : AppDesign.canvasParchment,
            surfaceTintColor: Colors.transparent,
            toolbarHeight: 44,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 20),
              onPressed: () => context.canPop() ? context.pop() : context.go('/'),
            ),
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsetsDirectional.only(
                start: 16,
                bottom: 12,
              ),
              title: Text(
                '设置',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.28,
                  color: isDark ? AppDesign.bodyOnDark : AppDesign.ink,
                ),
              ),
            ),
          ),

          // ─── 内容 ───────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.only(
              top: 8,
              bottom: AppDesign.spacingSection,
            ),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ── 外观 ──
                const _SectionHeader(title: '外观'),
                _InsetGroupedCard(
                  children: [
                    _SettingsTile(
                      icon: Icons.brightness_6_rounded,
                      iconColor: AppDesign.primary,
                      title: '主题模式',
                      subtitle: isDark ? '深色' : '浅色',
                      trailing: CupertinoSwitch(
                        value: isDark,
                        activeColor: AppDesign.appleGreen,
                        onChanged: (v) {
                          // TODO: 接入 ThemeNotifier
                        },
                      ),
                    ),
                    const _Divider(),
                    _SettingsTile(
                      icon: Icons.language_rounded,
                      iconColor: AppDesign.primary,
                      title: '语言',
                      subtitle: '中文',
                      trailing: Icon(Icons.chevron_right, size: 18),
                      onTap: () {
                        // TODO: 语言选择器
                      },
                    ),
                  ],
                ),

                const SizedBox(height: AppDesign.spacingSection),

                // ── 加密与安全 ──
                const _SectionHeader(title: '加密与安全'),
                _InsetGroupedCard(
                  children: [
                    _SettingsTile(
                      icon: Icons.lock_outline_rounded,
                      iconColor: AppDesign.appleOrange,
                      title: '密码盘',
                      subtitle: '管理密码盘认证',
                      trailing: Icon(Icons.chevron_right, size: 18),
                      onTap: () => context.push('/password-disk'),
                    ),
                    const _Divider(),
                    _SettingsTile(
                      icon: Icons.key_rounded,
                      iconColor: AppDesign.appleOrange,
                      title: '主密码',
                      subtitle: '更改主密码',
                      trailing: Icon(Icons.chevron_right, size: 18),
                      onTap: () {
                        // TODO: 主密码修改
                      },
                    ),
                  ],
                ),

                const SizedBox(height: AppDesign.spacingSection),

                // ── 备份与同步 ──
                const _SectionHeader(title: '备份与同步'),
                _InsetGroupedCard(
                  children: [
                    _SettingsTile(
                      icon: Icons.cloud_upload_outlined,
                      iconColor: AppDesign.appleGreen,
                      title: '导出数据',
                      subtitle: '导出所有笔记和画作',
                      trailing: Icon(Icons.chevron_right, size: 18),
                      onTap: () {
                        // TODO: 导出功能
                      },
                    ),
                    const _Divider(),
                    _SettingsTile(
                      icon: Icons.cloud_download_outlined,
                      iconColor: AppDesign.appleGreen,
                      title: '导入数据',
                      subtitle: '从备份文件恢复',
                      trailing: Icon(Icons.chevron_right, size: 18),
                      onTap: () {
                        // TODO: 导入功能
                      },
                    ),
                  ],
                ),

                const SizedBox(height: AppDesign.spacingSection),

                // ── 关于 ──
                const _SectionHeader(title: '关于'),
                _InsetGroupedCard(
                  children: [
                    _SettingsTile(
                      icon: Icons.info_outline_rounded,
                      iconColor: AppDesign.inkMuted48,
                      title: '版本',
                      subtitle: 'drawing_notes_app v0.1.0',
                    ),
                    const _Divider(),
                    _SettingsTile(
                      icon: Icons.gavel_rounded,
                      iconColor: AppDesign.inkMuted48,
                      title: '开源许可',
                      subtitle: '查看第三方库许可',
                      trailing: Icon(Icons.chevron_right, size: 18),
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
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 分区标题（Apple HIG: 13px/600, muted color） ──────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(
        left: 32,
        right: 16,
        bottom: AppDesign.spacingXs,
      ),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
          color: isDark ? AppDesign.bodyMuted : AppDesign.inkMuted48,
        ),
      ),
    );
  }
}

// ─── Inset Grouped 卡片（Apple HIG: 18px radius, 16px margin） ──────
class _InsetGroupedCard extends StatelessWidget {
  final List<Widget> children;
  const _InsetGroupedCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: isDark ? AppDesign.surfaceTile1 : AppDesign.canvas,
        borderRadius: BorderRadius.circular(AppDesign.roundedLg),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}

// ─── 分隔线（hairline: 0.5px，左缩进 52px 对齐标题文字） ─────────────
class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Divider(
      height: 0.5,
      thickness: 0.5,
      indent: 52,
      endIndent: 0,
      color: isDark
          ? AppDesign.bodyMuted.withValues(alpha: 0.2)
          : AppDesign.dividerSoft,
    );
  }
}

// ─── 设置项（图标 + 标题 + 可选副标题 + 可选 trailing） ─────────────
class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 11,
          ),
          child: Row(
            children: [
              // ── 图标（圆角方形背景） ──
              Container(
                width: 29,
                height: 29,
                decoration: BoxDecoration(
                  color: iconColor,
                  borderRadius: BorderRadius.circular(AppDesign.roundedSm),
                ),
                child: Icon(
                  icon,
                  size: 17,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              // ── 标题 + 副标题 ──
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w400,
                        height: 1.47,
                        letterSpacing: -0.374,
                        color: isDark ? AppDesign.bodyOnDark : AppDesign.ink,
                      ),
                    ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle!,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            height: 1.0,
                            letterSpacing: -0.12,
                            color: isDark
                                ? AppDesign.bodyMuted
                                : AppDesign.inkMuted48,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // ── Trailing ──
              if (trailing != null)
                DefaultTextStyle(
                  style: TextStyle(
                    fontSize: 17,
                    color: isDark ? AppDesign.bodyMuted : AppDesign.inkMuted48,
                  ),
                  child: trailing!,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
