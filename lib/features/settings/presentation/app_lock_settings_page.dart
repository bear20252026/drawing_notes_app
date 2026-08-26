import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/security/app_lock_service.dart';
import '../../../core/theme/app_design.dart';

/// 应用锁定设置页面 — 设置/修改/取消应用密码。
///
/// 功能：
/// - 设置新密码（6 位 PIN）
/// - 修改密码（需验证旧密码）
/// - 取消密码（需验证当前密码）
/// - 切换生物识别
class AppLockSettingsPage extends ConsumerStatefulWidget {
  const AppLockSettingsPage({super.key});

  @override
  ConsumerState<AppLockSettingsPage> createState() =>
      _AppLockSettingsPageState();
}

class _AppLockSettingsPageState extends ConsumerState<AppLockSettingsPage> {
  final AppLockService _service = AppLockService.instance;
  bool _biometricAvailable = false;

  @override
  void initState() {
    super.initState();
    _checkBiometric();
  }

  Future<void> _checkBiometric() async {
    final available = await AppLockService.isBiometricAvailable();
    if (mounted) {
      setState(() {
        _biometricAvailable = available;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isEnabled = _service.enabled;

    return Scaffold(
      backgroundColor:
          isDark ? AppDesign.surfaceBlack : AppDesign.canvasParchment,
      body: CustomScrollView(
        slivers: [
          // ─── 大标题 ───
          SliverAppBar(
            floating: true,
            backgroundColor:
                isDark ? AppDesign.surfaceBlack : AppDesign.canvasParchment,
            surfaceTintColor: Colors.transparent,
            toolbarHeight: 44,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 20),
              onPressed: () => context.pop(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsetsDirectional.only(
                start: 16,
                bottom: 12,
              ),
              title: Text(
                '应用锁定',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.28,
                  color: isDark ? AppDesign.bodyOnDark : AppDesign.ink,
                ),
              ),
            ),
          ),

          // ─── 内容 ───
          SliverPadding(
            padding: const EdgeInsets.only(
              top: 8,
              bottom: AppDesign.spacingSection,
            ),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ── 应用锁定开关 ──
                const _SectionHeader(title: '应用锁定'),
                _InsetGroupedCard(
                  children: [
                    _SettingsTile(
                      icon: Icons.screen_lock_portrait_rounded,
                      iconColor: AppDesign.appleOrange,
                      title: '启用应用锁定',
                      subtitle: '每次打开应用时需要输入密码',
                      trailing: CupertinoSwitch(
                        value: isEnabled,
                        activeColor: AppDesign.appleGreen,
                        onChanged: (v) => _onToggleEnabled(v),
                      ),
                    ),
                  ],
                ),

                if (isEnabled) ...[
                  const SizedBox(height: AppDesign.spacingSection),

                  // ── 密码管理 ──
                  const _SectionHeader(title: '密码管理'),
                  _InsetGroupedCard(
                    children: [
                      _SettingsTile(
                        icon: Icons.edit_rounded,
                        iconColor: AppDesign.primary,
                        title: '修改密码',
                        subtitle: '更改应用锁定密码',
                        trailing: Icon(Icons.chevron_right, size: 18),
                        onTap: () => _showChangePasswordDialog(),
                      ),
                      const _Divider(),
                      _SettingsTile(
                        icon: Icons.lock_open_rounded,
                        iconColor: const Color(0xFFFF3B30),
                        title: '取消应用锁定',
                        subtitle: '移除应用锁定密码',
                        trailing: Icon(Icons.chevron_right, size: 18),
                        onTap: () => _showRemovePasswordDialog(),
                      ),
                    ],
                  ),

                  const SizedBox(height: AppDesign.spacingSection),

                  // ── 生物识别 ──
                  const _SectionHeader(title: '生物识别'),
                  _InsetGroupedCard(
                    children: [
                      _SettingsTile(
                        icon: Icons.fingerprint,
                        iconColor: AppDesign.appleGreen,
                        title: '生物识别解锁',
                        subtitle: _biometricAvailable
                            ? '使用指纹或面容解锁'
                            : '当前设备不支持生物识别',
                        trailing: CupertinoSwitch(
                          value: _service.biometricEnabled,
                          activeColor: AppDesign.appleGreen,
                          onChanged: _biometricAvailable
                              ? (v) => _service.setBiometricEnabled(v)
                              : null,
                        ),
                      ),
                    ],
                  ),
                ],

                // ── 提示信息 ──
                if (isEnabled) ...[
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      '应用锁定会在每次打开应用时要求输入密码。'
                      '如果连续 5 次输入错误，将触发阶梯锁定。',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? AppDesign.bodyMuted
                            : AppDesign.inkMuted48,
                      ),
                    ),
                  ),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onToggleEnabled(bool enabled) async {
    if (enabled) {
      // 开启：显示设置密码对话框
      final result = await _showSetPasswordDialog();
      if (result != true) {
        // 用户取消，不切换开关
        setState(() {});
      }
    } else {
      // 关闭：显示取消密码对话框
      await _showRemovePasswordDialog();
    }
  }

  Future<bool?> _showSetPasswordDialog() async {
    final controller = TextEditingController();
    final confirmController = TextEditingController();
    String? errorText;

    return showDialog<bool>(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor:
                  isDark ? AppDesign.surfaceTile1 : AppDesign.canvas,
              title: const Text('设置应用密码'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: InputDecoration(
                      labelText: '输入 6 位密码',
                      errorText: errorText,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmController,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      labelText: '确认密码',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () async {
                    final password = controller.text;
                    final confirm = confirmController.text;

                    if (password.length < 6) {
                      setDialogState(() {
                        errorText = '密码至少 6 位';
                      });
                      return;
                    }

                    if (password != confirm) {
                      setDialogState(() {
                        errorText = '两次输入不一致';
                      });
                      return;
                    }

                    final success = await _service.setPassword(password);
                    if (success) {
                      if (context.mounted) {
                        Navigator.of(context).pop(true);
                        _showSuccessSnackBar('应用密码已设置');
                      }
                    } else {
                      setDialogState(() {
                        errorText = '设置失败，请重试';
                      });
                    }
                  },
                  child: const Text('确定'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showChangePasswordDialog() async {
    final oldController = TextEditingController();
    final newController = TextEditingController();
    final confirmController = TextEditingController();
    String? errorText;

    await showDialog(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor:
                  isDark ? AppDesign.surfaceTile1 : AppDesign.canvas,
              title: const Text('修改应用密码'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: oldController,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      labelText: '当前密码',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: newController,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: InputDecoration(
                      labelText: '新密码',
                      errorText: errorText,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmController,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      labelText: '确认新密码',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () async {
                    final oldPassword = oldController.text;
                    final newPassword = newController.text;
                    final confirm = confirmController.text;

                    if (newPassword.length < 6) {
                      setDialogState(() {
                        errorText = '新密码至少 6 位';
                      });
                      return;
                    }

                    if (newPassword != confirm) {
                      setDialogState(() {
                        errorText = '两次输入不一致';
                      });
                      return;
                    }

                    final success = await _service.changePassword(
                      oldPassword: oldPassword,
                      newPassword: newPassword,
                    );

                    if (context.mounted) {
                      Navigator.of(context).pop();
                      if (success) {
                        _showSuccessSnackBar('密码已修改');
                      } else {
                        _showErrorSnackBar('当前密码错误');
                      }
                    }
                  },
                  child: const Text('确定'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showRemovePasswordDialog() async {
    final controller = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor:
              isDark ? AppDesign.surfaceTile1 : AppDesign.canvas,
          title: const Text('取消应用锁定'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('请输入当前密码以取消应用锁定。'),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                  labelText: '当前密码',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFFF3B30),
              ),
              onPressed: () async {
                final success = await _service.removePassword(controller.text);
                if (context.mounted) {
                  Navigator.of(context).pop();
                  if (success) {
                    setState(() {});
                    _showSuccessSnackBar('应用锁定已取消');
                  } else {
                    _showErrorSnackBar('密码错误');
                  }
                }
              },
              child: const Text('确认取消'),
            ),
          ],
        );
      },
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppDesign.appleGreen,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFFFF3B30),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

// ─── 复用 settings_page.dart 中的组件 ───

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
        highlightColor: AppDesign.primary.withValues(alpha: 0.12),
        splashColor: Colors.transparent,
        borderRadius: BorderRadius.circular(AppDesign.roundedLg),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 11,
          ),
          child: Row(
            children: [
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
