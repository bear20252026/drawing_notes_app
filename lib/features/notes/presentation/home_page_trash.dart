part of 'home_page.dart';

/// 回收站对话框（审计 2026-09-26 #37：自 home_page.dart 拆出，行为零变化）。
extension _HomePageTrashOps on _HomePageState {
  /// M-06 回收站对话框（专家审计 2026-08-15）：列出已删除文档（id/删除
  /// 时间）+ 恢复/永久删除/清空（UX Patterns 官方模式——Restore 主操作、
  /// 永久删除分离——操作后刷新列表）。
  Future<void> _showTrashDialog() async {
    final List<(String, String, DateTime)> trash;
    try {
      trash = await _docStorage.listTrash();
    } catch (e) {
      _showSnack(_l10nSafe?.homeTrashLoadFailed ?? '回收站加载失败，请重试');
      return;
    }
    if (!mounted) return;
    await GlassDialog.show<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_l10nSafe?.trash ?? '回收站（30 天内可恢复）'),
        content: ConstrainedBox(
          // L-02 响应式（专家审计 2026-08-15）：maxWidth 而非固定宽度——
          // 窄屏自适应（原 SizedBox 固定 380 在窄屏可能溢出）。
          constraints: const BoxConstraints(maxWidth: 380),
          child: trash.isEmpty
              ? Text(_l10nSafe?.homeTrashEmpty ?? '回收站为空')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: trash.length,
                  itemBuilder: (context, i) {
                    final item = trash[i];
                    final time = item.$3.toLocal().toString().substring(0, 16);
                    return ListTile(
                      title: Text(item.$2),
                      subtitle: Text(
                        _l10nSafe?.homeDeletedAt(time) ?? '删除于 $time',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: _l10nSafe?.homeRecover ?? '恢复',
                            icon: const Icon(Icons.restore),
                            onPressed: () async {
                              try {
                                final id = await _docStorage.restoreTrash(
                                  item.$1,
                                );
                                if (ctx.mounted) Navigator.of(ctx).pop();
                                unawaited(_refresh());
                                if (id != null) {
                                  _showSnack(
                                    _l10nSafe?.homeRecovered(id) ?? '已恢复「$id」',
                                  );
                                }
                              } catch (e) {
                                _showSnack(
                                  _l10nSafe?.homeRestoreFailed ?? '恢复失败，请重试',
                                );
                              }
                            },
                          ),
                          IconButton(
                            tooltip: _l10nSafe?.homeDeleteForever ?? '永久删除',
                            icon: const Icon(Icons.delete_forever),
                            onPressed: () async {
                              final ok = await _confirmDelete(
                                _l10nSafe?.homeDeleteForever ?? '永久删除',
                                _l10nSafe?.homeDeleteForeverConfirm(item.$2) ??
                                    '确定永久删除「${item.$2}」吗？此操作不可恢复。',
                              );
                              if (ok == true) {
                                try {
                                  await _docStorage.deleteTrashPermanently(
                                    item.$1,
                                  );
                                  if (ctx.mounted) Navigator.of(ctx).pop();
                                  unawaited(_refresh());
                                } catch (e) {
                                  _showSnack(
                                    _l10nSafe?.homeDeleteForeverFailed ??
                                        '永久删除失败，请重试',
                                  );
                                }
                              }
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        actions: [
          if (trash.isNotEmpty)
            TextButton(
              onPressed: () async {
                await _docStorage.purgeTrash();
                if (ctx.mounted) Navigator.of(ctx).pop();
                unawaited(_refresh());
              },
              child: Text(_l10nSafe?.homeEmptyTrash ?? '清空回收站'),
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(_l10nSafe?.close ?? '关闭'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirmDelete(String title, String content) {
    return GlassDialog.confirm(
      context,
      title: title,
      content: content,
      confirmText: _l10nSafe?.delete ?? '删除',
      cancelText: _l10nSafe?.homeCancel ?? '取消',
      dangerous: true,
    );
  }
}
