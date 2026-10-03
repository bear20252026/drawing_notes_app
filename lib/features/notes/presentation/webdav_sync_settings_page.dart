// 由 Claude 团队生成 | Drawing Notes App
// WebDAV 本地优先同步：设置页（服务器/认证 + 立即同步 + 端到端加密）。

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:drawing_notes_app/l10n/app_localizations.dart';
import 'package:drawing_notes_app/core/security/audit_logger.dart';
import 'package:drawing_notes_app/core/theme/apple_design.dart';
import 'package:drawing_notes_app/core/sync/sync_conflict.dart';
import 'package:drawing_notes_app/core/sync/sync_progress.dart';
import 'package:drawing_notes_app/features/notes/application/sync_controller.dart';
import 'package:drawing_notes_app/features/notes/presentation/conflict_resolution_dialog.dart';
import 'package:drawing_notes_app/shared/widgets/glass_dialog.dart';
import 'package:drawing_notes_app/shared/widgets/glass_app_bar.dart';

/// R1：把同步异常映射为人话文案——用户界面只出现可读懂的提示，
/// 原始异常对象进调试日志（debugPrint），不再直接拼进 UI 字符串。
String humanizeWebDavSyncError(Object? e, {AppLocalizations? l10n}) {
  if (e == null) return l10n?.syncFailedUnknown ?? '同步失败：未知错误';
  if (e is String) return l10n?.webdavSyncFailRaw(e) ?? '同步失败：$e';
  // P1 修复（审计 H-04）：原始异常可能含 URL/用户名/口令片段——仅记类型，
  // 不记原文（logcat 可被其他应用读取）。
  AuditLogger.log(
    'webdav.sync.error',
    success: false,
    detail: e.runtimeType.toString(),
  );
  if (e is WebDavSyncException) {
    // F-20 修复（审计 2026-09-07）：「远端路径」分支的 message 内嵌
    // relativePath——docId 来自未认证远端 manifest，可被操控（注入换行/
    // 钓鱼文案）。不再拼进用户可见文案，改静态提示；原文只进审计日志
    // detail（该分支为固定前缀 + 路径段，无口令/凭据片段，符合 H-04 去敏口径）。
    if (e.message.contains('远端路径')) {
      AuditLogger.log(
        'webdav.sync.unsafe_path',
        success: false,
        detail: e.message,
      );
      return l10n?.syncFailedRemoteFile ?? '同步失败：同步远端文件失败，请检查服务器';
    }
    // 本地安全门禁（https）文案是本地静态文本，可直接透出。
    if (e.message.contains('https')) {
      return l10n?.webdavSyncFailRaw(e.message) ?? '同步失败：${e.message}';
    }
    final code = e.statusCode;
    if (code == 401 || code == 403) {
      return l10n?.syncFailedAuth ?? '同步失败：用户名或密码不对（服务器拒绝登录）';
    }
    if (code != null && code >= 500) {
      return l10n?.syncFailedHttpUnavailable(code) ??
          '同步失败：服务器暂时不可用（HTTP $code），请稍后再试';
    }
    if (code == 404 || code == 409) {
      return l10n?.syncFailedDirMissing ?? '同步失败：服务器目录不存在或路径被占用，请检查远端目录设置';
    }
    return l10n?.syncFailedRejected(
          code == null ? (l10n.syncHttpUnknown) : '$code',
        ) ??
        '同步失败：服务器拒绝了这次请求（HTTP ${code ?? '未知'}）';
  }
  if (e is HandshakeException) {
    return l10n?.syncFailedHttps ?? '同步失败：安全连接（HTTPS）握手失败，请检查服务器证书';
  }
  if (e is SocketException || e is TimeoutException) {
    return l10n?.syncFailedConnect ?? '同步失败：连不上服务器，请检查网络或服务器地址';
  }
  return l10n?.syncFailedGeneric ?? '同步失败：请检查网络与账号设置后重试';
}

/// WebDAV 同步设置页。
///
/// C-05（审计 2026-09-27）：同步装配收口到 [SyncController]（application 层，
/// 组合根 AppServices → AppShell → SettingsPage 注入，生产路径恒有）——
/// 本页不再 new 基础设施 store、不再自选加密方案、不再直接构建 SyncService。
class WebDavSyncSettingsPage extends StatefulWidget {
  const WebDavSyncSettingsPage({super.key, required this.syncController});

  final SyncController syncController;

  @override
  State<WebDavSyncSettingsPage> createState() => _WebDavSyncSettingsPageState();
}

class _WebDavSyncSettingsPageState extends State<WebDavSyncSettingsPage> {
  SyncController get _sync => widget.syncController;
  final _url = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _syncSecret = TextEditingController();
  bool _syncing = false;
  SyncProgress? _progress;
  String? _lastSummary;

  /// S-03（审计 2026-09-27）方案 A：口令**不回填**控制器，只记存在性
  /// 用于占位提示。明文一旦写进 `TextEditingController` 就绕过了
  /// `SessionSecrets.clearAll()`（切后台清的是各 store 的会话缓存，清不到
  /// 仍在内存里的 widget 树），堆转储可直接读出。此处仅存 bool。
  bool _hasSavedPassword = false;
  bool _hasSavedPassphrase = false;

  /// 空操作回调（用于禁用态按钮）。
  static void _noop() {}

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final cfg = await _sync.loadConfig();
    final secrets = await _sync.readSecrets();
    if (!mounted) return;
    setState(() {
      _url.text = cfg.baseUrl;
      _user.text = cfg.username;
      // S-03 方案 A：口令留空，仅记存在性（占位提示由 hintText 呈现）。
      // 空值在保存/同步两侧一律解释为「沿用已存」，见 _save / _syncNow。
      _hasSavedPassword = secrets.webdavPassword?.isNotEmpty ?? false;
      _hasSavedPassphrase = secrets.syncPassphrase?.isNotEmpty ?? false;
    });
  }

  Future<void> _save() async {
    // C-05：装配与「空值沿用」语义收口到 SyncController——本页只提交表单
    // 原文，不再触碰配置/机密存储；https 门禁 ArgumentError 在此明示。
    final ({String password, String passphrase}) effective;
    try {
      effective = await _sync.save(
        baseUrl: _url.text,
        username: _user.text,
        password: _pass.text,
        passphrase: _syncSecret.text,
      );
    } on ArgumentError catch (e) {
      if (!mounted) return;
      _toast(AppLocalizations.of(context)?.webdavSaveFail(e.message) ?? '保存失败：${e.message}');
      return;
    }
    if (!mounted) return;
    // 保存后刷新存在性标记：用户若把口令敲了进去，占位提示即刻让位。
    setState(() {
      _hasSavedPassword = effective.password.isNotEmpty;
      _hasSavedPassphrase = effective.passphrase.isNotEmpty;
    });
    _toast(
      effective.passphrase.isEmpty
          ? (AppLocalizations.of(context)?.webdavSavedPlain ?? '已保存 WebDAV 配置（未启用端到端加密）')
          : (AppLocalizations.of(context)?.webdavSavedEncrypted ?? '已保存 WebDAV 配置（已启用端到端加密）'),
    );
  }

  Future<void> _syncNow() async {
    final rawUrl = _url.text.trim();
    if (rawUrl.isEmpty) {
      _toast(AppLocalizations.of(context)?.webdavBadUrl ?? '请先填写合法的服务器 URL（含 http/https 与 /）');
      return;
    }
    // F-21 修复（审计 2026-09-07）：原预检仅 `uri.hasScheme`——明文 http
    // URL 能过预检，直到 WebDavSyncClient 传输层门禁才失败。复用保存路径
    // 同一 requireHttpsBaseUrl 预检（https；本地回环 http 例外）。
    try {
      SyncController.requireHttpsBaseUrl(rawUrl);
    } on ArgumentError catch (e) {
      _toast(AppLocalizations.of(context)?.webdavSyncFailRaw(e.message) ?? '同步失败：${e.message}');
      return;
    }
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) {
      _toast(AppLocalizations.of(context)?.webdavBadUrl ?? '请先填写合法的服务器 URL（含 http/https 与 /）');
      return;
    }
    // 安全审计修复（2026-09-06 P1-2）：未配置同步密码 = 同步层明文透传，
    // 笔记正文会以明文落在 WebDAV 服务器（UI 曾误称「云端仅保存加密数据」）。
    // fail-closed：拒绝同步，要求先设置同步密码。
    // S-03 方案 A：口令不回填 → 生效值 = 表单非空 ? 表单 : 已存。
    final cfg = await _sync.loadConfig();
    final secrets = await _sync.readSecrets();
    final passphrase =
        _syncSecret.text.trim().isNotEmpty
            ? _syncSecret.text.trim()
            : (secrets.syncPassphrase ?? '');
    final password =
        _pass.text.isNotEmpty ? _pass.text : (secrets.webdavPassword ?? '');
    if (passphrase.isEmpty) {
      // mounted 守卫：本分支前已 await 两次（cfg/secrets），与下方两处同款。
      _toast(
        (mounted ? AppLocalizations.of(context) : null)?.webdavNeedSyncPassword ??
            '未设置同步密码：为避免笔记明文上云，已阻止同步。请在下方设置同步密码后重试。',
      );
      return;
    }
    // F-21 修复（审计 2026-09-07）：cipher 用「已保存盐 + 表单口令」构造——
    // 表单有未保存修改时密钥会与云端数据错配（首次设置未保存时盐缺失，
    // _buildCipher 甚至退化为 Noop 明文透传）。检测到表单与已保存配置/
    // 机密不一致时，先提示保存再同步。
    // S-03 方案 A：空值表示「未改」，故只有**非空且与已存不等**才算脏。
    final formDirty =
        _url.text.trim() != cfg.baseUrl ||
        _user.text.trim() != cfg.username ||
        (_pass.text.isNotEmpty && _pass.text != secrets.webdavPassword) ||
        (_syncSecret.text.trim().isNotEmpty &&
            _syncSecret.text.trim() != secrets.syncPassphrase);
    if (formDirty) {
      _toast(
        (mounted ? AppLocalizations.of(context) : null)?.webdavFormDirty ??
            '表单有未保存的修改：请先点击「保存配置」再同步（避免加密密钥与云端数据错配）',
      );
      return;
    }
    if (cfg.syncSalt == null || cfg.syncSalt!.isEmpty) {
      _toast(
        (mounted ? AppLocalizations.of(context) : null)?.syncMissingSalt ??
            '同步配置缺少加密盐：请重新点击「保存配置」后再同步',
      );
      return;
    }
    setState(() {
      _syncing = true;
      _progress = SyncProgress.starting();
      _lastSummary = null;
    });
    try {
      // C-05：cipher/SyncService/transport 装配 + 有界重试 + close 全部
      // 收口到 SyncController；本页只注入冲突裁决（弹窗）与进度回调。
      final outcome = await _sync.syncNow(
        baseUrl: uri,
        username: _user.text.trim(),
        // S-03 方案 A：口令不回填 → 用生效值（表单非空 ? 表单 : 已存），
        // 否则留空提交会拿空串去认证。
        password: password,
        passphrase: passphrase,
        syncSalt: cfg.syncSalt,
        conflictHandler: _DialogConflictHandler(this),
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      if (outcome.result != null) {
        final summary = _summaryOf(outcome.result!);
        setState(() {
          _progress = SyncProgress.complete();
          _lastSummary = summary;
        });
        _toast(summary);
      } else {
        final summary = humanizeWebDavSyncError(
          outcome.error,
          l10n: mounted ? AppLocalizations.of(context) : null,
        );
        setState(() {
          _progress = SyncProgress.failure(summary);
          _lastSummary = summary;
        });
        _toast(summary);
      }
    } catch (e) {
      if (!mounted) return;
      final summary = humanizeWebDavSyncError(
        e,
        l10n: mounted ? AppLocalizations.of(context) : null,
      );
      setState(() {
        _progress = SyncProgress.failure(summary);
        _lastSummary = summary;
      });
      _toast(summary);
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  String _summaryOf(SyncResult r) {
    final l10n = mounted ? AppLocalizations.of(context) : null;
    final base = r.changed
        ? l10n?.syncDoneSummary(r.uploaded, r.downloaded, r.deletedRemote) ??
              '同步完成：↑${r.uploaded} ↓${r.downloaded} ✕${r.deletedRemote}'
        : l10n?.syncUpToDate ?? '已是最新，无需同步';
    if (r.conflictedDocIds.isNotEmpty) {
      return l10n?.syncWithConflicts(base, r.conflictedDocIds.length) ??
          '$base；另有 ${r.conflictedDocIds.length} 个文档本地与云端均有改动，已按你的选择处理';
    }
    return base;
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    _pass.dispose();
    _syncSecret.dispose();
    super.dispose();
  }

  /// Apple 胶囊输入框样式：可见面用 subtleSurface 填色 + hairline 描边。
  InputDecoration _appleDecoration({
    required String labelText,
    required IconData icon,
    String? hintText,
    String? helperText,
  }) {
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      helperText: helperText,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppleSpacing.md,
        vertical: 14,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppleRadius.lg),
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppleRadius.lg),
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppleRadius.lg),
        // 键盘焦点环：Focus Blue + 2px 实线（DESIGN.md:300、440）。
        borderSide: const BorderSide(color: AppleColor.focusBlue, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: Text(AppLocalizations.of(context)?.webdavTitle ?? 'WebDAV 同步'),
      ),
      body: ListView(
        // 可滚动 padding——见 settings_page 同名注释。
        padding: EdgeInsets.fromLTRB(
          16,
          GlassAppBar.bodyTopPadding(context) + 16,
          16,
          16,
        ),
        children: [
          Text(
            AppLocalizations.of(context)?.webdavLocalFirstBlurb ?? '本地优先同步：数据保存在本机，通过 WebDAV（如 Nextcloud / 自建）在工作区之间同步。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppleSpacing.md),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            decoration: _appleDecoration(
              labelText: AppLocalizations.of(context)?.webdavServerUrlLabel ?? '服务器 URL',
              hintText: 'https://dav.example.com/drawing_notes/',
              icon: Icons.cloud_outlined,
            ),
          ),
          const SizedBox(height: AppleSpacing.sm),
          TextField(
            controller: _user,
            decoration: _appleDecoration(
              labelText: AppLocalizations.of(context)?.webdavUsername ?? '用户名',
              icon: Icons.person_outline,
            ),
          ),
          const SizedBox(height: AppleSpacing.sm),
          TextField(
            controller: _pass,
            obscureText: true,
            decoration: _appleDecoration(
              labelText: AppLocalizations.of(context)?.commonPassword ?? '密码',
              icon: Icons.lock_outline,
              // S-03 方案 A：不回填明文，用占位提示告知「已存且留空沿用」。
              hintText:
                  _hasSavedPassword
                      ? (AppLocalizations.of(
                            context,
                          )?.webdavSecretKeepHint ?? '已保存 · 留空保持不变')
                      : null,
            ),
          ),
          const SizedBox(height: AppleSpacing.sm),
          TextField(
            controller: _syncSecret,
            obscureText: true,
            decoration: _appleDecoration(
              labelText:
                  AppLocalizations.of(context)?.webdavSyncSecretLabel ??
                  '同步密码（必填，用于端到端加密）',
              icon: Icons.vpn_key_outlined,
              hintText:
                  _hasSavedPassphrase
                      ? (AppLocalizations.of(
                            context,
                          )?.webdavSecretKeepHint ?? '已保存 · 留空保持不变')
                      : null,
              helperText:
                  AppLocalizations.of(context)?.webdavSyncSecretHelper ??
                  '未设置同步密码时同步会被阻止（防止笔记明文上云）',
            ),
          ),
          const SizedBox(height: AppleSpacing.lg),
          _syncing
              ? ApplePrimaryButton(
                  label: AppLocalizations.of(context)?.webdavSyncing ?? '同步中…',
                  onPressed: _noop,
                )
              : ApplePrimaryButton(
                  label: AppLocalizations.of(context)?.webdavSyncNow ?? '立即同步',
                  onPressed: _syncNow,
                ),
          if (_progress != null) ...[
            const SizedBox(height: AppleSpacing.md),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppleRadius.full),
              child: LinearProgressIndicator(
                value: _progress!.fraction,
                minHeight: 6,
                color: _progress!.phase == SyncProgressPhase.failed
                    ? AppleColor.errorRed
                    : AppleColor.actionBlue,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _progress!.description,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _progress!.phase == SyncProgressPhase.failed
                    ? AppleColor.errorRed
                    : null,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (_lastSummary != null) ...[
            const SizedBox(height: 4),
            Text(
              _lastSummary!,
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: AppleSpacing.sm),
          OutlinedButton.icon(
            onPressed: _syncing ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: Text(AppLocalizations.of(context)?.webdavSave ?? '保存配置'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 44),
              foregroundColor: AppleColor.actionBlue,
              side: const BorderSide(color: AppleColor.hairline),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppleRadius.lg),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 冲突处理器：遇到冲突时弹窗询问用户逐条裁决；用户取消则返回空（走默认 LWW）。
class _DialogConflictHandler implements ConflictHandler {
  _DialogConflictHandler(this._state);

  final State<WebDavSyncSettingsPage> _state;

  @override
  Future<Map<String, ConflictResolution>> resolve(
    List<SyncConflict> conflicts,
  ) async {
    if (conflicts.isEmpty || !_state.mounted) return const {};
    final result = await GlassDialog.show<Map<String, ConflictResolution>>(
      context: _state.context,
      barrierDismissible: false,
      builder: (_) => ConflictResolutionDialog(conflicts: conflicts),
    );
    return result ?? const {};
  }
}
