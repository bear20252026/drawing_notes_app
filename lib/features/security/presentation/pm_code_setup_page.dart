/// PM码（胁迫密码）设置页面 — Apple HIG 风格。
///
/// 在设置 → 加密与安全 → PM码 中访问。
/// 功能：
/// 1. 设置 PM码（输入当前密码 + 新 PM码）
/// 2. 修改 PM码（验证旧 PM码 + 输入新 PM码）
/// 3. 关闭 PM码（验证 PM码 后删除）
/// 4. 销毁密钥（⚠️ 不可逆操作）
///
/// 版权声明：本实现借鉴了以下开源项目的设计理念：
/// - kurpod (github.com/srv1n/kurpod) — AGPL-3.0
/// - Sanctum (github.com/Teycir/Sanctum) — 项目自定义许可
/// - CipherVault (github.com/vipecoder228/CipherVault) — MIT
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/pm_code_provider.dart';
import '../../../../core/security/interfaces/pm_code_service.dart';
import '../../../../core/theme/app_design.dart';
import '../../../../core/ui/widgets/apple_pin_input.dart';
import '../../../../core/ui/widgets/ios_dialog.dart';

/// PM码设置页面。
class PmCodeSetupPage extends ConsumerStatefulWidget {
  const PmCodeSetupPage({super.key});

  /// 路由路径。
  static const String routePath = '/pm-code-setup';

  @override
  ConsumerState<PmCodeSetupPage> createState() => _PmCodeSetupPageState();
}

class _PmCodeSetupPageState extends ConsumerState<PmCodeSetupPage> {
  bool _isConfigured = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final pmCodeService = ref.read(pmCodeServiceProvider);
    final configured = await pmCodeService.isConfigured();
    if (mounted) {
      setState(() {
        _isConfigured = configured;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppDesign.surfaceBlack : AppDesign.canvasParchment,
      appBar: AppBar(
        backgroundColor:
            isDark ? AppDesign.surfaceBlack : AppDesign.canvasParchment,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => context.pop(),
        ),
        title: const Text('PM码（胁迫密码）'),
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: isDark ? AppDesign.bodyOnDark : AppDesign.ink,
        ),
      ),
      body: _isLoading
          ? const Center(child: CupertinoActivityIndicator(radius: 14))
          : CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.only(
                    top: 8,
                    bottom: AppDesign.spacingSection,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      // ── 说明文字 ──
                      _buildInfoSection(isDark),

                      const SizedBox(height: AppDesign.spacingSection),

                      // ── PM码操作 ──
                      if (_isConfigured) ...[
                        const _SectionHeader(title: 'PM码管理'),
                        _InsetGroupedCard(
                          children: [
                            _SettingsTile(
                              icon: Icons.edit_rounded,
                              iconColor: AppDesign.appleOrange,
                              title: '修改PM码',
                              trailing:
                                  const Icon(Icons.chevron_right, size: 18),
                              onTap: _changePmCode,
                            ),
                            const _Divider(),
                            _SettingsTile(
                              icon: Icons.delete_outline_rounded,
                              iconColor: const Color(0xFFFF3B30),
                              title: '关闭PM码',
                              subtitle: '删除胁迫密码',
                              trailing:
                                  const Icon(Icons.chevron_right, size: 18),
                              onTap: _disablePmCode,
                            ),
                          ],
                        ),
                      ] else ...[
                        const _SectionHeader(title: '启用PM码'),
                        _InsetGroupedCard(
                          children: [
                            _SettingsTile(
                              icon: Icons.add_circle_outline_rounded,
                              iconColor: AppDesign.appleGreen,
                              title: '设置PM码',
                              subtitle: '设置一个独立的胁迫密码',
                              trailing:
                                  const Icon(Icons.chevron_right, size: 18),
                              onTap: _setupPmCode,
                            ),
                          ],
                        ),
                      ],

                      const SizedBox(height: AppDesign.spacingSection),

                      // ── 危险操作 ──
                      if (_isConfigured) ...[
                        const _SectionHeader(title: '危险操作'),
                        _InsetGroupedCard(
                          children: [
                            _SettingsTile(
                              icon: Icons.warning_amber_rounded,
                              iconColor: const Color(0xFFFF3B30),
                              title: '销毁真实密钥',
                              subtitle: '⚠️ 不可逆操作！将永久隐藏真实数据',
                              trailing:
                                  const Icon(Icons.chevron_right, size: 18),
                              onTap: _destroyRealKey,
                            ),
                          ],
                        ),
                      ],
                    ]),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildInfoSection(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark
              ? AppDesign.surfaceTile1.withValues(alpha: 0.5)
              : AppDesign.canvas,
          borderRadius: BorderRadius.circular(AppDesign.roundedLg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: AppDesign.appleOrange,
                ),
                const SizedBox(width: 8),
                Text(
                  '什么是PM码？',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppDesign.bodyOnDark : AppDesign.ink,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'PM码（Panic Mode Code）是一个特殊的胁迫密码。'
              '当您被胁迫输入密码时，可以输入PM码。'
              '此时应用会显示伪装的数据（假笔记），而您的真实数据被隐藏。\n\n'
              '• PM码与正常密码独立，无法相互推导\n'
              '• 输入PM码后显示的数据由系统自动生成\n'
              '• 销毁密钥后，真实数据将永久不可恢复',
              style: TextStyle(
                fontSize: 14,
                height: 1.47,
                color: isDark ? AppDesign.bodyMuted : AppDesign.inkMuted48,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 设置PM码流程。
  Future<void> _setupPmCode() async {
    // 第一步：输入当前正常密码
    final currentPassword = await _showPinInputDialog(
      title: '输入当前密码',
      content: '请输入您的正常登录密码以验证身份',
    );
    if (currentPassword == null) return;

    // 第二步：输入新的PM码
    final pmCode = await _showPinInputDialog(
      title: '输入PM码',
      content: '输入6位以上的胁迫密码（不能与正常密码相同）',
    );
    if (pmCode == null) return;

    // 第三步：确认PM码
    final confirmPmCode = await _showPinInputDialog(
      title: '确认PM码',
      content: '请再次输入PM码以确认',
    );
    if (confirmPmCode == null) return;

    if (pmCode != confirmPmCode) {
      if (mounted) {
        await _showErrorDialog('PM码不一致', '两次输入的PM码不一致，请重试。');
      }
      return;
    }

    // 执行设置
    final result = await ref.read(pmCodeServiceProvider).setupPmCode(
      currentPassword: currentPassword,
      pmCode: pmCode,
    );

    if (!mounted) return;

    switch (result) {
      case PmCodeSetupResult.success:
        await _showSuccessDialog('PM码设置成功',
            'PM码已设置。当被胁迫时，可以输入此密码显示伪装数据。');
        _loadState();
      case PmCodeSetupResult.sameAsPassword:
        await _showErrorDialog('PM码不能与正常密码相同',
            'PM码必须与您的正常登录密码不同。');
      case PmCodeSetupResult.tooShort:
        await _showErrorDialog('PM码太短', 'PM码至少需要6位。');
      case PmCodeSetupResult.invalidParameters:
        await _showErrorDialog('设置失败', '参数错误，请重试。');
    }
  }

  /// 修改PM码流程。
  Future<void> _changePmCode() async {
    // 验证旧PM码
    final oldPmCode = await _showPinInputDialog(
      title: '输入当前PM码',
      content: '请输入当前的胁迫密码以验证身份',
    );
    if (oldPmCode == null) return;

    final (verifyResult, _) =
        await ref.read(pmCodeServiceProvider).verifyPmCode(pmCode: oldPmCode);

    if (!mounted) return;

    if (verifyResult != PmCodeVerifyResult.success) {
      await _showErrorDialog('PM码验证失败', '输入的PM码不正确。');
      return;
    }

    // 输入新PM码
    final newPmCode = await _showPinInputDialog(
      title: '输入新PM码',
      content: '输入6位以上的新胁迫密码',
    );
    if (newPmCode == null) return;

    // 确认新PM码
    final confirmNewPmCode = await _showPinInputDialog(
      title: '确认新PM码',
      content: '请再次输入新PM码以确认',
    );
    if (confirmNewPmCode == null) return;

    if (newPmCode != confirmNewPmCode) {
      if (mounted) {
        await _showErrorDialog('PM码不一致', '两次输入的PM码不一致，请重试。');
      }
      return;
    }

    final result = await ref.read(pmCodeServiceProvider).changePmCode(
      oldPmCode: oldPmCode,
      newPmCode: newPmCode,
    );

    if (!mounted) return;

    if (result == PmCodeSetupResult.success) {
      await _showSuccessDialog('PM码修改成功', '新的PM码已设置。');
    } else {
      await _showErrorDialog('修改失败', 'PM码修改失败，请重试。');
    }
  }

  /// 关闭PM码流程。
  Future<void> _disablePmCode() async {
    final confirmed = await showIosDialog<bool>(
      context,
      title: '关闭PM码',
      content: '确定要关闭PM码功能吗？这将删除胁迫密码设置。',
      actions: const [
        IosDialogAction(label: '取消', result: false),
        IosDialogAction(
          label: '关闭',
          result: true,
          isDestructive: true,
        ),
      ],
    );
    if (confirmed != true) return;

    // 验证PM码
    final pmCode = await _showPinInputDialog(
      title: '输入PM码',
      content: '请输入当前的胁迫密码以确认关闭',
    );
    if (pmCode == null) return;

    final success =
        await ref.read(pmCodeServiceProvider).disablePmCode(pmCode: pmCode);

    if (!mounted) return;

    if (success) {
      await _showSuccessDialog('PM码已关闭', '胁迫密码功能已禁用。');
      _loadState();
    } else {
      await _showErrorDialog('关闭失败', 'PM码验证失败，请重试。');
    }
  }

  /// 销毁真实密钥流程。
  Future<void> _destroyRealKey() async {
    // 第一次确认
    final firstConfirm = await showIosDialog<bool>(
      context,
      title: '⚠️ 警告：不可逆操作',
      content: '销毁真实密钥后，您的真实数据将永久隐藏且不可恢复。\n\n'
          '此操作会：\n'
          '1. 用随机数据覆盖真实密钥\n'
          '2. 强制刷盘确保数据写入\n'
          '3. 清零内存中的密钥副本\n\n'
          '确定要继续吗？',
      actions: const [
        IosDialogAction(label: '取消', result: false),
        IosDialogAction(
          label: '继续',
          result: true,
          isDestructive: true,
        ),
      ],
    );
    if (firstConfirm != true) return;

    // 第二次确认
    final secondConfirm = await showIosDialog<bool>(
      context,
      title: '⚠️ 最终确认',
      content: '这是最后的确认。\n\n'
          '一旦销毁，即使您输入正确的正常密码，真实数据也将不可访问。\n\n'
          '我理解后果，继续销毁',
      actions: const [
        IosDialogAction(label: '取消', result: false),
        IosDialogAction(
          label: '确认销毁',
          result: true,
          isDestructive: true,
        ),
      ],
    );
    if (secondConfirm != true) return;

    // 验证PM码
    final pmCode = await _showPinInputDialog(
      title: '输入PM码',
      content: '输入PM码以确认销毁操作',
    );
    if (pmCode == null) return;

    // 执行销毁
    final destroyed =
        await ref.read(pmCodeServiceProvider).destroyRealKey(pmCode: pmCode);

    if (!mounted) return;

    if (destroyed) {
      await _showSuccessDialog(
        '密钥已销毁',
        '真实密钥已被永久销毁。\n\n'
            '后续输入正常密码将显示伪装数据。\n'
            '此操作不可逆。',
      );
      _loadState();
    } else {
      await _showErrorDialog('销毁失败', 'PM码验证失败或销毁操作失败，请重试。');
    }
  }

  /// 显示 PIN 输入对话框。
  Future<String?> _showPinInputDialog({
    required String title,
    required String content,
  }) {
    String? enteredPin;
    return showIosStatefulDialog<String>(
      context,
      title: title,
      width: 280,
      builder: (context, setState) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                content,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF6E6E73),
                ),
              ),
              const SizedBox(height: 16),
              ApplePinInput(
                length: 6,
                obscureText: true,
                onCompleted: (pin) {
                  enteredPin = pin;
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
      actions: [
        const IosDialogAction(label: '取消', result: '__cancel__'),
        IosDialogAction(
          label: '确认',
          result: '__confirm__',
          isDefault: true,
        ),
      ],
    ).then((result) {
      if (result == '__confirm__') return enteredPin;
      return null;
    });
  }

  /// 显示成功对话框。
  Future<void> _showSuccessDialog(String title, String message) {
    return showIosDialog(
      context,
      title: title,
      content: message,
      actions: const [
        IosDialogAction(label: '好', result: true, isDefault: true),
      ],
    );
  }

  /// 显示错误对话框。
  Future<void> _showErrorDialog(String title, String message) {
    return showIosDialog(
      context,
      title: title,
      content: message,
      actions: const [
        IosDialogAction(label: '好', result: true, isDefault: true),
      ],
    );
  }
}

// ─── UI 组件（复用 Apple HIG 模式） ──────────────────────────────────

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
                child: Icon(icon, size: 17, color: Colors.white),
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
                        color:
                            isDark ? AppDesign.bodyOnDark : AppDesign.ink,
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
                    color: isDark
                        ? AppDesign.bodyMuted
                        : AppDesign.inkMuted48,
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
