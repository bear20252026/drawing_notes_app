part of 'drawing_controller.dart';

/// 通用历史和图层编辑 API 的兼容委托层。
///
/// 命令栈仍由 [HistoryService] 管理；图层变更、快照边界和缓存刷新
/// 编排由 [LayerEditingSession] 持有。该层保留既有控制器 API，避免 UI、
/// 命令和测试调用方在架构收口时发生迁移。
extension DrawingControllerHistoryOps on DrawingController {
  void _pushCommand(DocCommand command) {
    historyService.push(command);
    // Operation Engine（2026-10-11）：命令提交点成对记录语义操作。
    // 命令栈仍是撤销权威；null = 形状/图片/快照桥接类不进操作流。
    //
    // DRW-08：分组窗口开着时**不记**单条。窗口闭合时整批会以一个 `OpBatch`
    // 记一次（`DocumentTransaction.operation` 就是子命令的 op 聚合），在这里
    // 也记就是**同一批 op 落两遍**；回滚那条腿更糟——`command.undo()` 撤得掉
    // 文档改动，撤不掉已经写进会话日志的 op，磁盘侧车会留下一段从没生效过的
    // 操作。还有一处顺带修掉：窗口内混进一条不可表达的命令（形状/图片/快照）时，
    // 旧写法会记下半批 op，而 `DocumentTransaction.operation` 故意返回 null
    // ——「部分记录」正是那句注释禁止的形状。
    if (historyService.isGroupOpen) return;
    final op = command.operation;
    if (op != null) {
      operationLog.record(op);
    }
  }

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
    layerService.bindTransactionOperations(
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

  /// 事务窗口的**公开提交入口**（P1 架构收口 2026-11-18）：关组 + 消费
  /// 窗口内命令 + 补发挂起通知，与图层事务 _commitLayerTransaction 同语义。
  ///
  /// 为什么必须公开：三轮审计 H-1/H-2 的根因是 presentation 层的事务
  /// 记录器摸不到私有的 _flushDeferredNotify，自己调 historyService.closeGroup
  /// 又丢弃返回值——聚焦手柄期间 Delete 冒泡 push 的命令被吞（删除撤不回
  /// +自动落盘）、挂起通知永不补发。收口后**任何事务关组只经此入口**，
  /// 「消费返回值+flush」成为结构保证而非约定。不经 layerService 通道
  /// （其 _transactionDepth 是图层专属计数，借用会撕裂）。
  ///
  /// 返回是否真正闭合了最外层窗口（嵌套中返回 false，调用方据此不结算）。
  bool commitGroup() {
    final commands = historyService.closeGroup();
    if (commands == null) return false; // 仍在嵌套中，等最外层闭合
    if (commands.isNotEmpty) pushTransaction(commands);
    _flushDeferredNotify();
    return true;
  }

  /// 事务窗口的**公开回滚入口**（P1 架构收口）：拆全部嵌套层、逆序撤销
  /// 窗口内已执行命令、补发挂起通知——与 _rollbackLayerTransaction 同语义。
  void rollbackGroup() {
    final commands = historyService.discardGroup();
    for (final command in commands.reversed) {
      command.undo();
    }
    _flushDeferredNotify();
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

  /// 结束一次透明度滑块调整：提交可撤销窄命令（与显隐/换位同口径）。
  void settleLayerOpacity(int index) =>
      _layerEditingSession.settleLayerOpacity(index);
  void moveLayerUp(int index) => layerService.moveLayerUp(index);
  void moveLayerDown(int index) => layerService.moveLayerDown(index);
  void mergeLayerDown(int index) => layerService.mergeLayerDown(index);
  void clearCurrentLayer() => _layerEditingSession.clearCurrentLayer();
  void clearAll() => _layerEditingSession.clearAll();
}
