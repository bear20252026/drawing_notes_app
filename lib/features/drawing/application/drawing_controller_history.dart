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
    );
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
