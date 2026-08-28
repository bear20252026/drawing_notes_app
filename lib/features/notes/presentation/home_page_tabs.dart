part of 'home_page.dart';

// 首页 Tab 布局域（行数门禁拆分）：_buildBody / 三个 Tab / 打开笔记本等。
// 从 home_page.dart 移出为 extension（行为零变化），保持主文件 < 500 逻辑行。

extension _HomePageTabs on _HomePageState {
  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: _refresh, child: const Text('重试')),
          ],
        ),
      );
    }
    return TabBarView(
      children: [
        _buildDrawingsTab(),
        _buildNotebooksTab(),
        _buildTimelineTab(),
      ],
    );
  }

  // ---------------- 时间线 Tab（A4，借鉴 Memos/Notes） ----------------

  /// 时间线视图：合并画作与笔记本页面，按更新时间倒序展示。
  Widget _buildTimelineTab() {
    // 条目携带跳转目标：画作 -> meta；页面 -> 笔记本 + 页面。
    final entries =
        <
          ({
            DateTime time,
            String type,
            String title,
            String sub,
            DocumentMeta? drawing,
            Notebook? notebook,
            NotebookPage? page,
          })
        >[];
    for (final m in _documents) {
      entries.add((
        time: m.updatedAt,
        type: '画作',
        title: m.title,
        sub: '画作',
        drawing: m,
        notebook: null,
        page: null,
      ));
    }
    for (final nb in _notebooks) {
      for (final p in nb.pages) {
        entries.add((
          time: p.updatedAt,
          type: '页面',
          title: '${nb.title} / ${p.title}',
          sub: p.folder.isNotEmpty ? '📁 ${p.folder}' : nb.title,
          drawing: null,
          notebook: nb,
          page: p,
        ));
      }
    }
    entries.sort((a, b) => b.time.compareTo(a.time));
    if (entries.isEmpty) {
      return const Center(
        child: Text('还没有任何内容，先新建画作或笔记本吧', style: TextStyle(color: Colors.grey)),
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: entries.length,
        itemBuilder: (context, i) {
          final e = entries[i];
          return ListTile(
            leading: Icon(e.type == '画作' ? Icons.brush : Icons.menu_book),
            title: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              '${e.sub} · ${_formatTime(e.time)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            // 可用性修复：时间线条目可点击跳转（此前点击无反应）。
            onTap: e.drawing != null
                ? () => _openDrawing(e.drawing!)
                : () => _openTimelineNotebook(e.notebook!),
          );
        },
      ),
    );
  }

  /// 时间线页面条目跳转：打开对应笔记本（加密笔记本会先要求输入密码）。
  Future<void> _openTimelineNotebook(Notebook nb) async {
    if (nb.encrypted) {
      await _openNotebook(nb);
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NotebookViewPage(
          notebook: nb,
          storage: _nbStorage,
          onChanged: _refresh,
          editorPageBuilder: widget.editorPageBuilder,
        ),
      ),
    );
  }

  // ---------------- 画作 Tab ----------------

  Widget _buildDrawingsTab() {
    if (_documents.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.brush_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 12),
            Text('还没有无限画布，点击右下角按钮新建一个吧'),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: GridView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppDesign.pagePadding,
          12,
          AppDesign.pagePadding,
          96,
        ),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 256,
          childAspectRatio: 0.82,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        itemCount: _documents.length,
        itemBuilder: (context, i) => _DrawingCard(
          meta: _documents[i],
          documentStorage: _docStorage,
          onTap: () => _openDrawing(_documents[i]),
          onDelete: () => _deleteDrawing(_documents[i]),
        ),
      ),
    );
  }

  // ---------------- 笔记本 Tab ----------------

  Widget _buildNotebooksTab() {
    if (_notebooks.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 12),
            Text('还没有笔记本，点击右下角按钮新建一个吧'),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppDesign.pagePadding,
          8,
          AppDesign.pagePadding,
          96,
        ),
        itemCount: _notebooks.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final nb = _notebooks[i];
          return Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                foregroundColor: Theme.of(
                  context,
                ).colorScheme.onPrimaryContainer,
                child: const Icon(Icons.menu_book_rounded),
              ),
              title: Text(
                nb.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  '${nb.pages.length} 页 · 更新于 ${_formatTime(nb.updatedAt)}',
                ),
              ),
              trailing: IconButton(
                tooltip: '删除笔记本',
                icon: const Icon(Icons.delete_outline_rounded),
                color: Theme.of(context).colorScheme.error,
                onPressed: () => _deleteNotebook(nb),
              ),
              onTap: () => _openNotebook(nb),
            ),
          );
        },
      ),
    );
  }

  /// 打开笔记本：若已启用加密（C3/keyfile），先解锁后再进入。
  Future<void> _openNotebook(Notebook nb) async {
    var notebook = nb;
    // 会话内密码（仅内存，不落盘）：解密后传入页面，使编辑后能重加密保存。
    String? password;
    // 会话内 U盘主密钥（keyfile 模式）：插盘解锁后传入页面。
    List<int>? masterKey;
    if (nb.encrypted) {
      if (nb.encryptionMode == EncryptionMode.keyfile) {
        // U盘钥匙模式：弹密码盘选择目录 → 读取主密钥 → 解锁。
        final disk = createPasswordDisk();
        final dir = await disk.pickDirectory();
        if (dir == null || !mounted) return;
        masterKey = await disk.readKey(dir);
        if (masterKey == null) {
          _showSnack('未找到有效的密码盘（key.frogkey）');
          return;
        }
        final fresh = await _nbStorage.load(nb.id);
        if (fresh == null) return;
        try {
          final ok = await _nbStorage.decryptNotebookWithKey(fresh, masterKey);
          if (!ok) {
            _showSnack('密码盘无法解锁该笔记本');
            return;
          }
          notebook = fresh;
          _maybeWarnLegacyEncryption(fresh);
        } catch (_) {
          _showSnack('密码盘无法解锁该笔记本');
          return;
        }
      } else {
        password = await showDialog<String>(
          context: context,
          builder: (ctx) => const _PasswordDialog(title: '输入密码'),
        );
        if (password == null || !mounted) return;
        // 从存储重新加载（确保拿到密文载荷），用密码解密。
        final fresh = await _nbStorage.load(nb.id);
        if (fresh == null) return;
        try {
          final ok = await _nbStorage.decryptNotebook(fresh, password);
          if (!ok) {
            _showSnack('密码错误或数据已损坏');
            return;
          }
          notebook = fresh;
          await _upgradeLegacyPasswordEncryption(fresh, password);
          // H-03 密码模式媒体加密（方案 B）：解锁后全局盐派生注入
          // （媒体解密 key 与加密时一致）。
          final mediaSalt = await _nbStorage.ensureMediaSalt();
          await MediaCryptoService.instance.setSessionPassword(
            password,
            mediaSalt,
          );
        } catch (_) {
          _showSnack('密码错误或数据已损坏');
          return;
        }
      }
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NotebookViewPage(
          notebook: notebook,
          storage: _nbStorage,
          onChanged: _refresh,
          sessionPassword: password,
          sessionMasterKey: masterKey,
          editorPageBuilder: widget.editorPageBuilder,
        ),
      ),
    );
  }

  String _formatTime(DateTime t) {
    final now = DateTime.now();
    if (t.year == now.year && t.month == now.month && t.day == now.day) {
      return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    }
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }
}
