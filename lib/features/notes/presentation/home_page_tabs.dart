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
    return TabBarView(children: [_buildDrawingsTab(), _buildNotesTab()]);
  }

  // ---------------- 画布 Tab ----------------

  Widget _buildDrawingsTab() {
    if (_documents.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.brush_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 12),
            Text('还没有画布，点击右下角按钮新建一个吧'),
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
          onPasswordAction: () => _showDrawingPasswordSheet(_documents[i]),
        ),
      ),
    );
  }

  // ---------------- 笔记 Tab（M12：笔记本=笔记）----------------

  Widget _buildNotesTab() {
    if (_notes.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.edit_note_rounded, size: 64, color: Colors.grey),
            SizedBox(height: 12),
            Text('还没有笔记，点击右下角按钮新建一个吧'),
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
        itemCount: _notes.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final doc = _notes[i];
          final isTyped = doc.kind == AllDocKind.blockdoc;
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
                child: Icon(
                  isTyped ? Icons.edit_note_rounded : Icons.description_rounded,
                ),
              ),
              title: Text(
                doc.title.isEmpty ? '未命名' : doc.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  '${isTyped ? '笔记' : '分页画布页面'}'
                  ' · 更新于 ${_formatTime(doc.updatedAt)}',
                ),
              ),
              // 分页画布页面的删除在其所属分页画布页内管理（含克隆引用语义）；
              // 笔记支持此处直接删除。
              trailing: isTyped
                  ? IconButton(
                      tooltip: '删除笔记',
                      icon: const Icon(Icons.delete_outline_rounded),
                      color: Theme.of(context).colorScheme.error,
                      onPressed: () => _deleteNote(doc),
                    )
                  : null,
              onTap: () => _openEntry(doc),
            ),
          );
        },
      ),
    );
  }

  /// 统一打开路径（M12.4）：与 All Docs 同一回调（note→NotebookViewPage，
  /// blockdoc→DocPage）。无宿主回调时兜底直推 DocPage（仅笔记）。
  Future<void> _openEntry(AllDoc doc) async {
    if (widget.onOpenDoc != null) {
      widget.onOpenDoc!(doc);
      return;
    }
    if (doc.kind != AllDocKind.blockdoc) return;
    final d = await _blockDocStore.loadDocument(doc.id);
    if (!mounted || d == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DocPage(
          document: d,
          blockDocStore: _blockDocStore,
          controller: DocController(
            onSave: (updated) => _blockDocStore.saveDocument(updated),
          ),
        ),
      ),
    );
    await _refresh();
  }

  String _formatTime(DateTime t) {
    final now = DateTime.now();
    if (t.year == now.year && t.month == now.month && t.day == now.day) {
      return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    }
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }

  Future<void> _deleteNote(AllDoc doc) async {
    // 策略门禁（专家审计最优先④）：删除操作白名单判定（回收站——可恢复）。
    if (!const PolicyEngine().check('note.delete').isAllowed) {
      _showSnack('操作被策略拒绝（note.delete）');
      return;
    }
    final ok = await _confirmDelete(
      '删除笔记',
      '确定删除笔记「${doc.title.isEmpty ? '未命名' : doc.title}」吗？此操作不可恢复。',
    );
    if (ok != true) return;
    try {
      await _blockDocStore.deleteDocument(doc.id);
      widget.onDataChanged?.call();
      await _refresh();
    } catch (e) {
      _showSnack('删除失败：${e.runtimeType}');
    }
  }
}
