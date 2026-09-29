// 批次⑤：第四界面「设置」——密码体系与通用设置的集中管理入口。
//
// 单一事实来源：密码类设置（应用锁/单文件密码）与通用设置
// （外观/WebDAV）此前散落在 HomePage 的 AppBar 图标与「更多」菜单里，
// 本页收编为唯一入口（HomePage 原入口随批次⑤移除，功能只搬家不删除）。
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'package:drawing_notes_app/core/security/app_lock_service.dart';
import 'package:drawing_notes_app/core/security/audit_logger.dart';
import 'package:drawing_notes_app/core/security/quick_unlock_service.dart';
import 'package:drawing_notes_app/core/security/vault_key_service.dart';
import 'package:drawing_notes_app/core/storage/app_data_root.dart';
import 'package:drawing_notes_app/core/storage/backup_service.dart';
import 'package:drawing_notes_app/core/theme/app_locale_controller.dart';
import 'package:drawing_notes_app/core/theme/app_theme_controller.dart';
import 'package:drawing_notes_app/features/notes/presentation/app_lock_settings_page.dart';
import 'package:drawing_notes_app/features/notes/presentation/webdav_sync_settings_page.dart';
import '../../../core/theme/apple_design.dart';
import 'package:drawing_notes_app/shared/widgets/glass_app_bar.dart';
import 'package:drawing_notes_app/shared/application/diagnostics_exporter.dart';
import 'package:drawing_notes_app/shared/application/keyboard_shortcuts.dart';
import 'package:drawing_notes_app/shared/widgets/app_snack.dart';
import 'package:drawing_notes_app/l10n/app_localizations.dart';
import 'package:drawing_notes_app/shared/widgets/glass_dialog.dart';

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
    this.localeController,
    this.appDataRoot,
  });

  /// 应用锁服务（应用锁入口需要；null 时隐藏应用锁入口）。
  final AppLockService? appLockService;

  /// 主密钥保险库（U 盘恢复钥匙绑定需要；与开屏密码共用同一位密码）。
  final VaultKeyService? vaultKeyService;

  /// 系统验证快速解锁（批D1；null 时快速解锁开关不出现）。
  final QuickUnlockService? quickUnlockService;

  /// 外观控制器（外观入口需要；null 时隐藏外观入口）。
  final AppThemeController? themeController;

  /// 语言控制器（语言入口需要；null 时隐藏语言入口）。
  final AppLocaleController? localeController;

  /// 统一数据根（备份/恢复入口需要；null 时隐藏两行——测试装配兼容）。
  final AppDataRoot? appDataRoot;

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outline;
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      // 让内容延伸到顶栏之后——玻璃才有东西可模糊。
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(title: Text(l10n?.settingsTitle ?? '设置')),
      body: ListView(
        // 顶部让位必须用**可滚动**的 padding：内容滚到顶栏之后才会被玻璃
        // 模糊；若改用外层固定 Padding，内容永远进不到顶栏背后，
        // BackdropFilter 采不到东西，玻璃会退化成一块脏兮兮的半透明板。
        padding: EdgeInsets.fromLTRB(
          16,
          GlassAppBar.bodyTopPadding(context) + 12,
          16,
          // v1.10.5：底部让位（顶栏注释同一原则的镜像——可滚动 padding，
          // 内容能滚到玻璃导航条背后被模糊；外层固定 Padding 会让玻璃
          // 退化成脏板子）。app_shell extendBody 把条总高注入
          // MediaQuery.padding.bottom，此处消费并保留原 24 呼吸空间。
          MediaQuery.paddingOf(context).bottom + 24,
        ),
        children: [
          const _PasswordLayersCard(),
          const SizedBox(height: 16),
          _SectionHeader(
            title: l10n?.settingsSectionSecurity ?? '密码与安全',
            outline: outline,
          ),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                if (appLockService != null)
                  ListTile(
                    leading: const Icon(Icons.lock_outline_rounded),
                    title: Text(l10n?.settingsAppLock ?? '应用锁'),
                    subtitle: Text(l10n?.settingsAppLockHint ?? '开屏密码 · 重置密码盘'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _openAppLock(context),
                  ),
                ListTile(
                  leading: const Icon(Icons.enhanced_encryption_rounded),
                  title: Text(l10n?.settingsStandalonePassword ?? '单文件密码'),
                  subtitle: Text(
                    l10n?.settingsStandalonePasswordHint ??
                        '个别画布的第二道锁（在画布卡片设置）',
                  ),
                  trailing: const Icon(Icons.help_outline_rounded),
                  onTap: () => _showFilePasswordHelp(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionHeader(
            title: l10n?.settingsSectionGeneral ?? '通用',
            outline: outline,
          ),
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
                    title: Text(l10n?.settingsAppearance ?? '外观'),
                    subtitle: Text(_themeLabel(context, themeController!.mode)),
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
                    title: Text(l10n?.settingsHighContrast ?? '高对比度'),
                    subtitle: Text(themeController!.highContrastLabel),
                    trailing: const Icon(Icons.sync_alt_rounded),
                    onTap: () => themeController!.cycleHighContrast(),
                  ),
                if (localeController != null)
                  ListTile(
                    leading: const Icon(Icons.translate_rounded),
                    title: Text(l10n?.settingsLanguage ?? '语言'),
                    subtitle: Text(_localeLabel(context, localeController!)),
                    trailing: const Icon(Icons.sync_alt_rounded),
                    onTap: () => localeController!.cycle(),
                  ),
                ListTile(
                  leading: const Icon(Icons.cloud_sync_outlined),
                  title: Text(l10n?.settingsWebdav ?? 'WebDAV 同步'),
                  subtitle: Text(l10n?.settingsWebdavHint ?? '本地优先，跨设备同步'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const WebDavSyncSettingsPage(),
                    ),
                  ),
                ),
                if (appDataRoot != null) ...[
                  ListTile(
                    leading: const Icon(Icons.archive_outlined),
                    title: Text(l10n?.settingsBackup ?? '备份全部数据'),
                    subtitle:
                        Text(l10n?.settingsBackupHint ?? '打包全部笔记与设置（含密钥文件，请妥善保管）'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _createBackup(context),
                  ),
                  ListTile(
                    leading: const Icon(Icons.restore_rounded),
                    title: Text(l10n?.settingsRestore ?? '从备份恢复'),
                    subtitle:
                        Text(l10n?.settingsRestoreHint ?? '覆盖当前数据，重启应用后生效'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _startRestore(context),
                  ),
                ],
                ListTile(
                  leading: const Icon(Icons.bug_report_outlined),
                  title: Text(l10n?.settingsDiagnostics ?? '导出诊断信息'),
                  subtitle:
                      Text(l10n?.settingsDiagnosticsHint ?? '脱敏日志，帮助排查问题'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _exportDiagnostics(context),
                ),
                ListTile(
                  leading: const Icon(Icons.keyboard_rounded),
                  title: Text(l10n?.settingsShortcuts ?? '键盘快捷键'),
                  subtitle: Text(l10n?.settingsShortcutsHint ?? '按键与作用速查'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _showShortcuts(context),
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
    GlassDialog.show<void>(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        return AlertDialog(
          title: Text(l10n?.settingsStandalonePassword ?? '单文件密码'),
          content: Text(
            l10n?.settingsFilePasswordHelpContent ??
                '在首页或全部文档页，点击画布卡片上的锁形按钮，可为单个画布'
                    '设置独立密码。设置后打开该画布需要输入此密码，缩略图也会'
                    '隐藏为锁形占位。\n\n'
                    '单文件密码独立于开屏密码——即使有人解锁了你的应用，没有'
                    '这个密码也打不开对应的画布。',
          ),
          actions: [
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n?.gotIt ?? '知道了'),
            ),
          ],
        );
      },
    );
  }

  String _themeLabel(BuildContext context, ThemeMode mode) => switch (mode) {
    ThemeMode.system =>
      AppLocalizations.of(context)?.settingsThemeSystem ?? '跟随系统（点击切换为浅色）',
    ThemeMode.light =>
      AppLocalizations.of(context)?.settingsThemeLight ?? '浅色（点击切换为深色）',
    ThemeMode.dark =>
      AppLocalizations.of(context)?.settingsThemeDark ?? '深色（点击切换为跟随系统）',
  };

  String _localeLabel(BuildContext context, AppLocaleController controller) =>
      switch (controller.locale) {
        null => AppLocalizations.of(context)?.settingsLanguageSystem ??
            '跟随系统（点击切换为中文）',
        const Locale('zh') =>
          AppLocalizations.of(context)?.settingsLanguageZh ?? '中文（点击切换为 English）',
        _ => AppLocalizations.of(context)?.settingsLanguageEn ??
            'English（点击切换为跟随系统）',
      };

  /// 导出诊断信息（2026-09-27）：用户选位置保存脱敏报告——环境摘要 +
  /// AuditLogger 哈希链校验结果 + 近期条目（类型级别，无路径/正文）。
  Future<void> _exportDiagnostics(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    try {
      final report = DiagnosticsExporter.buildReport(
        platformInfo:
            '${Platform.operatingSystem} ${Platform.operatingSystemVersion} · '
            'Dart ${Platform.version.split(' ').first}',
        localeName: l10n?.localeName ?? 'zh',
        auditIntegrity: AuditLogger.verifyIntegrity(),
        auditEntries: AuditLogger.snapshot(),
      );
      final now = DateTime.now();
      final stamp =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}'
          '_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
      final location = await getSaveLocation(
        suggestedName: 'drawing_notes_diagnostics_$stamp.txt',
        acceptedTypeGroups: [
          XTypeGroup(label: l10n?.fileTypeText ?? '文本文档', extensions: const ['txt']),
        ],
      );
      if (location == null) return; // 用户取消
      await File(location.path).writeAsString(report, flush: true);
      if (!context.mounted) return;
      AppSnack.show(
        context,
        l10n?.settingsDiagnosticsExported ?? '诊断信息已导出',
      );
    } catch (e) {
      AuditLogger.log(
        'settings.diagnostics.export_failed',
        success: false,
        detail: e.runtimeType.toString(),
      );
      if (!context.mounted) return;
      AppSnack.show(
        context,
        l10n?.settingsDiagnosticsExportFail ?? '导出失败，请重试',
      );
    }
  }

  /// 备份全部数据（批次 M）：数据根整体打包为 zip（含 manifest 与密钥
  /// 文件），用户选位置保存。打包在 isolate 内执行，大目录不卡 UI。
  Future<void> _createBackup(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    try {
      final dataRoot = await appDataRoot!.root();
      final now = DateTime.now();
      final stamp =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}'
          '_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
      final location = await getSaveLocation(
        suggestedName: 'drawing_notes_backup_$stamp.zip',
        acceptedTypeGroups: [
          XTypeGroup(
            label: l10n?.fileTypeBackup ?? '绘图笔记备份',
            extensions: const ['zip'],
          ),
        ],
      );
      if (location == null) return; // 用户取消
      await BackupService.createBackup(
        dataRoot: dataRoot,
        destinationPath: location.path,
      );
      if (!context.mounted) return;
      AppSnack.show(context, l10n?.backupExported ?? '备份已导出');
    } catch (e) {
      AuditLogger.log(
        'settings.backup.export_failed',
        success: false,
        detail: e.runtimeType.toString(),
      );
      if (!context.mounted) return;
      AppSnack.show(context, l10n?.backupFailed ?? '备份失败，请重试');
    }
  }

  /// 从备份恢复（批次 M）：选包 → 校验并解压到暂存 → 强确认 → 退出应用；
  /// 下次启动 main() 早期 applyPendingRestore 原子换目录后自动生效。
  Future<void> _startRestore(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    try {
      final docsDir = await appDataRoot!.documentsDirectory();
      final selected = await openFile(
        acceptedTypeGroups: [
          XTypeGroup(
            label: l10n?.fileTypeBackup ?? '绘图笔记备份',
            extensions: const ['zip'],
          ),
        ],
      );
      if (selected == null) return; // 用户取消
      await BackupService.stageRestore(
        backupPath: selected.path,
        documentsDir: docsDir,
      );
      if (!context.mounted) return;
      final proceed = await GlassDialog.confirm(
        context,
        title: l10n?.restoreConfirmTitle ?? '从备份恢复',
        content:
            l10n?.restoreConfirmBody ??
                '恢复将覆盖当前全部数据（含保险库密钥）。数据已就绪，'
                    '确认后应用将退出，重新打开时生效。',
        confirmText: l10n?.restoreConfirmAction ?? '确认恢复',
        dangerous: true,
      );
      if (proceed != true) {
        // 用户取消：清掉刚写的标记与暂存，保持现网原状。
        try {
          final marker = File(
            '${docsDir.path}${Platform.pathSeparator}'
                '${AppDataRoot.pendingRestoreMarkerName}',
          );
          if (marker.existsSync()) {
            final stagingPath = (await marker.readAsString()).trim();
            await marker.delete();
            final staging = Directory(stagingPath);
            if (stagingPath.isNotEmpty && staging.existsSync()) {
              await staging.delete(recursive: true);
            }
          }
        } catch (_) {
          // 清理失败不阻塞——残留暂存会在下次成功恢复或重启时被处理。
        }
        return;
      }
      // 用户确认：退出应用；下次启动 applyPendingRestore 完成交换。
      exit(0);
    } on FormatException {
      if (!context.mounted) return;
      AppSnack.show(context, l10n?.restoreInvalid ?? '无效的备份文件');
    } catch (e) {
      AuditLogger.log(
        'settings.backup.restore_failed',
        success: false,
        detail: e.runtimeType.toString(),
      );
      if (!context.mounted) return;
      AppSnack.show(context, l10n?.restoreFailed ?? '恢复失败，请重试');
    }
  }

  /// 快捷键速查（批次 N）：目录数据全部来自代码注册点核对
  /// （KeyboardShortcuts.catalog），滚动列表按交互域分组。
  void _showShortcuts(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final groups = KeyboardShortcuts.catalog(l10n);
    GlassDialog.show<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(l10n?.settingsShortcuts ?? '键盘快捷键'),
          content: SizedBox(
            width: 420,
            height: 480,
            child: ListView.builder(
              itemCount: groups.length,
              itemBuilder: (context, gi) {
                final group = groups[gi];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                      child: Text(
                        group.title,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                    for (final entry in group.entries)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 168,
                              child: Text(
                                entry.keys,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                entry.label,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          actions: [
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n?.gotIt ?? '知道了'),
            ),
          ],
        );
      },
    );
  }
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
    final l10n = AppLocalizations.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: AppleColor.panelOf(scheme),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.layers_rounded, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  l10n?.settingsPasswordSystem ?? '密码体系',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _layer(
              context,
              icon: Icons.smartphone_rounded,
              title: l10n?.settingsLayer1Title ?? '第 1 层 · 开屏密码',
              desc:
                  l10n?.settingsLayer1Desc ??
                  '解锁应用，同时解开主密钥保险库——保护全部画布与笔记。'
                      '忘记时可用重置密码盘重设。',
            ),
            _divider(scheme),
            _layer(
              context,
              icon: Icons.enhanced_encryption_rounded,
              title: l10n?.settingsLayer2Title ?? '第 2 层 · 文件密码',
              desc:
                  l10n?.settingsLayer2Desc ??
                  '给单个画布/分页画布/笔记另设的独立密码，独立于开屏密码。'
                      '忘记时可用重置密码盘重设。',
            ),
            _divider(scheme),
            _layer(
              context,
              icon: Icons.usb_rounded,
              title: l10n?.settingsLayer3Title ?? '重置密码盘（U 盘）',
              desc:
                  l10n?.settingsLayer3Desc ??
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
        const SizedBox(width: 8),
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
        padding: const EdgeInsets.fromLTRB(4, 0, 0, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(color: outline),
      ),
    );
  }
}
