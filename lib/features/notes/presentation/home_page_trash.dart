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
              // TRASH-LAYOUT（第四轮审计追加发现，2026-10-16，由本批新用例逼出）：
              // 原先这里是 `ListView.builder(shrinkWrap: true)`，而 Material
              // `AlertDialog` 要用固有尺寸量内容 ⇒ 触发「viewport 不支持返回固有
              // 尺寸」断言：debug/profile 直接炸渲染，release 下这条查询拿到 0，
              // 列表高度归零。条目形态本来就是「30 天内删掉的文档」，
              // Column 支持固有尺寸，也就不需要懒加载那一层。
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final item in trash) _trashTile(ctx, item),
                      ],
                    ),
                  ),
                ),
        ),
        actions: [
          if (trash.isNotEmpty)
            TextButton(
              // NOT-01：这枚按钮原写作「清空回收站」，却只删超过保留期的条目
              // ——未满期的仍会留在回收站里，而且零二次确认。文案按真实作用域
              // 改写，并补上确认与结果回执。
              onPressed: () async {
                final days = StorageService.trashRetentionDays;
                final label = _l10nSafe?.homeEmptyTrash ?? '清除过期条目';
                final ok = await _confirmDelete(
                  label,
                  _l10nSafe?.homePurgeExpiredConfirm(days) ??
                      '这里只会删除超过 $days 天的条目，未满期的仍会保留。确定现在清除吗？',
                );
                if (ok != true) return;
                if (!_allowTrashOp('note.purge', null)) return;
                try {
                  final purged = await _docStorage.purgeTrash();
                  _showSnack(
                    _l10nSafe?.homePurgedN(purged) ?? '已清除 $purged 个过期条目',
                  );
                  if (ctx.mounted) Navigator.of(ctx).pop();
                  unawaited(_refresh());
                } catch (e) {
                  _showSnack(
                    _l10nSafe?.homeDeleteForeverFailed ?? '永久删除失败，请重试',
                  );
                }
              },
              child: Text(_l10nSafe?.homeEmptyTrash ?? '清除过期条目'),
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(_l10nSafe?.close ?? '关闭'),
          ),
        ],
      ),
    );
  }

  /// 回收站里的一行：文档 id + 删除时间 + 恢复 / 永久删除两个动作。
  Widget _trashTile(BuildContext ctx, (String, String, DateTime) item) {
    final time = item.$3.toLocal().toString().substring(0, 16);
    return ListTile(
      title: Text(item.$2),
      subtitle: Text(_l10nSafe?.homeDeletedAt(time) ?? '删除于 $time'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: _l10nSafe?.homeRecover ?? '恢复',
            icon: const Icon(Icons.restore),
            onPressed: () async {
              if (!_allowTrashOp('note.restore', item.$1)) {
                return;
              }
              try {
                final id = await _docStorage.restoreTrash(item.$1);
                if (ctx.mounted) Navigator.of(ctx).pop();
                unawaited(_refresh());
                if (id != null) {
                  _showSnack(_l10nSafe?.homeRecovered(id) ?? '已恢复「$id」');
                }
              } catch (e) {
                _showSnack(_l10nSafe?.homeRestoreFailed ?? '恢复失败，请重试');
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
              if (ok != true) return;
              // 门禁排在确认**之后**：先判后问会让用户的取消
              // 也留下一条「放行」审计——那是没发生过的事。
              if (!_allowTrashOp('note.purge', item.$1)) {
                return;
              }
              try {
                await _docStorage.deleteTrashPermanently(item.$1);
                if (ctx.mounted) Navigator.of(ctx).pop();
                unawaited(_refresh());
              } catch (e) {
                _showSnack(_l10nSafe?.homeDeleteForeverFailed ?? '永久删除失败，请重试');
              }
            },
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

  /// NOT-01：回收站的三类动作统一经**默认拒绝**策略判定（与
  /// `app_shell_routes` 的 restore/purge 用同一份白名单）。[PolicyEngine
  /// .enforceCheck] 在 deny 时抛异常，这里捕获后拒绝执行并告知用户——
  /// 既不放行，也不静默。
  bool _allowTrashOp(String operation, String? target) {
    try {
      const PolicyEngine().enforceCheck(operation, target: target);
      return true;
    } on PolicyDeniedException catch (e) {
      _showSnack(
        _l10nSafe?.docPolicyDenied(e.operation) ?? '操作被策略拒绝（$operation）',
      );
      return false;
    }
  }
}
