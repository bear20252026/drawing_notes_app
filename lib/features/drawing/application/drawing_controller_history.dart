part of 'drawing_controller.dart';

/// 通用历史和图层编辑 API 的兼容委托层。
///
/// 命令栈仍由 [DocumentEditHistory] 管理；图层变更、快照边界和缓存刷新
/// 编排由 [LayerEditingSession] 持有。该层保留既有控制器 API，避免 UI、
/// 命令和测试调用方在架构收口时发生迁移。
extension DrawingControllerHistoryOps on DrawingController {
  void _pushCommand(DocCommand command) => _editHistory.push(command);

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

  void undo() => _editHistory.undo();
  void redo() => _editHistory.redo();

  void addLayer({String? name}) => _layerEditingSession.addLayer(name: name);
  void removeLayer(int index) => _layerEditingSession.removeLayer(index);
  void toggleLayerVisibility(int index) =>
      _layerEditingSession.toggleLayerVisibility(index);
  void setLayerOpacity(int index, double value) =>
      _layerEditingSession.setLayerOpacity(index, value);
  void moveLayerUp(int index) => _layerEditingSession.moveLayerUp(index);
  void moveLayerDown(int index) => _layerEditingSession.moveLayerDown(index);
  void mergeLayerDown(int index) => _layerEditingSession.mergeLayerDown(index);
  void clearCurrentLayer() => _layerEditingSession.clearCurrentLayer();
  void clearAll() => _layerEditingSession.clearAll();
}
