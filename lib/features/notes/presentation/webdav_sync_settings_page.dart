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

/// P2 脱敏（审计 2026-10）：审计日志的 detail 也可能带远端可控文本
/// （reasonPhrase / 远端路径），落盘前先剥掉凭据形态（Basic token、URL
/// userinfo）、折行（防伪造审计行）并截断——审计链虽只在内存，仍按
/// H-04「绝不落凭据」口径处理。
final RegExp _basicTokenRe = RegExp(r'Basic\s+[A-Za-z0-9+/=]+');
final RegExp _urlUserInfoRe = RegExp(
  r'([A-Za-z][A-Za-z0-9+.-]*://)[^\s/@:]+:[^\s/@]*@',
);
final RegExp _whitespaceRe = RegExp(r'\s+');
const int _logDetailMaxLen = 160;

/// 同步进度的展示文案（审计 P1-2）。
///
/// core 层的 `SyncProgress` 只给「阶段 + 计数」，文案在这里按 arb 键取——
/// 此前界面直接渲染 `SyncProgress.description`，而那是 core 里写死的一整块
/// 中文（纯 Dart 层拿不到 `AppLocalizations`），于是 **en 用户整条同步进度
/// 全程中文**（「正在上传 3/7」「同步完成」一路陪到结束）。
///
/// 缺 l10n 时回落到 core 的中文兜底串——与本仓所有 `l10n?.x ?? '中文兜底'`
/// 站点同一口径，同时也让 `SyncProgress.description` 保有生产消费方
/// （它正是无本地化环境下的兜底），不留孤儿 API。
///
/// switch 覆盖整个枚举：**以后新增阶段必须在这里补文案**（否则编译不过），
/// 避免新阶段悄悄退回中文兜底而没人发现。
String syncProgressLabel(SyncProgress p, AppLocalizations? l10n) {
  final hasTotal = p.totalCount > 0;
  switch (p.phase) {
    case SyncProgressPhase.started:
      return l10n?.syncPhaseStarted ?? p.description;
    case SyncProgressPhase.connecting:
      return l10n?.syncPhaseConnecting ?? p.description;
    case SyncProgressPhase.planning:
      return l10n?.syncPhasePlanning ?? p.description;
    case SyncProgressPhase.uploading:
      return hasTotal
          ? (l10n?.syncPhaseUploadingCount(p.doneCount, p.totalCount) ??
                p.description)
          : (l10n?.syncPhaseUploading ?? p.description);
    case SyncProgressPhase.downloading:
      return hasTotal
          ? (l10n?.syncPhaseDownloadingCount(p.doneCount, p.totalCount) ??
                p.description)
          : (l10n?.syncPhaseDownloading ?? p.description);
    case SyncProgressPhase.deleting:
      return hasTotal
          ? (l10n?.syncPhaseDeletingCount(p.doneCount, p.totalCount) ??
                p.description)
          : (l10n?.syncPhaseDeleting ?? p.description);
    case SyncProgressPhase.writingManifest:
      return l10n?.syncPhaseWritingManifest ?? p.description;
    case SyncProgressPhase.done:
      return l10n?.syncPhaseDone ?? p.description;
    case SyncProgressPhase.failed:
      // 失败原因由 humanizeWebDavSyncError 生成，本身已按当前语言取 arb 文案
      // （且过脱敏纪律），所以有 message 时优先用它——与修复前行为一致。
      final detail = p.message;
      if (detail != null && detail.isNotEmpty) return detail;
      return l10n?.syncPhaseFailed ?? p.description;
  }
}

String _redactForLog(String raw) {
  final scrubbed = raw
      .replaceAll(_basicTokenRe, 'Basic [redacted]')
      .replaceAllMapped(_urlUserInfoRe, (m) => '${m[1]}[redacted]@')
      .replaceAll(_whitespaceRe, ' ');
  return scrubbed.length <= _logDetailMaxLen
      ? scrubbed
      : '${scrubbed.substring(0, _logDetailMaxLen)}…';
}

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
  // 修复 1②：口令轮换导致的「旧云端密文解不开」是确定性失败——文案必须
  // 可执行（填回旧口令 / 决定全量重传），不得落到下面那句「检查网络与账号」。
  // 走静态文案：该异常 message 本地固定构造，不含口令、密钥或远端原文。
  if (e is SyncKeyMismatchException) {
    AuditLogger.log('webdav.sync.key_mismatch', success: false);
    return l10n?.syncKeyRotatedUnreadable ??
        '同步失败：云端数据是用改动前的同步口令加密的，当前口令解不开（重试无用）。要继续用云端数据，请在「同步密码」里填回原来的口令并保存；确定放弃旧的云端数据，就换一个新口令保存后重新全量上传——旧的云端对象不会被自动清理，需要你在服务器上手动删除';
  }
  if (e is WebDavSyncException) {
    // 原文（脱敏 + 截断后）进审计日志供本机排查；UI 一律走下面的静态文案。
    AuditLogger.log(
      'webdav.sync.detail',
      success: false,
      detail: _redactForLog('HTTP ${e.statusCode ?? '-'} ${e.message}'),
    );
    // F-20 修复（审计 2026-09-07）：「远端路径」分支的 message 内嵌
    // relativePath——docId 来自未认证远端 manifest，可被操控（注入换行/
    // 钓鱼文案）。不再拼进用户可见文案，改静态提示；原文只进审计日志
    // detail（该分支为固定前缀 + 路径段，无口令/凭据片段，符合 H-04 去敏口径）。
    if (e.message.contains('远端路径')) {
      AuditLogger.log(
        'webdav.sync.unsafe_path',
        success: false,
        detail: _redactForLog(e.message),
      );
      return l10n?.syncFailedRemoteFile ?? '同步失败：同步远端文件失败，请检查服务器';
    }
    // P2 修复（审计 2026-10）：此前用 `message.contains('https')` 猜「本地
    // 门禁文案」——远端 reasonPhrase 里带一个 https 字样就能把任意字符串送进
    // snackbar，且该分支排在 401/5xx/404 分类之前会把认证失败降级成裸文本。
    // 改为全等白名单：只有本地静态构造的门禁 message 才允许透出。
    if (WebDavSyncException.isLocalGateMessage(e.message)) {
      if (e.message == WebDavSyncException.redirectGateMessage) {
        AuditLogger.log(
          'webdav.sync.redirect_blocked',
          success: false,
          detail: 'HTTP ${e.statusCode ?? '-'}',
        );
      }
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
    //
    // 修复 1①：换同步口令就换整把主密钥（盐沿用旧值，remotePath=HMAC(key,id)
    // 与固定名 manifest 全部错位）⇒ 旧的云端加密数据从此解不开。判定必须在
    // 保存**之前**（零网络预检），用户二次确认后才带 confirmKeyRotation 落盘；
    // 不确认则一个字节都不改，已存口令原样保留。
    bool confirmKeyRotation = false;
    if (_syncSecret.text.trim().isNotEmpty) {
      if (await _sync.willRotateSyncKey(passphrase: _syncSecret.text)) {
        if (!mounted) return;
        final l10n = AppLocalizations.of(context);
        final confirmed = await GlassDialog.confirm(
          context,
          title: l10n?.webdavKeyRotationConfirmTitle ?? '确认更换同步口令？',
          content: l10n?.webdavKeyRotationConfirmBody ??
              '同步口令一改，端到端加密的密钥就会整体更换：云端已有的加密数据将「无法再解密」，之后需要把本地笔记全量重新上传；本地数据不受影响。若只是想接着同步，请留空（沿用原口令）或填回原来的口令。',
          confirmText:
              l10n?.webdavKeyRotationConfirmAction ?? '仍要更换并重新上传',
          dangerous: true,
        );
        if (!confirmed) {
          if (!mounted) return;
          _toast(
            AppLocalizations.of(context)?.webdavKeyRotationCancelled ??
                '已取消更换：同步口令保持原值，云端数据仍可读',
          );
          return;
        }
        confirmKeyRotation = true;
      }
    }
    final ({String password, String passphrase}) effective;
    try {
      effective = await _sync.save(
        baseUrl: _url.text,
        username: _user.text,
        password: _pass.text,
        passphrase: _syncSecret.text,
        confirmKeyRotation: confirmKeyRotation,
      );
    } on ArgumentError catch (e) {
      if (!mounted) return;
      _toast(AppLocalizations.of(context)?.webdavSaveFail(e.message) ?? '保存失败：${e.message}');
      return;
    } on SyncKeyRotationConfirmationRequired {
      // 预检到落盘之间口令状态变了：控制器 fail-closed（未上盘），这里同样
      // 只给静态文案，不把异常原文送进 UI。
      if (!mounted) return;
      _toast(
        AppLocalizations.of(context)?.webdavKeyRotationConfirmTitle ??
            '确认更换同步口令？',
      );
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
    // mounted 守卫（P2 修复）：上面 await 了两次，页面可能已被 pop。下面的
    // 三个提示分支（未设密码 / 表单脏 / 缺盐）与 setState 都要碰 UI，统一在
    // 此早退；_toast 内另有一道同款兜底守卫。
    if (!mounted) return;
    final passphrase =
        _syncSecret.text.trim().isNotEmpty
            ? _syncSecret.text.trim()
            : (secrets.syncPassphrase ?? '');
    final password =
        _pass.text.isNotEmpty ? _pass.text : (secrets.webdavPassword ?? '');
    if (passphrase.isEmpty) {
      _toast(
        AppLocalizations.of(context)?.webdavNeedSyncPassword ??
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
        AppLocalizations.of(context)?.webdavFormDirty ??
            '表单有未保存的修改：请先点击「保存配置」再同步（避免加密密钥与云端数据错配）',
      );
      return;
    }
    if (cfg.syncSalt == null || cfg.syncSalt!.isEmpty) {
      _toast(
        AppLocalizations.of(context)?.syncMissingSalt ??
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
    var summary = r.changed
        ? l10n?.syncDoneSummary(r.uploaded, r.downloaded, r.deletedRemote) ??
              '同步完成：↑${r.uploaded} ↓${r.downloaded} ✕${r.deletedRemote}'
        : l10n?.syncUpToDate ?? '已是最新，无需同步';
    if (r.conflictedDocIds.isNotEmpty) {
      summary =
          l10n?.syncWithConflicts(summary, r.conflictedDocIds.length) ??
          '$summary；另有 ${r.conflictedDocIds.length} 个文档本地与云端均有改动，已按你的选择处理';
    }
    // 修复 1②：解不开的旧密文必须对用户可见（同「冲突不得静默」纪律）——
    // 只说「同步完成」会把 N 个文档永远下不下来这件事藏起来。
    if (r.unreadableDocIds.isNotEmpty) {
      summary =
          '$summary${l10n?.syncUnreadableRemoteCount(r.unreadableDocIds.length) ?? '；${r.unreadableDocIds.length} 个云端文档用当前同步口令解不开（多半是改过口令之前的旧密文），其余文档已正常同步'}';
    }
    // keepBoth 的云端副本读不出来时本轮不上传（不覆盖云端），这事必须同样
    // 可见且可执行：否则用户以为「两者皆保留」已经生效。
    if (r.unprotectedRemoteDocIds.isNotEmpty) {
      summary =
          '$summary${l10n?.syncRemoteCopyUnprotectedCount(r.unprotectedRemoteDocIds.length) ?? '；${r.unprotectedRemoteDocIds.length} 个云端副本暂时读不出来，为避免覆盖已跳过这几个文档的上传（本次未同步）：请确认同步口令是否填回原值，或稍后再同步一次'}';
    }
    return summary;
  }

  /// 轻提示。
  ///
  /// mounted 守卫收口在此（P2 修复）：本页多处 await 之后才提示，页面被
  /// pop 时 `ScaffoldMessenger.of(context)` 会拿 defunct element 的 context
  /// 直接抛错。各调用点仍保留早退守卫——不弹就别继续走 setState。
  void _toast(String msg) {
    if (!mounted) return;
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
              // P1-2：文案来自 arb（core 只给阶段与计数）。
              syncProgressLabel(_progress!, AppLocalizations.of(context)),
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
