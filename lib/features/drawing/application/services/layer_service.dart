import 'dart:ui' show Rect;

import 'drawing_service.dart';

/// Layer operation boundary.
///
/// This service is intentionally host-agnostic. Existing LayerEditingSession
/// remains the implementation during migration; this boundary allows future
/// layer features (plugins, AI operations, batch editing) to avoid coupling to
/// DrawingController.
final class LayerService implements DrawingService {
  LayerService();

  bool _disposed = false;

  bool get isDisposed => _disposed;

  void Function({String? name})? _createLayer;
  void Function(int index)? _deleteLayer;
  void Function(int index)? _toggleVisibility;
  void Function(int index, double value)? _setOpacity;
  void Function(int index)? _moveUp;
  void Function(int index)? _moveDown;
  void Function(int index)? _mergeDown;
  Future<void> Function(String layerId, {Rect? region})? _invalidate;
  void Function(String layerId, int targetIndex)? _reorder;
  void Function()? _beginTransaction;
  void Function()? _commitTransaction;
  void Function()? _rollbackTransaction;

  /// Connects the migration boundary to the existing LayerEditingSession.
  /// The session remains the implementation owner until the next migration step.
  void bindLegacyOperations({
    required void Function({String? name}) createLayer,
    required void Function(int index) deleteLayer,
    void Function(int index)? toggleVisibility,
    void Function(int index, double value)? setOpacity,
    void Function(int index)? moveUp,
    void Function(int index)? moveDown,
    void Function(int index)? mergeDown,
    Future<void> Function(String layerId, {Rect? region})? invalidate,
    void Function(String layerId, int targetIndex)? reorder,
  }) {
    _createLayer = createLayer;
    _deleteLayer = deleteLayer;
    _toggleVisibility = toggleVisibility;
    _setOpacity = setOpacity;
    _moveUp = moveUp;
    _moveDown = moveDown;
    _mergeDown = mergeDown;
    _invalidate = invalidate;
    _reorder = reorder;
  }

  /// 绑定事务宿主钩子（与 [bindLegacyOperations] 分开：图层操作的委托与
  /// 「一批操作如何合成一次撤销」是两种职责，混在一个 12 参数的方法里，
  /// DCM 的 Long Parameter List 只是在替你把设计味道喊出来）。
  void bindTransactionOperations({
    required void Function() beginTransaction,
    required void Function() commitTransaction,
    required void Function() rollbackTransaction,
  }) {
    _beginTransaction = beginTransaction;
    _commitTransaction = commitTransaction;
    _rollbackTransaction = rollbackTransaction;
  }

  /// Future migration entry point for layer invalidation-aware operations.
  Future<void> invalidate(String layerId, {Rect? region}) async {
    if (_disposed) return;
    final operation = _invalidate;
    if (operation == null) throw StateError('Layer invalidation is not bound');
    await operation(layerId, region: region);
  }

  /// Stable entry point for structural layer operations.
  ///
  /// Actual document mutation remains in LayerEditingSession until the next
  /// migration stage. Keeping these names here creates a single API surface for
  /// UI, plugins and future AI operations.
  void createLayer({String? name}) {
    if (_disposed) return;
    _createLayer?.call(name: name);
  }

  void deleteLayer(int index) {
    if (_disposed) return;
    _deleteLayer?.call(index);
  }

  void toggleVisibility(int index) {
    if (_disposed) return;
    _toggleVisibility?.call(index);
  }

  void setOpacity(int index, double value) {
    if (_disposed) return;
    _setOpacity?.call(index, value);
  }

  void moveLayerUp(int index) {
    if (_disposed) return;
    _moveUp?.call(index);
  }

  void moveLayerDown(int index) {
    if (_disposed) return;
    _moveDown?.call(index);
  }

  void mergeLayerDown(int index) {
    if (_disposed) return;
    _mergeDown?.call(index);
  }

  void reorderLayer(String layerId, int targetIndex) {
    if (_disposed) return;
    final operation = _reorder;
    if (operation == null) throw StateError('Layer reordering is not bound');
    operation(layerId, targetIndex);
  }

  // ---------------- 图层事务（一批操作 = 一次撤销） ----------------

  int _transactionDepth = 0;

  /// 是否有事务开着。
  bool get hasOpenLayerTransaction => _transactionDepth > 0;

  /// 开启一批图层操作。语义（交接文档 2026-10-05 第三优先，逐条钉死）：
  ///
  /// - **开始**：窗口内产生的历史命令只累积、不写栈；文档立刻置脏，自动保存
  ///   不会因为「还没提交」而漏掉这期间的编辑；窗口内 undo/redo 一律拒绝。
  /// - **提交**（[commitLayerTransaction]）：窗口内的命令合成**一条**原子条目
  ///   ——一次撤销整批回到 begin 之前，一次重做整批回到提交时；窗口内没有
  ///   任何命令时不产生条目。
  /// - **失败回滚**（[rollbackLayerTransaction]）：逆序 undo 窗口内已执行的命令
  ///   并丢弃它们，历史条目数不变。
  /// - **嵌套**：内层并入外层，只有最外层闭合才提交/回滚。
  /// - **通知合并**：窗口期间宿主的逐次刷新挂起，闭合时补发一次。
  /// - **未配对**：没有开启中的事务就 commit/rollback 直接抛 [StateError]，
  ///   不静默放过（与「未绑定就报错」同一条纪律）。
  void beginLayerTransaction() {
    if (_disposed) return;
    final begin = _beginTransaction;
    if (begin == null) throw StateError('Layer transaction is not bound');
    begin();
    _transactionDepth++;
  }

  void commitLayerTransaction() {
    if (_disposed) return;
    _requireOpen('commit');
    _transactionDepth--;
    // 每次都转发给宿主：宿主侧的分组计数才知道「还有外层没闭合」，
    // 嵌套时它会返回 null、什么都不写（若在此处提前返回，历史侧的
    // 分组计数会永远降不回来，最外层提交也就永不落地）。
    final commit = _commitTransaction;
    if (commit == null) throw StateError('Layer transaction is not bound');
    commit();
  }

  void rollbackLayerTransaction() {
    if (_disposed) return;
    if (_transactionDepth == 0) {
      throw StateError('No layer transaction is open (rollback)');
    }
    _transactionDepth = 0;
    final rollback = _rollbackTransaction;
    if (rollback == null) throw StateError('Layer transaction is not bound');
    rollback();
  }

  void _requireOpen(String action) {
    if (_transactionDepth == 0) {
      throw StateError('No layer transaction is open ($action)');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _transactionDepth = 0;
  }
}
