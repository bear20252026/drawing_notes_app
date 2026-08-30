# -*- coding: utf-8 -*-
import io
p = 'lib/features/notes/presentation/note_editor_page.dart'
s = io.open(p, encoding='utf-8').read()

# 1) 滚动控制器字段
old = "  /// 每个块的 LayerLink（key = blockId）——浮动选区工具条锚定用。"
new = """  /// 块列表滚动控制器（大纲跳转用）。
  final ScrollController _listScroll = ScrollController();

  /// Scaffold key（大纲抽屉开合）。
  final GlobalKey<Scaffold> scaffoldKey = GlobalKey();

  /// 每个块的 LayerLink（key = blockId）——浮动选区工具条锚定用。"""
assert old in s, 'f'
s = s.replace(old, new, 1)

# 2) ListView 挂控制器
old = "  Widget _buildBlockList(List<NoteBlock> blocks) {\n    return ListView.builder("
new = "  Widget _buildBlockList(List<NoteBlock> blocks) {\n    return ListView.builder(\n      controller: _listScroll,"
assert old in s, 'lv'
s = s.replace(old, new, 1)

# 3) dispose
old = "    _selectionToolbarOverlay?.remove();\n    _selectionToolbarOverlay = null;"
new = "    _selectionToolbarOverlay?.remove();\n    _selectionToolbarOverlay = null;\n    _listScroll.dispose();"
assert old in s, 'dp'
s = s.replace(old, new, 1)

# 4) AppBar：标题移除（AFFiNE 式标题在正文）
old = """      child: Scaffold(
        appBar: AppBar(
          title: TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              hintText: 'Untitled',
              border: InputBorder.none,
            ),
            style: AppleType.titleStyle(
              Theme.of(context).colorScheme.onSurface,
            ),
          ),
          elevation: 1,"""
new = """      child: Scaffold(
        key: scaffoldKey,
        endDrawer: _buildOutlineDrawer(),
        appBar: AppBar(
          // M11：AFFiNE 式——标题不在 AppBar，而是正文第一个大标题块。
          title: const Text(''),
          elevation: 1,"""
assert old in s, 'appbar'
s = s.replace(old, new, 1)

# 5) AppBar actions 加大纲按钮
old = """            if (widget.onSave != null)
              IconButton(icon: const Icon(Icons.save), onPressed: _manualSave),
          ],"""
new = """            if (widget.onSave != null)
              IconButton(icon: const Icon(Icons.save), onPressed: _manualSave),
            IconButton(
              tooltip: '大纲',
              icon: const Icon(Icons.format_list_bulleted_rounded),
              onPressed: () => scaffoldKey.currentState?.openEndDrawer(),
            ),
          ],"""
assert old in s, 'act'
s = s.replace(old, new, 1)

# 6) 正文插入大标题字段
old = """        body: Column(
          children: [
            Expanded("""
new = """        body: Column(
          children: [
            // AFFiNE 式正文大标题（受控于 _titleController，随 onSave 持久化）
            _buildTitleField(),
            Expanded("""
assert old in s, 'body'
s = s.replace(old, new, 1)

# 7) 大纲方法组 + 标题字段方法（插在 _showExitDialog 前）
old = "  /// 退出未保存提醒对话框。"
new = """  // ── 大纲（Outline，对标 AFFiNE Outline 面板）─────────────────

  /// 按文档顺序抽取所有标题块（含嵌套），供大纲面板展示。
  List<({String id, int level, String text})> outline() {
    final out = <({String id, int level, String text})>[];
    void walk(NoteBlock b) {
      if (b.type == NoteBlockType.heading) {
        out.add((
          id: b.id,
          level: (b.props['level'] as int?)?.clamp(1, 6) ?? 1,
          text: b.text,
        ));
      }
      for (final c in b.children) {
        walk(c);
      }
    }
    for (final b in _root.children) {
      walk(b);
    }
    return out;
  }

  bool _containsId(NoteBlock node, String id) {
    if (node.id == id) return true;
    for (final c in node.children) {
      if (_containsId(c, id)) return true;
    }
    return false;
  }

  /// 大纲点击跳转：按顶层索引估算滚动位置（v1 行高估算）。
  void scrollToBlock(String blockId) {
    final topLevel = _root.children;
    var index = -1;
    for (var i = 0; i < topLevel.length; i++) {
      if (_containsId(topLevel[i], blockId)) {
        index = i;
        break;
      }
    }
    if (index < 0 || !_listScroll.hasClients) return;
    const estimatedExtent = 72.0;
    final target = (index * estimatedExtent)
        .clamp(0.0, _listScroll.position.maxScrollExtent);
    _listScroll.animateTo(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  /// 大纲抽屉面板。
  Widget _buildOutlineDrawer() {
    final entries = outline();
    final scheme = Theme.of(context).colorScheme;
    return Drawer(
      width: 280,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '大纲',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    tooltip: '刷新',
                    icon: const Icon(Icons.refresh, size: 20),
                    onPressed: () => setState(() {}),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: entries.isEmpty
                  ? Center(
                      child: Text(
                        '暂无标题块，用 / 菜单插入「标题」后出现在这里',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: entries.length,
                      itemBuilder: (context, i) {
                        final e = entries[i];
                        return InkWell(
                          onTap: () {
                            scrollToBlock(e.id);
                            Navigator.of(context).pop();
                          },
                          child: Padding(
                            padding: EdgeInsets.only(
                              left: 16 + (e.level - 1) * 16.0,
                              right: 16,
                              top: 8,
                              bottom: 8,
                            ),
                            child: Text(
                              e.text.isEmpty ? '（空标题）' : e.text,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    fontWeight: e.level <= 2
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// AFFiNE 式正文大标题。
  Widget _buildTitleField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: TextField(
        controller: _titleController,
        decoration: const InputDecoration(
          hintText: 'Untitled',
          border: InputBorder.none,
        ),
        style: AppleType.titleStyle(
          Theme.of(context).colorScheme.onSurface,
        ).copyWith(fontSize: 26, fontWeight: FontWeight.w700),
        maxLines: null,
      ),
    );
  }

  /// 退出未保存提醒对话框。"""
assert old in s, 'ol'
s = s.replace(old, new, 1)

io.open(p, 'w', encoding='utf-8', newline='\n').write(s)
print('OK')
