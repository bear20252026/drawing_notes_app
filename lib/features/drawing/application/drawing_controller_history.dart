part of 'drawing_controller.dart';

// 历史/图层管理域（O1 拆分）：撤销重做栈、快照恢复与图层增删
// 改/排序/合并方法从 drawing_controller.dart 移出为 extension；
// 行为零变化。

/// 历史/图层管理域（拆分自 drawing_controller.dart）。
extension DrawingControllerHistoryOps on DrawingController {
  void _pushCommand(DocCommand command) {
    _isDirty = true; // 任何命令入栈 = 文档有未保存修改（保存状态跟踪）。
    markSpatialIndexDirty(); // 标记内容变更，需要重建空间索引
    if (_historyPosition < _history.length) {
      _history.removeRange(_historyPosition, _history.length);
    }
    _history.add(command);
    // 限制历史长度：移除最旧的条目，并校正位置指针。
    if (_history.length > DrawingController.maxHistoryEntries) {
      final overflow = _history.length - DrawingController.maxHistoryEntries;
      _history.removeRange(0, overflow);
      _historyPosition -= overflow;
      if (_historyPosition < 0) _historyPosition = 0;
    }
    _historyPosition = _history.length;
  }

  /// 兼容入口：把快照条目包装为命令（低频操作使用）。
  void _pushHistory(HistoryEntry entry) {
    _pushCommand(SnapshotCommand(this, entry.before, entry.after));
  }

  /// 批量命令原子提交（借鉴 iwb_canvas_engine SceneWriteTxn 思想，
  /// 见 docs/SOURCE_READ_ADAPTATION_REPORT.md）。
  ///
  /// 把多个 [DocCommand] 包装为 [DocumentTransaction] 整体入栈：
  /// - 一次撤销/重做作用于整批命令（原子语义，审计留痕）；
  /// - 执行任一子命令失败时事务自动逆序回滚已执行部分（全部成功或全部回滚）。
  /// 空列表直接忽略（无操作），不产生空事务条目。
  void pushTransaction(List<DocCommand> commands) {
    if (commands.isEmpty) return;
    _pushCommand(DocumentTransaction(commands));
  }

  void undo() {
    if (!canUndo) return;
    _historyPosition--;
    _history[_historyPosition].undo();
  }

  void redo() {
    if (!canRedo) return;
    _history[_historyPosition].redo();
    _historyPosition++;
  }

  // ---------------- 图层操作 ----------------

  /// 新建图层（放在最上层），并自动选中它。
  void addLayer({String? name}) {
    final before = _snapshotLayers();
    final layer = Layer(
      // Q-4 修复（专家审查 2026-08-15）：统一用 LocalIdGenerator——
      // 微秒时间戳在快速连续操作下可能碰撞（批量加图层）。
      id: LocalIdGenerator.next('layer'),
      name: name ?? '图层 ${_document.layers.length + 1}',
    );
    _document.layers.add(layer);
    _document.touch();
    _currentLayerIndex = _document.layers.length - 1;
    _caches[layer.id] = LayerRenderCache();
    _pushHistory(HistoryEntry(before: before, after: _snapshotLayers()));
    _applyNotify();
  }

  /// 删除指定索引的图层。
  void removeLayer(int index) {
    if (_document.layers.length <= 1) return; // 至少保留一个图层
    final before = _snapshotLayers();
    final removed = _document.layers.removeAt(index);
    _caches.remove(removed.id)?.dispose();
    _document.touch();
    if (_currentLayerIndex >= _document.layers.length) {
      _currentLayerIndex = _document.layers.length - 1;
    }
    _pushHistory(HistoryEntry(before: before, after: _snapshotLayers()));
    _applyNotify();
  }

  /// 切换图层显隐。
  void toggleLayerVisibility(int index) {
    final before = _snapshotLayers();
    final layer = _document.layers[index];
    layer.visible = !layer.visible;
    _document.touch();
    _pushHistory(HistoryEntry(before: before, after: _snapshotLayers()));
    _applyNotify();
  }

  /// 设置图层透明度（0~1）。
  void setLayerOpacity(int index, double value) {
    final layer = _document.layers[index];
    if ((layer.opacity - value).abs() < 0.001) return;
    layer.opacity = value.clamp(0.0, 1.0);
    _document.touch();
    _applyNotify();
  }

  /// 上移图层（向更上层移动一格）。
  void moveLayerUp(int index) {
    if (index >= _document.layers.length - 1) return;
    final before = _snapshotLayers();
    final l = _document.layers.removeAt(index);
    _document.layers.insert(index + 1, l);
    _document.touch();
    _currentLayerIndex = index + 1;
    _pushHistory(HistoryEntry(before: before, after: _snapshotLayers()));
    _applyNotify();
  }

  /// 下移图层（向更下层移动一格）。
  void moveLayerDown(int index) {
    if (index <= 0) return;
    final before = _snapshotLayers();
    final l = _document.layers.removeAt(index);
    _document.layers.insert(index - 1, l);
    _document.touch();
    _currentLayerIndex = index - 1;
    _pushHistory(HistoryEntry(before: before, after: _snapshotLayers()));
    _applyNotify();
  }

  /// 向下合并图层：把 [index] 层的内容合并到 index-1 层，并删除 [index] 层。
  void mergeLayerDown(int index) {
    if (index <= 0 || index >= _document.layers.length) return;
    final before = _snapshotLayers();
    final upper = _document.layers[index];
    final lower = _document.layers[index - 1];
    // 笔画顺序：底层原有笔画在前，上层笔画追加在后。
    lower.strokes.addAll(upper.strokes);
    _document.layers.removeAt(index);
    _caches.remove(upper.id)?.dispose();
    _document.touch();
    _currentLayerIndex = index - 1;
    _pushHistory(HistoryEntry(before: before, after: _snapshotLayers()));
    _rebuildAll();
  }

  // ---------------- 画布操作 ----------------

  /// 清空当前图层所有内容。
  void clearCurrentLayer() {
    final before = _snapshotLayers();
    if (currentLayer.strokes.isEmpty) return;
    currentLayer.strokes.clear();
    _document.touch();
    _pushHistory(HistoryEntry(before: before, after: _snapshotLayers()));
    _invalidateLayer(currentLayer.id);
  }

  /// 清空整个文档（所有图层）。
  void clearAll() {
    final before = _snapshotLayers();
    var changed = false;
    for (final l in _document.layers) {
      if (l.strokes.isNotEmpty) {
        l.strokes.clear();
        changed = true;
      }
    }
    if (!changed) return;
    _document.touch();
    _pushHistory(HistoryEntry(before: before, after: _snapshotLayers()));
    _rebuildAll();
  }
}
