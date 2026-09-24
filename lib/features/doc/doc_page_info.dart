part of 'doc_page.dart';

// 信息与标签域（O1 拆分自 doc_page.dart）：信息卡、标签切换与内联
// 建档、snack、日期格式化。行为零变化。

/// 信息卡/标签域私有助手（拆分自 doc_page.dart）。
extension _DocPageInfo on _DocPageState {

  void _snack(String message) {
    if (!mounted) return;
    AppSnack.show(context, message);
  }


  /// 文档显示名（空标题回退「未命名」，可被 l10n 覆盖）。
  String _docName(NoteBlockDoc doc) => doc.title.isEmpty
      ? AppLocalizations.of(context)?.docUntitled ?? '未命名'
      : doc.title;


  /// 文档信息对话框（含标签编辑——M12.6 标签系统入口）。
  void _showInfoDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tagStore = widget.tagStore ?? TagStore();
    final title = _docName(_doc);
    GlassDialog.show<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow(l10n?.docCreatedAt ?? '创建于', _fmtDate(_doc.createdAt)),
              _infoRow(l10n?.docUpdatedAt ?? '更新于', _fmtDate(_doc.updatedAt)),
              _infoRow(l10n?.docBlockCount ?? '块数量', '${_doc.body.length}'),
              const SizedBox(height: 12),
              Text(
                l10n?.docTags ?? '标签',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: FutureBuilder<List<DocTag>>(
                  future: tagStore.listTags(),
                  builder: (context, snap) {
                    final allTags = snap.data ?? const <DocTag>[];
                    final assigned = allTags
                        .where((t) => _doc.tags.contains(t.id))
                        .toList();
                    final available = allTags
                        .where((t) => !_doc.tags.contains(t.id))
                        .toList();
                    return SingleChildScrollView(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final t in assigned)
                            Chip(
                              label: Text(t.name),
                              onDeleted: () => _toggleDocTag(t.id),
                            ),
                          for (final t in available)
                            ActionChip(
                              label: Text('+ ${t.name}'),
                              onPressed: () => _toggleDocTag(t.id),
                            ),
                          ActionChip(
                            label: const Icon(Icons.add_rounded, size: 18),
                            onPressed: () => _createTagInline(tagStore),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            // 键盘可达：默认聚焦「关闭」，Enter 直接关（防误触他处）。
            autofocus: true,
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n?.close ?? '关闭'),
          ),
        ],
      ),
    );
  }


  /// 给当前文档加/移除标签（编辑即保存）。
  Future<void> _toggleDocTag(String tagId) async {
    final tags = List.of(_doc.tags);
    if (tags.contains(tagId)) {
      tags.remove(tagId);
    } else {
      tags.add(tagId);
    }
    final updated = _doc.copyWith(tags: tags, updatedAt: DateTime.now());
    // 先落盘、成功后才更新 UI——失败时保持原标签状态，避免假保存。
    try {
      await widget.controller?.save(updated);
    } catch (e) {
      _snack(
        (mounted ? AppLocalizations.of(context) : null)?.docSnackSaveKept ??
            '保存失败，已保持原状态',
      );
      return;
    }
    if (!mounted) return;
    pageSetState(() => _doc = updated);
    Navigator.of(context).pop();
    _showInfoDialog(context);
  }


  /// 快速新建标签（输入名称 → 默认紫色）。
  Future<void> _createTagInline(TagStore tagStore) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    // P3：对话框结束后释放 controller（审计低危 L1）。
    try {
      final name = await GlassDialog.show<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n?.docNewTag ?? '新建标签'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: l10n?.docTagNameHint ?? '标签名称',
            ),
          ),
          actions: AppleDialog.actions([
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n?.cancel ?? '取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text),
              child: Text(l10n?.create ?? '创建'),
            ),
          ]),
        ),
      );
      if (name == null || name.trim().isEmpty) return;
      final tag = await tagStore.addTag(name);
      if (tag != null && !_doc.tags.contains(tag.id)) {
        await _toggleDocTag(tag.id);
      }
    } catch (e) {
      _snack(
        (mounted ? AppLocalizations.of(context) : null)?.docSnackTagFailed ??
            '创建标签失败，请重试',
      );
    } finally {
      controller.dispose();
    }
  }


  Widget _infoRow(String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: AppleType.controlStyle(
              scheme.onSurfaceVariant,
            ).copyWith(fontWeight: FontWeight.w400),
          ),
          Text(
            value,
            style: AppleType.controlStyle(
              scheme.onSurface,
            ).copyWith(fontWeight: FontWeight.w400),
          ),
        ],
      ),
    );
  }


  // 日期部分为 yyyy/M/d（不补零）的本地展示格式，与 formatShortDate
  // 不同，仅钟点读数复用 formatClock。
  String _fmtDate(DateTime d) =>
      '${d.year}/${d.month}/${d.day} ${formatClock(d)}';
}
