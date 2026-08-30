# -*- coding: utf-8 -*-
"""P0-H1/H2：保存链统一 + 退出 flush。
- DocController.save 改 Future（await onSave，不丢盘写）
- 消除自动保存双写（saveNow→_persist 与 scheduler 回调各写一次）
- 「已保存」状态由 scheduler.onSaved 单一驱动（写盘完成后才显示）
- DocPage 包 PopScope：脏状态退出时先 flush 再 pop
"""
import io

# ── 1. DocController：Future 化 ──
p = 'lib/features/doc/doc_controller.dart'
s = io.open(p, encoding='utf-8').read()
old = """  /// 持久化回调（通常接 NoteBlockDocStore.saveDocument）。
  final void Function(NoteBlockDoc doc) onSave;

  bool _dirty = false;

  /// 是否有未持久化的改动。
  bool get dirty => _dirty;

  /// 保存文档。
  void save(NoteBlockDoc doc) {
    onSave(doc);
    _dirty = false;
  }"""
new = """  /// 持久化回调（通常接 NoteBlockDocStore.saveDocument）。
  ///
  /// P0-H1（审计 2026-08-31）：返回 Future 并在 [save] 中 await——
  /// 原实现丢弃 Future，保存失败被静默吞掉，"已保存"状态失真。
  final Future<void> Function(NoteBlockDoc doc) onSave;

  bool _dirty = false;

  /// 是否有未持久化的改动。
  bool get dirty => _dirty;

  /// 保存文档（等待磁盘写完成后才清除脏标记）。
  Future<void> save(NoteBlockDoc doc) async {
    await onSave(doc);
    _dirty = false;
  }"""
if new not in s:  # 幂等
    assert old in s, 'controller'
    s = s.replace(old, new, 1)
io.open(p, 'w', encoding='utf-8', newline='\n').write(s)
print('OK controller')

# ── 2. DocPage：调度回调 await + _persist 去重 + PopScope flush ──
p = 'lib/features/doc/doc_page.dart'
s = io.open(p, encoding='utf-8').read()

old = """  late final SaveScheduler _saveScheduler = SaveScheduler(
    save: () async {
      final editor = _editorKey.currentState;
      if (editor == null) return;
      final doc = editor.saveNow();
      widget.controller?.save(doc);
      _doc = doc;
    },
    onSaved: () {
      if (!mounted) return;
      setState(() {
        _saveStatus = _SaveStatus.saved;
        _lastSavedAt = DateTime.now();
      });
    },
    onError: (e, st) => debugPrint('笔记自动保存失败: $e'),
  );"""
new = """  /// 是否有待写盘改动（P0-H2 退出 flush 判据）。
  bool _pendingChanges = false;

  late final SaveScheduler _saveScheduler = SaveScheduler(
    save: () async {
      final editor = _editorKey.currentState;
      if (editor == null) return;
      final doc = editor.saveNow();
      _doc = doc;
      // P0-H1：等磁盘写完才返回——scheduler.onSaved 在此之后触发，
      // 「已保存」状态不再早于落盘。原实现此处与 _persist 各写一次（双写）。
      await widget.controller?.save(doc);
    },
    onSaved: () {
      if (!mounted) return;
      setState(() {
        _saveStatus = _SaveStatus.saved;
        _lastSavedAt = DateTime.now();
        _pendingChanges = false;
      });
    },
    onError: (e, st) {
      // P0-H1：保存失败必须让用户知道（原仅 debugPrint）。
      if (mounted) {
        setState(() => _saveStatus = _SaveStatus.unsaved);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保存失败，请重试或手动保存')),
        );
      }
    },
  );"""
assert old in s, 'scheduler'
s = s.replace(old, new, 1)

# _onEditorDirty：置 _pendingChanges
old = """  void _onEditorDirty() {
    if (mounted && _saveStatus != _SaveStatus.unsaved) {
      setState(() => _saveStatus = _SaveStatus.unsaved);
    }
    _saveScheduler.markDirty();
  }"""
new = """  void _onEditorDirty() {
    _pendingChanges = true;
    if (mounted && _saveStatus != _SaveStatus.unsaved) {
      setState(() => _saveStatus = _SaveStatus.unsaved);
    }
    _saveScheduler.markDirty();
  }"""
assert old in s, 'dirty'
s = s.replace(old, new, 1)

# _persist：去掉 controller.save 与提前的 saved 状态（P0-H1 单一驱动）
old = """  void _persist(NoteBlockDoc doc) {
    setState(() {
      _doc = doc;
      _saveStatus = _SaveStatus.saved;
      _lastSavedAt = DateTime.now();
    });
    widget.controller?.save(doc);
  }"""
new = """  void _persist(NoteBlockDoc doc) {
    // P0-H1：仅同步快照到页面状态；「已保存」状态与落盘一律由
    // SaveScheduler（await 写盘后的 onSaved）单一驱动，消除假已保存。
    setState(() {
      _doc = doc;
    });
  }"""
assert old in s, 'persist'
s = s.replace(old, new, 1)

# 标签编辑：可 await 的 save
old = """    final updated = _doc.copyWith(tags: tags, updatedAt: DateTime.now());
    setState(() => _doc = updated);
    widget.controller?.save(updated);
    if (context.mounted) Navigator.of(context).pop();
    _showInfoDialog(context);"""
new = """    final updated = _doc.copyWith(tags: tags, updatedAt: DateTime.now());
    setState(() => _doc = updated);
    await widget.controller?.save(updated);
    if (context.mounted) Navigator.of(context).pop();
    _showInfoDialog(context);"""
assert old in s, 'tag save'
s = s.replace(old, new, 1)

# H2：Scaffold 包 PopScope（脏状态退出先 flush）
old = """    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1A1A1E) : Colors.white,
      appBar: _DocHeader("""
new = """    // P0-H2：有未落盘改动时拦截返回，先 flush（saveNow 同步等待写盘）
    // 再真正退出——消除防抖窗口内的编辑丢失。
    return PopScope(
      canPop: !_pendingChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _saveScheduler.saveNow();
        if (mounted) {
          setState(() => _pendingChanges = false);
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
      backgroundColor: isDark ? const Color(0xFF1A1A1E) : Colors.white,
      appBar: _DocHeader("""
assert old in s, 'popscope'
s = s.replace(old, new, 1)

# 闭合 PopScope：build 尾部精确锚点（Row 收尾 + _insertPageLink 文档注释）
old = """          ),
        ],
      ),
    );
  }

  /// 选择目标文档 → 在文末追加 [[标题]] 页面引用（M12.7 反向链接）。"""
new = """          ),
        ],
      ),
      ),
    );
  }

  /// 选择目标文档 → 在文末追加 [[标题]] 页面引用（M12.7 反向链接）。"""
assert s.count(old) == 1, 'close'
s = s.replace(old, new, 1)

io.open(p, 'w', encoding='utf-8', newline='\n').write(s)
print('OK docpage')
