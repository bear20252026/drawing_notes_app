# -*- coding: utf-8 -*-
"""M12.6 收尾：DocPage 标签编辑 + shell TagStore + HomePage 模板对话框。"""
import io

# ───────── 1. DocPage：信息对话框标签编辑 ─────────
p = 'lib/features/doc/doc_page.dart'
s = io.open(p, encoding='utf-8').read()

old = "import 'package:drawing_notes_app/features/doc/application/doc_export_io.dart';"
new = ("import 'package:drawing_notes_app/features/all_docs/infrastructure/tag_store.dart';\n"
       "import 'package:drawing_notes_app/features/doc/application/doc_export_io.dart';")
assert old in s, 'imp'
s = s.replace(old, new, 1)

old = """    this.onOpenInEdgeless,"""
new = """    this.onOpenInEdgeless,
    this.tagStore,"""
assert s.count(old) == 1, 'ctor'
s = s.replace(old, new, 1)

old = """  final VoidCallback? onOpenInEdgeless;"""
# DocPage 字段（第一个出现）
new = """  final VoidCallback? onOpenInEdgeless;

  /// 标签注册表（M12.6 标签编辑）；null 时内部自建（全局文件）。
  final TagStore? tagStore;"""
assert s.count(old) >= 1, 'field'
s = s.replace(old, new, 1)

# 重写 _showInfoDialog：含标签编辑
old_start = s.index('  void _showInfoDialog(BuildContext context) {')
old_end = s.index('  Widget _infoRow(')
new_dialog = '''  /// 文档信息对话框（含标签编辑——M12.6 标签系统入口）。
  void _showInfoDialog(BuildContext context) {
    final tagStore = widget.tagStore ?? TagStore();
    final title = _doc.title.isEmpty ? '未命名' : _doc.title;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow('创建于', _fmtDate(_doc.createdAt)),
              _infoRow('更新于', _fmtDate(_doc.updatedAt)),
              _infoRow('块数量', '${_doc.body.length}'),
              const SizedBox(height: 12),
              const Text('标签', style: TextStyle(fontWeight: FontWeight.w600)),
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
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
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
    final updated = NoteBlockDoc(
      id: _doc.id,
      title: _doc.title,
      body: _doc.body,
      tags: tags,
      createdAt: _doc.createdAt,
      updatedAt: DateTime.now(),
    );
    setState(() => _doc = updated);
    widget.controller?.save(updated);
    if (context.mounted) Navigator.of(context).pop();
    _showInfoDialog(context);
  }

  /// 快速新建标签（输入名称 → 默认紫色）。
  Future<void> _createTagInline(TagStore tagStore) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建标签'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '标签名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    final tag = await tagStore.addTag(name);
    if (tag != null && !_doc.tags.contains(tag.id)) {
      await _toggleDocTag(tag.id);
    }
  }

'''
s = s[:old_start] + new_dialog + s[old_end:]
io.open(p, 'w', encoding='utf-8', newline='\n').write(s)
print('OK docpage tags')

# ───────── 2. shell：TagStore 实例 + loadTags 注入 ─────────
p = 'lib/app/app_shell.dart'
s = io.open(p, encoding='utf-8').read()

old = "import 'package:drawing_notes_app/features/doc/presentation/trash_page.dart';"
new = ("import 'package:drawing_notes_app/features/all_docs/infrastructure/tag_store.dart';\n"
       "import 'package:drawing_notes_app/features/doc/presentation/trash_page.dart';")
assert old in s, 'shell imp'
s = s.replace(old, new, 1)

old = """  /// 数据版本通知器"""
if old not in s:
    raise SystemExit('shell notifier anchor missing')
# 在 _dataVersion 声明后加 _tagStore —— 找声明行
i = s.index('final ValueNotifier<int> _dataVersion = ValueNotifier(0);')
end = s.index('\n', i) + 1
s = s[:end] + '\n  /// 标签注册表（M12.6）。\n  final TagStore _tagStore = TagStore();\n' + s[end:]

old = """      onOpenTrash: _openTrash,
    ),"""
new = """      onOpenTrash: _openTrash,
      loadTags: _tagStore.listTags,
    ),"""
assert old in s, 'shell wire'
s = s.replace(old, new, 1)
io.open(p, 'w', encoding='utf-8', newline='\n').write(s)
print('OK shell')
