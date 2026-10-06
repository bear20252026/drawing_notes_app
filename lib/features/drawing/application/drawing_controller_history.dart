part of 'drawing_controller.dart';

/// 通用历史和图层编辑 API 的兼容委托层。
///
/// 命令栈仍由 [HistoryService] 管理；图层变更、快照边界和缓存刷新
/// 编排由 [LayerEditingSession] 持有。该层保留既有控制器 API，避免 UI、
/// 命令和测试调用方在架构收口时发生迁移。
extension DrawingControllerHistoryOps on DrawingController {
  void _pushCommand(DocCommand command) => historyService.push(command);

  void _bindLayerServiceMigration() {
    layerService.bindLegacyOperations(
      createLayer: ({String? name}) =>
          _layerEditingSession.addLayer(name: name),
      deleteLayer: (index) => _layerEditingSession.removeLayer(index),
      toggleVisibility: (index) =>
          _layerEditingSession.toggleLayerVisibility(index),
      setOpacity: (index, value) =>
          _layerEditingSession.setLayerOpacity(index, value),
      moveUp: (index) => _layerEditingSession.moveLayerUp(index),
      moveDown: (index) => _layerEditingSession.moveLayerDown(index),
      mergeDown: (index) => _layerEditingSession.mergeLayerDown(index),
      invalidate: _invalidateLayer,
      reorder: _layerEditingSession.reorderLayer,
      beginTransaction: historyService.beginGroup,
      commitTransaction: _commitLayerTransaction,
      rollbackTransaction: _rollbackLayerTransaction,
    );
  }

  /// 图层事务的宿主侧提交：窗口内累积的命令合成**一条**原子历史条目。
  ///
  /// 走既有的 [pushTransaction]（空窗口不产生条目），撤销=整批回到 begin 之前，
  /// 重做=整批回到提交时；命令此前已执行过，这里只登记，不再重放。
  void _commitLayerTransaction() {
    final commands = historyService.closeGroup();
    if (commands == null) return; // 仍在嵌套中，等最外层闭合
    pushTransaction(commands);
    _flushDeferredNotify();
  }

  /// 图层事务的宿主侧回滚：逆序撤销窗口内已执行的命令并丢弃它们，历史条目数
  /// 不变。用命令自己的 `undo`（与 `DocumentTransaction.undo` 同一语义），
  /// 各命令负责自己的缓存与当前索引校正。
  void _rollbackLayerTransaction() {
    final commands = historyService.discardGroup();
    for (final command in commands.reversed) {
      command.undo();
    }
    _flushDeferredNotify();
  }

  /// 兼容既有基于图层完整快照的历史入口。
  void _pushHistory(HistoryEntry entry) {
    _pushCommand(SnapshotCommand(this, entry.before, entry.after));
  }

  /// 批量命令原子提交。
  ///
  /// 多个 [DocCommand] 作为一条历史记录写入，撤销或重做时保持全有或全无。
  /// 空命令集合不产生历史条目。
  void pushTransaction(List<DocCommand> commands) {
    if (commands.isEmpty) return;
    _pushCommand(DocumentTransaction(commands));
  }

  void undo() => historyService.undo();
  void redo() => historyService.redo();

  void addLayer({String? name}) => layerService.createLayer(name: name);
  void removeLayer(int index) => layerService.deleteLayer(index);
  void toggleLayerVisibility(int index) => layerService.toggleVisibility(index);
  void setLayerOpacity(int index, double value) =>
      layerService.setOpacity(index, value);
  void moveLayerUp(int index) => layerService.moveLayerUp(index);
  void moveLayerDown(int index) => layerService.moveLayerDown(index);
  void mergeLayerDown(int index) => layerService.mergeLayerDown(index);
  void clearCurrentLayer() => _layerEditingSession.clearCurrentLayer();
  void clearAll() => _layerEditingSession.clearAll();
}
