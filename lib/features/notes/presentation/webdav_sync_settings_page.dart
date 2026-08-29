// 由 Claude 团队生成 | Drawing Notes App
// WebDAV 本地优先同步：设置页（服务器/认证 + 立即同步 + 端到端加密）。

import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:drawing_notes_app/core/storage/webdav_sync_client.dart';
import 'package:drawing_notes_app/core/sync/sync_cipher.dart';
import 'package:drawing_notes_app/core/sync/sync_progress.dart';
import 'package:drawing_notes_app/core/sync/sync_retry_policy.dart';
import 'package:drawing_notes_app/core/sync/sync_service.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/file_sync_baseline_store.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/note_block_doc_store.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/note_block_doc_sync_store.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/webdav_config_store.dart';

/// WebDAV 同步设置页。
class WebDavSyncSettingsPage extends StatefulWidget {
  const WebDavSyncSettingsPage({super.key, this.configStore});

  final WebDavConfigStore? configStore;

  @override
  State<WebDavSyncSettingsPage> createState() => _WebDavSyncSettingsPageState();
}

class _WebDavSyncSettingsPageState extends State<WebDavSyncSettingsPage> {
  late final WebDavConfigStore _configStore;
  final _url = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _syncSecret = TextEditingController();
  bool _syncing = false;
  SyncProgress? _progress;
  String? _lastSummary;

  @override
  void initState() {
    super.initState();
    _configStore = widget.configStore ?? WebDavConfigStore();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final cfg = await _configStore.load();
    if (!mounted) return;
    setState(() {
      _url.text = cfg.baseUrl;
      _user.text = cfg.username;
      _pass.text = cfg.password;
      _syncSecret.text = cfg.syncPassphrase ?? '';
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
    await _configStore.save(WebDavSyncConfig(
      baseUrl: _url.text.trim(),
      username: _user.text.trim(),
      password: _pass.text,
      syncPassphrase: passphrase.isEmpty ? null : passphrase,
      syncSalt: saltBase64,
    ));
    if (!mounted) return;
    _toast(passphrase.isEmpty
        ? '已保存 WebDAV 配置（未启用端到端加密）'
        : '已保存 WebDAV 配置（已启用端到端加密）');
  }

  Future<void> _syncNow() async {
    final rawUrl = _url.text.trim();
    final uri = Uri.tryParse(rawUrl);
    if (rawUrl.isEmpty || uri == null || !uri.hasScheme) {
      _toast('请先填写合法的服务器 URL（含 http/https 与 /）');
      return;
    }
    setState(() {
      _syncing = true;
      _progress = SyncProgress.starting();
      _lastSummary = null;
    });
    try {
      final cfg = await _configStore.load();
      final cipher = await _buildCipher(cfg);
      final service = SyncService(
        transport: WebDavSyncClient(
          baseUrl: uri,
          username: _user.text.trim(),
          password: _pass.text,
        ),
        documentStore: NoteBlockDocSyncStore(NoteBlockDocStore()),
        baselineStore: FileSyncBaselineStore(),
        cipher: cipher,
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
          final summary = '同步失败：${outcome.error ?? '未知错误'}';
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
      setState(() {
        _progress = SyncProgress.failure('同步初始化失败：$e');
        _lastSummary = '同步初始化失败：$e';
      });
      _toast('同步初始化失败：$e');
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
      return '$base；另有 ${r.conflictedDocIds.length} 个文档本地与云端均有改动，已应用较新版本';
    }
    return base;
  }

  // 已配置口令 → 派生主密钥并用 AES 加密器；否则用 Noop（明文透传）。
  Future<SyncCipher> _buildCipher(WebDavSyncConfig cfg) async {
    if (!cfg.hasSyncSecret) return const NoopSyncCipher();
    final salt = base64Decode(cfg.syncSalt!);
    final key = await deriveMasterKey(cfg.syncPassphrase!, salt);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WebDAV 同步')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '本地优先同步：数据保存在本机，通过 WebDAV（如 Nextcloud / 自建）在工作区之间同步。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: '服务器 URL',
              hintText: 'https://dav.example.com/drawing_notes/',
              prefixIcon: Icon(Icons.cloud_outlined),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _user,
            decoration: const InputDecoration(
              labelText: '用户名',
              prefixIcon: Icon(Icons.person_outline),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pass,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: '密码',
              prefixIcon: Icon(Icons.lock_outline),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _syncSecret,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: '同步密码（可选，用于端到端加密）',
              helperText: '与服务器认证密码独立；云端仅保存加密后的数据',
              prefixIcon: Icon(Icons.vpn_key_outlined),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _syncing ? null : _syncNow,
            icon: _syncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            label: Text(_syncing ? '同步中…' : '立即同步'),
          ),
          if (_progress != null) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: _progress!.fraction,
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
            ),
            const SizedBox(height: 4),
            Text(
              _progress!.description,
              style: Theme.of(context).textTheme.bodySmall,
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
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _syncing ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('保存配置'),
          ),
        ],
      ),
    );
  }
}
