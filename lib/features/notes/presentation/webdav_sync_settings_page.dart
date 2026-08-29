// 由 Claude 团队生成 | Drawing Notes App
// WebDAV 本地优先同步：设置页（服务器/认证 + 立即同步）。

import 'package:flutter/material.dart';

import 'package:drawing_notes_app/core/storage/webdav_sync_client.dart';
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
  bool _syncing = false;

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
    });
  }

  Future<void> _save() async {
    await _configStore.save(WebDavSyncConfig(
      baseUrl: _url.text.trim(),
      username: _user.text.trim(),
      password: _pass.text,
    ));
    if (!mounted) return;
    _toast('已保存 WebDAV 配置');
  }

  Future<void> _syncNow() async {
    final rawUrl = _url.text.trim();
    final uri = Uri.tryParse(rawUrl);
    if (rawUrl.isEmpty || uri == null || !uri.hasScheme) {
      _toast('请先填写合法的服务器 URL（含 http/https 与 /）');
      return;
    }
    setState(() => _syncing = true);
    try {
      final service = SyncService(
        transport: WebDavSyncClient(
          baseUrl: uri,
          username: _user.text.trim(),
          password: _pass.text,
        ),
        documentStore: NoteBlockDocSyncStore(NoteBlockDocStore()),
        baselineStore: FileSyncBaselineStore(),
      );
      try {
        final result = await service.syncNow();
        if (!mounted) return;
        _toast(result.changed
            ? '同步完成：↑${result.uploaded} ↓${result.downloaded} ✕${result.deletedRemote}'
            : '已是最新，无需同步');
      } finally {
        service.close();
      }
    } catch (e) {
      if (!mounted) return;
      _toast('同步失败：$e');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
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
