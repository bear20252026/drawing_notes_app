# -*- coding: utf-8 -*-
"""M12.7 DocPage：反向链接面板 + 插入页面链接。"""
import io

p = 'lib/features/doc/doc_page.dart'
s = io.open(p, encoding='utf-8').read()

# 1) 导入
old = "import 'package:drawing_notes_app/features/all_docs/infrastructure/tag_store.dart';"
new = ("import 'package:drawing_notes_app/features/all_docs/infrastructure/tag_store.dart';\n"
       "import 'package:drawing_notes_app/features/doc/application/doc_link_index.dart';")
assert old in s, 'imp'
s = s.replace(old, new, 1)

# 2) ctor + 字段
old = """    this.onOpenInEdgeless,
    this.tagStore,
  });"""
new = """    this.onOpenInEdgeless,
    this.tagStore,
    this.allDocsLoader,
    this.onOpenDocById,
  });"""
assert s.count(old) == 1, 'ctor'
s = s.replace(old, new, 1)

old = """  /// 标签注册表（M12.6 标签编辑）；null 时内部自建（全局文件）。
  final TagStore? tagStore;"""
new = """  /// 标签注册表（M12.6 标签编辑）；null 时内部自建（全局文件）。
  final TagStore? tagStore;

  /// 全量块文档读取（M12.7 反向链接索引用）；null 时隐藏反向链接面板。
  final Future<List<NoteBlockDoc>> Function()? allDocsLoader;

  /// 点击反向链接条目打开对应文档（宿主路由）。
  final void Function(String docId)? onOpenDocById;"""
assert s.count(old) == 1, 'fields'
s = s.replace(old, new, 1)

# 3) AppBar 加插入链接按钮（放 save 前）
old = """        IconButton(
          tooltip: '保存',
          icon: const Icon(Icons.save_outlined),
          onPressed: onSavePressed,
        ),"""
new = """        IconButton(
          tooltip: '插入页面链接',
          icon: const Icon(Icons.insert_link_rounded),
          onPressed: onInsertPageLink,
        ),
        IconButton(
          tooltip: '保存',
          icon: const Icon(Icons.save_outlined),
          onPressed: onSavePressed,
        ),"""
assert s.count(old) == 1, 'appbar'
s = s.replace(old, new, 1)

old = """        onExportMarkdown: _exportMarkdown,
        onExportHtml: _exportHtml,"""
new = """        onExportMarkdown: _exportMarkdown,
        onExportHtml: _exportHtml,
        onInsertPageLink: _insertPageLink,"""
assert s.count(old) == 1, 'header wire'
s = s.replace(old, new, 1)

old = """    this.onExportHtml,"""
new = """    this.onExportHtml,
    this.onInsertPageLink,"""
assert s.count(old) == 1, 'hdr ctor'
s = s.replace(old, new, 1)

old = """  /// 导出 HTML（M12.6）。
  final VoidCallback? onExportHtml;"""
new = """  /// 导出 HTML（M12.6）。
  final VoidCallback? onExportHtml;

  /// 插入页面链接（M12.7 反向链接）。
  final VoidCallback? onInsertPageLink;"""
assert s.count(old) == 1, 'hdr field'
s = s.replace(old, new, 1)

# 4) body：DocEditor 外套 Column + 底部反向链接面板
old = """          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: DocEditor(
                  key: _editorKey,
                  showChrome: false,
                  document: _doc,
                  onSave: _persist,
                  onDirty: _onEditorDirty,
                ),
              ),
            ),
          ),"""
new = """          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: DocEditor(
                        key: _editorKey,
                        showChrome: false,
                        document: _doc,
                        onSave: _persist,
                        onDirty: _onEditorDirty,
                      ),
                    ),
                    // 反向链接面板（M12.7，AFFiNE Backlinks 对齐）
                    if (widget.allDocsLoader != null)
                      _BacklinksPanel(
                        currentDoc: _doc,
                        allDocsLoader: widget.allDocsLoader!,
                        onOpenDocById: widget.onOpenDocById,
                      ),
                  ],
                ),
              ),
            ),
          ),"""
assert s.count(old) == 1, 'body'
s = s.replace(old, new, 1)

# 5) _DocPageState：插入方法 + 反向链接面板组件（插在 _showInfoDialog 前）
old = "  /// 文档信息对话框（含标签编辑——M12.6 标签系统入口）。"
new = """  /// 选择目标文档 → 在文末追加 [[标题]] 页面引用。
  Future<void> _insertPageLink() async {
    final loader = widget.allDocsLoader;
    if (loader == null) return;
    final all = await loader();
    if (!mounted) return;
    final candidates = all.where((d) => d.id != _doc.id).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final target = await showDialog<NoteBlockDoc>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('插入页面链接'),
        children: [
          for (final d in candidates.take(50))
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(d),
              child: ListTile(
                leading: const Icon(Icons.edit_note_rounded),
                title: Text(d.title.isEmpty ? '未命名' : d.title),
                subtitle: Text(
                  '更新于 '
                  '\${d.updatedAt.year}-'
                  '\${d.updatedAt.month.toString().padLeft(2, '0')}-'
                  '\${d.updatedAt.day.toString().padLeft(2, '0')}',
                ),
              ),
            ),
        ],
      ),
    );
    if (target == null) return;
    _editorKey.currentState?.appendPageLink(target);
  }

  /// 文档信息对话框（含标签编辑——M12.6 标签系统入口）。"""
assert s.count(old) == 1, 'insert fn'
s = s.replace(old, new, 1)

# 6) 文件尾追加 _BacklinksPanel
s += '''

/// 反向链接面板：列出引用了当前文档的笔记（[[标题]] 双链）。
class _BacklinksPanel extends StatefulWidget {
  const _BacklinksPanel({
    required this.currentDoc,
    required this.allDocsLoader,
    this.onOpenDocById,
  });

  final NoteBlockDoc currentDoc;
  final Future<List<NoteBlockDoc>> Function() allDocsLoader;
  final void Function(String docId)? onOpenDocById;

  @override
  State<_BacklinksPanel> createState() => _BacklinksPanelState();
}

class _BacklinksPanelState extends State<_BacklinksPanel> {
  List<NoteBlockDoc>? _backlinks;

  @override
  void didUpdateWidget(_BacklinksPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当前文档变化（保存回写）时重算索引。
    if (oldWidget.currentDoc.updatedAt != widget.currentDoc.updatedAt ||
        oldWidget.currentDoc.id != widget.currentDoc.id) {
      _reload();
    }
  }

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final all = await widget.allDocsLoader();
    if (!mounted) return;
    setState(() => _backlinks = backlinksOf(widget.currentDoc, all));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final backlinks = _backlinks;
    if (backlinks == null || backlinks.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.link_rounded,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                '反向链接 · ' + backlinks.length.toString(),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final doc in backlinks)
            InkWell(
              onTap: () => widget.onOpenDocById?.call(doc.id),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const SizedBox(width: 2),
                    Icon(
                      Icons.edit_note_rounded,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        doc.title.isEmpty ? '未命名' : doc.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
'''

io.open(p, 'w', encoding='utf-8', newline='\n').write(s)
print('OK docpage backlinks')
