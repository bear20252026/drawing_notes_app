part of 'doc_editor.dart';

// 历史/保存域（O1 拆分自 doc_editor.dart）：历史快照入栈与合帧、脏通知
// 边沿、标题编辑、恢复与根变更应用、手动保存。public API 与字段、静态
// 延迟留在本体。行为零变化。

/// 历史/保存域私有助手（拆分自 doc_editor.dart）。
extension _DocEditorHistory on DocEditorState {

  /// U3 P1-9：静默模型更新后的装饰性刷新。
  ///
  /// build 对 block.text 的依赖是装饰性的（大纲面板条目、空标题提示、
  /// 语义标签）。纯文本击键不再整树 setState，装饰消费方改由本方法
  /// 按 [_cosmeticRefreshDelay] 合帧跟进；结构操作（分块/合并/类型切换）
  /// 仍即时 setState。
  void _scheduleCosmeticRefresh() {
    _cosmeticRefreshDebounce?.cancel();
    _cosmeticRefreshDebounce = Timer(DocEditorState._cosmeticRefreshDelay, () {
      if (mounted)editorSetState(() {});
    });
  }


  /// 提交一次编辑：压入历史栈并标记脏状态（触发宿主自动保存）。
  /// 结构性操作（分块/合并/删除/类型切换/插入引用）走本方法——即时入栈。
  void _commitHistory() {
    _historyDebounce?.cancel();
    _history.push(_buildDocFromState());
    _isDirty = true;
    _notifyDirtyOnce();
  }


  /// P2-M6：文本击键合帧——连续输入只在停顿 [_historyDebounceDelay] 后
  /// 压一次史栈（撤销粒度变为「输入 burst」而非单字符，与主流编辑器
  /// 一致），消除每键全文档深拷贝。脏标记仍即时（自动保存不受影响）。
  void _commitHistoryCoalesced() {
    _historyDebounce?.cancel();
    _historyDebounce = Timer(DocEditorState._historyDebounceDelay, () {
      _history.push(_buildDocFromState());
    });
    _isDirty = true;
    _notifyDirtyOnce();
  }


  /// 边沿触发一次 onDirty（首次脏时通知宿主启动自动保存）。
  void _notifyDirtyOnce() {
    if (_dirtyNotified) return;
    _dirtyNotified = true;
    widget.onDirty?.call();
  }


  /// 把待提交的合帧快照立即入栈（saveNow/结构操作前调用，防丢撤销粒度）。
  void _flushPendingHistory() {
    _historyDebounce?.cancel();
    _history.push(_buildDocFromState());
  }


  void _onTitleEdited() {
    if (_restoring) return;
    if (!_isDirty) {
      _isDirty = true;
      widget.onDirty?.call();
    }
  }


  /// 退出时把编辑后的 NoteBlockDoc 通过 onSave 回调传给调用方。
  void _notifySave() {
    if (!_initialized || widget.onSave == null) return;
    final updatedDoc = _buildDocFromState();
    widget.onSave!(updatedDoc);
  }


  // ── 文档 ↔ 状态 互转 ───────────────────────────────────────

  /// 从 NoteBlockDoc 构建 root 块（title 由 _titleController 持有）。
  NoteBlock _buildRootFromDoc(NoteBlockDoc doc) {
    _ensureBlockResourcesForList(doc.body);
    return NoteBlock(
      id: 'root',
      type: NoteBlockType.text,
      children: List<NoteBlock>.from(doc.body),
    );
  }


  /// 从当前状态重建 NoteBlockDoc。
  NoteBlockDoc _buildDocFromState() {
    return _doc.copyWith(
      title: _titleController.text,
      body: List<NoteBlock>.from(_root.children),
      updatedAt: DateTime.now(),
    );
  }


  /// 从历史快照恢复文档（撤销/重做）。
  ///
  /// 必须重建根树、标题与块资源，并回填仍存在控制器的文本，
  /// 否则 TextField 会显示回滚前的旧文本。恢复期间通过 [_restoring]
  /// 抑制 [_syncText] 的副作用，避免回填 controller.text 反向污染史栈。
  void _restoreDoc(NoteBlockDoc doc) {
    _historyDebounce?.cancel(); // 撤销/重做恢复期间丢弃待提交击键
    final keepIds = _collectAllDocBlockIds(doc);

    // 释放快照中已不存在的块资源。
    final stale = _controllers.keys
        .where((id) => !keepIds.contains(id))
        .toList();
    for (final id in stale) {
      _disposeBlockResources(id);
    }

    _restoring = true;
   editorSetState(() {
      _titleController.text = doc.title;
      _root = _buildRootFromDoc(doc);
      // 回填仍存在控制器的文本，使其与快照一致（同步触发 onChanged，被 _restoring 拦截）。
      void fill(NoteBlock b) {
        _controllers[b.id]?.text = b.text;
        for (final c in b.children) {
          fill(c);
        }
      }

      for (final b in doc.body) {
        fill(b);
      }
      // 聚焦块若已不存在则清空。
      if (_focusedBlockId != null && !keepIds.contains(_focusedBlockId)) {
        _focusedBlockId = null;
      }
    });
    _restoring = false;
    _updateDirtyState();
  }


  /// 应用经 NoteBlockEditor 变换后的新根树：确保资源、置脏、推历史。
  void _applyRootChange(NoteBlock newRoot) {
   editorSetState(() {
      _root = newRoot;
      _ensureBlockResourcesForList(_root.children);
      _updateDirtyState();
    });
    _commitHistory();
  }


  /// 手动触发保存：把当前编辑状态通过 onSave 回调传出。
  Future<void> _manualSave() async {
    if (widget.onSave == null) return;
    final doc = _buildDocFromState();
    // await 落盘结果：失败不置「已保存」，成功才清脏标记。
    try {
      await widget.onSave!(doc);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)?.docSaveFailedRetry ?? '保存失败，请重试',
            ),
          ),
        );
      }
      return;
    }
    if (mounted) {
     editorSetState(() {
        _doc = doc;
        _lastSavedBodySignature = _computeBodySignature();
        _isDirty = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)?.docSavedToast ?? '文档已保存'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }
}
