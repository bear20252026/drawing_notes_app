// 由 Claude 团队生成 | Drawing Notes App
// WebDAV 本地优先同步：设置页（服务器/认证 + 立即同步 + 端到端加密）。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:drawing_notes_app/core/storage/webdav_sync_client.dart';
import 'package:drawing_notes_app/core/security/audit_logger.dart';
import 'package:drawing_notes_app/core/security/vault_key_service.dart';
import 'package:drawing_notes_app/core/theme/apple_design.dart';
import 'package:drawing_notes_app/core/sync/sync_cipher.dart';
import 'package:drawing_notes_app/core/sync/sync_conflict.dart';
import 'package:drawing_notes_app/core/sync/sync_progress.dart';
import 'package:drawing_notes_app/core/sync/sync_retry_policy.dart';
import 'package:drawing_notes_app/core/sync/sync_service.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/file_sync_baseline_store.dart';
import 'package:drawing_notes_app/features/doc/infrastructure/note_block_doc_store.dart';
import 'package:drawing_notes_app/features/doc/infrastructure/note_block_doc_sync_store.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/sync_secret_store.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/webdav_config_store.dart';
import 'package:drawing_notes_app/features/notes/presentation/conflict_resolution_dialog.dart';
import 'package:drawing_notes_app/shared/widgets/glass_dialog.dart';
import 'package:drawing_notes_app/shared/widgets/glass_app_bar.dart';

/// R1：把同步异常映射为人话文案——用户界面只出现可读懂的提示，
/// 原始异常对象进调试日志（debugPrint），不再直接拼进 UI 字符串。
String humanizeWebDavSyncError(Object? e) {
  if (e == null) return '同步失败：未知错误';
  if (e is String) return '同步失败：$e';
  // P1 修复（审计 H-04）：原始异常可能含 URL/用户名/口令片段——仅记类型，
  // 不记原文（logcat 可被其他应用读取）。
  AuditLogger.log(
    'webdav.sync.error',
    success: false,
    detail: e.runtimeType.toString(),
  );
  if (e is WebDavSyncException) {
    // 本地安全门禁（https/路径白名单）文案已是人话，直接透出。
    if (e.message.contains('https') || e.message.contains('远端路径')) {
      return '同步失败：${e.message}';
    }
    final code = e.statusCode;
    if (code == 401 || code == 403) {
      return '同步失败：用户名或密码不对（服务器拒绝登录）';
    }
    if (code != null && code >= 500) {
      return '同步失败：服务器暂时不可用（HTTP $code），请稍后再试';
    }
    if (code == 404 || code == 409) {
      return '同步失败：服务器目录不存在或路径被占用，请检查远端目录设置';
    }
    return '同步失败：服务器拒绝了这次请求（HTTP ${code ?? '未知'}）';
  }
  if (e is HandshakeException) {
    return '同步失败：安全连接（HTTPS）握手失败，请检查服务器证书';
  }
  if (e is SocketException || e is TimeoutException) {
    return '同步失败：连不上服务器，请检查网络或服务器地址';
  }
  return '同步失败：请检查网络与账号设置后重试';
}

/// WebDAV 同步设置页。
class WebDavSyncSettingsPage extends StatefulWidget {
  const WebDavSyncSettingsPage({super.key, this.configStore, this.secretStore});

  final WebDavConfigStore? configStore;
  final SyncSecretStore? secretStore;

  @override
  State<WebDavSyncSettingsPage> createState() => _WebDavSyncSettingsPageState();
}

class _WebDavSyncSettingsPageState extends State<WebDavSyncSettingsPage> {
  late final WebDavConfigStore _configStore;
  late final SyncSecretStore _secretStore;
  final _url = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _syncSecret = TextEditingController();
  bool _syncing = false;
  SyncProgress? _progress;
  String? _lastSummary;

  /// 空操作回调（用于禁用态按钮）。
  static void _noop() {}

  @override
  void initState() {
    super.initState();
    _configStore =
        widget.configStore ?? WebDavConfigStore(SecureSyncSecretStore());
    _secretStore = widget.secretStore ?? SecureSyncSecretStore();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final cfg = await _configStore.load();
    final secrets = await _secretStore.read();
    if (!mounted) return;
    setState(() {
      _url.text = cfg.baseUrl;
      _user.text = cfg.username;
      _pass.text = secrets.webdavPassword ?? '';
      _syncSecret.text = secrets.syncPassphrase ?? '';
    });
  }

  Future<void> _save() async {
    final existing = await _configStore.load();
    final passphrase = _syncSecret.text.trim();
    String? saltBase64;
    if (passphrase.isNotEmpty) {
      // 复用已有盐（若无则生成新的），保证派生 key 对已上传密文保持稳定。
      saltBase64 = existing.syncSalt;
      if (saltBase64 == null || saltBase64.isEmpty) {
        saltBase64 = base64Encode(generateSalt());
      }
    }
    // P1 修复：save 内 https 门禁抛 ArgumentError——捕获后明示，不崩溃。
    try {
      await _configStore.save(
        WebDavSyncConfig(
          baseUrl: _url.text.trim(),
          username: _user.text.trim(),
          syncSalt: saltBase64,
        ),
      );
    } on ArgumentError catch (e) {
      if (!mounted) return;
      _toast('保存失败：${e.message}');
      return;
    }
    await _secretStore.write(
      SyncSecrets(
        webdavPassword: _pass.text.isEmpty ? null : _pass.text,
        syncPassphrase: passphrase.isEmpty ? null : passphrase,
      ),
    );
    if (!mounted) return;
    _toast(
      passphrase.isEmpty
          ? '已保存 WebDAV 配置（未启用端到端加密）'
          : '已保存 WebDAV 配置（已启用端到端加密）',
    );
  }

  Future<void> _syncNow() async {
    final rawUrl = _url.text.trim();
    final uri = Uri.tryParse(rawUrl);
    if (rawUrl.isEmpty || uri == null || !uri.hasScheme) {
      _toast('请先填写合法的服务器 URL（含 http/https 与 /）');
      return;
    }
    // 安全审计修复（2026-09-06 P1-2）：未配置同步密码 = 同步层明文透传，
    // 笔记正文会以明文落在 WebDAV 服务器（UI 曾误称「云端仅保存加密数据」）。
    // fail-closed：拒绝同步，要求先设置同步密码。
    if (_syncSecret.text.trim().isEmpty) {
      _toast('未设置同步密码：为避免笔记明文上云，已阻止同步。请在下方设置同步密码后重试。');
      return;
    }
    setState(() {
      _syncing = true;
      _progress = SyncProgress.starting();
      _lastSummary = null;
    });
    try {
      final cfg = await _configStore.load();
      final cipher = await _buildCipher(
        syncSalt: cfg.syncSalt,
        syncPassphrase: _syncSecret.text.trim(),
      );
      final service = SyncService(
        transport: WebDavSyncClient(
          baseUrl: uri,
          username: _user.text.trim(),
          password: _pass.text,
        ),
        // 批次①c：自建 store 也接共享保险库密钥——保险库解锁时同步能
        // 读写 DNV 密文文档（锁定时 keyProvider 返回 null，fail-closed）。
        documentStore: NoteBlockDocSyncStore(
          NoteBlockDocStore(
            keyProvider: () async => VaultKeyService.sharedMasterKeyOrNull,
          ),
        ),
        baselineStore: FileSyncBaselineStore(),
        cipher: cipher,
        conflictHandler: _DialogConflictHandler(this),
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      try {
        // 有界自动重试：派生密钥复用同一 service，失败按策略退避。
        final retry = SyncRetryPolicy();
        final start = DateTime.now();
        final outcome = await _runWithRetry(service, retry, start);
        if (!mounted) return;
        if (outcome.result != null) {
          final summary = _summaryOf(outcome.result!);
          setState(() {
            _progress = SyncProgress.complete();
            _lastSummary = summary;
          });
          _toast(summary);
        } else {
          final summary = humanizeWebDavSyncError(outcome.error);
          setState(() {
            _progress = SyncProgress.failure(summary);
            _lastSummary = summary;
          });
          _toast(summary);
        }
      } finally {
        service.close();
      }
    } catch (e) {
      if (!mounted) return;
      final summary = humanizeWebDavSyncError(e);
      setState(() {
        _progress = SyncProgress.failure(summary);
        _lastSummary = summary;
      });
      _toast(summary);
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  // 有界重试：达到 maxAttempts 或策略判定 giveUp 则放弃；返回最后一次结果/错误。
  Future<({SyncResult? result, Object? error})> _runWithRetry(
    SyncService service,
    SyncRetryPolicy retry,
    DateTime start,
  ) async {
    var attempt = 0;
    while (attempt < retry.maxAttempts) {
      try {
        final r = await service.syncNow();
        return (result: r, error: null);
      } catch (e) {
        attempt++;
        if (attempt >= retry.maxAttempts) return (result: null, error: e);
        final elapsed = DateTime.now().difference(start);
        final input = SyncRetryInput(failureCount: attempt, elapsed: elapsed);
        final decision = retry.decide(input);
        if (decision == SyncRetryDecision.giveUp) {
          return (result: null, error: e);
        }
        final wait = retry.delayFor(attempt);
        if (wait > Duration.zero) await Future<void>.delayed(wait);
      }
    }
    return (result: null, error: '达到最大重试次数');
  }

  String _summaryOf(SyncResult r) {
    final base = r.changed
        ? '同步完成：↑${r.uploaded} ↓${r.downloaded} ✕${r.deletedRemote}'
        : '已是最新，无需同步';
    if (r.conflictedDocIds.isNotEmpty) {
      return '$base；另有 ${r.conflictedDocIds.length} 个文档本地与云端均有改动，已按你的选择处理';
    }
    return base;
  }

  // 已配置口令（含盐）→ 派生主密钥并用 AES 加密器；否则用 Noop（明文透传）。
  Future<SyncCipher> _buildCipher({
    required String? syncSalt,
    required String syncPassphrase,
  }) async {
    if (syncSalt == null || syncSalt.isEmpty || syncPassphrase.isEmpty) {
      return const NoopSyncCipher();
    }
    final salt = base64Decode(syncSalt);
    final key = await deriveMasterKey(syncPassphrase, salt);
    return AesSyncCipher(key: key);
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
        borderSide: const BorderSide(color: AppleColor.actionBlue, width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const GlassAppBar(title: Text('WebDAV 同步')),
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
            '本地优先同步：数据保存在本机，通过 WebDAV（如 Nextcloud / 自建）在工作区之间同步。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppleSpacing.md),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            decoration: _appleDecoration(
              labelText: '服务器 URL',
              hintText: 'https://dav.example.com/drawing_notes/',
              icon: Icons.cloud_outlined,
            ),
          ),
          const SizedBox(height: AppleSpacing.sm),
          TextField(
            controller: _user,
            decoration: _appleDecoration(
              labelText: '用户名',
              icon: Icons.person_outline,
            ),
          ),
          const SizedBox(height: AppleSpacing.sm),
          TextField(
            controller: _pass,
            obscureText: true,
            decoration: _appleDecoration(
              labelText: '密码',
              icon: Icons.lock_outline,
            ),
          ),
          const SizedBox(height: AppleSpacing.sm),
          TextField(
            controller: _syncSecret,
            obscureText: true,
            decoration: _appleDecoration(
              labelText: '同步密码（必填，用于端到端加密）',
              icon: Icons.vpn_key_outlined,
              helperText: '未设置同步密码时同步会被阻止（防止笔记明文上云）',
            ),
          ),
          const SizedBox(height: AppleSpacing.lg),
          _syncing
              ? const ApplePrimaryButton(label: '同步中…', onPressed: _noop)
              : ApplePrimaryButton(label: '立即同步', onPressed: _syncNow),
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
            const SizedBox(height: 6),
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
            label: const Text('保存配置'),
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
