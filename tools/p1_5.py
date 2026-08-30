# -*- coding: utf-8 -*-
import io

p = 'lib/features/doc/doc_page.dart'
s = io.open(p, encoding='utf-8').read()

# 1) SaveScheduler 替换手写 Timer（P1-5 统一保存机制）
old = """  _SaveStatus _saveStatus = _SaveStatus.saved;
  DateTime? _lastSavedAt;
  Timer? _autosaveTimer;
  final GlobalKey<DocEditorState> _editorKey =
      GlobalKey<DocEditorState>();

  @override
  void initState() {
    super.initState();
    _doc = widget.document;
    _favorite = widget.isFavorite;
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    super.dispose();
  }

  /// 编辑变为脏：显示"未保存"并排定 1.2s 防抖自动保存。
  void _onEditorDirty() {
    _autosaveTimer?.cancel();
    if (mounted && _saveStatus != _SaveStatus.unsaved) {
      setState(() => _saveStatus = _SaveStatus.unsaved);
    }
    _autosaveTimer = Timer(const Duration(milliseconds: 1200), _saveNow);
  }

  /// 手动/自动保存入口：状态"保存中" → 编辑器快照落盘 → "已保存 + 时间"。
  Future<void> _saveNow() async {
    _autosaveTimer?.cancel();
    final editor = _editorKey.currentState;
    if (editor == null) return;
    if (mounted) setState(() => _saveStatus = _SaveStatus.saving);
    final doc = editor.saveNow();
    widget.controller?.save(doc);
    if (!mounted) return;
    setState(() {
      _saveStatus = _SaveStatus.saved;
      _lastSavedAt = DateTime.now();
    });
  }"""
new = """  _SaveStatus _saveStatus = _SaveStatus.saved;
  DateTime? _lastSavedAt;
  final GlobalKey<DocEditorState> _editorKey =
      GlobalKey<DocEditorState>();
  late final SaveScheduler _saveScheduler = SaveScheduler(
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
  );

  @override
  void initState() {
    super.initState();
    _doc = widget.document;
    _favorite = widget.isFavorite;
  }

  @override
  void dispose() {
    _saveScheduler.dispose();
    super.dispose();
  }

  /// 编辑变为脏：显示"未保存"并交由 SaveScheduler 防抖自动保存。
  void _onEditorDirty() {
    if (mounted && _saveStatus != _SaveStatus.unsaved) {
      setState(() => _saveStatus = _SaveStatus.unsaved);
    }
    _saveScheduler.markDirty();
  }

  /// 手动保存：立即落盘（保存中 → 已保存 由调度器回调驱动）。
  Future<void> _saveNow() async {
    if (mounted) setState(() => _saveStatus = _SaveStatus.saving);
    await _saveScheduler.saveNow();
  }"""
assert old in s, 'state'
s = s.replace(old, new, 1)

# 2) 移除 dart:async（Timer 不再需要）
s = s.replace("import 'dart:async';\n\n", "")
# 3) 加 save_scheduler 导入
s = s.replace("import 'package:flutter/material.dart';",
              "import 'package:flutter/material.dart';\n\nimport 'package:drawing_notes_app/core/saving/save_scheduler.dart';")

io.open(p, 'w', encoding='utf-8', newline='\n').write(s)
print('OK docpage-save')
