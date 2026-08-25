import 'dart:async';

import 'package:flutter/foundation.dart';

import '../application/drawing_controller.dart';
import '../domain/selection.dart';
import '../domain/stroke.dart';
import '../domain/text_item.dart';

/// 编辑器 ViewModel 胶水层（架构重构 R4，见 docs/ARCHITECTURE_REVISION.md）。
///
/// 职责（View 只显示，ViewModel 调度，Engine/Storage 执行）：
/// - 管理编辑器**工具状态**（吸管/文字/连线/选区完成态）；
/// - 管理**防抖自动保存**（2s 停笔后触发 onSave，避免高频落盘）；
/// - 管理**混排对象选中/就地编辑状态**；
/// - 不读写文件、不直接操作图层位图——这些仍由 Storage/Engine 负责。
class EditorViewModel extends ChangeNotifier {
  EditorViewModel({required this.controller, this.onSave});

  /// 绘图引擎（状态机）。
  final DrawingController controller;

  /// 自动保存回调（由上级页面落盘）。
  final Future<void> Function()? onSave;

  /// 自动保存防抖时长：停笔 800ms 后触发保存。
  ///
  /// 与 editor_page 原实现保持一致（R4 接入保持行为不变）；
  /// 未来如需更省 IO 可上调，无需改动调用方。
  static const Duration autosaveDelay = Duration(milliseconds: 800);

  // ---------------- 工具状态 ----------------

  bool _eyedropperActive = false;
  bool _textToolActive = false;
  bool _linkMode = false;
  String? _linkSourceId;
  bool _selectionDone = false;

  bool get eyedropperActive => _eyedropperActive;
  bool get textToolActive => _textToolActive;
  bool get linkMode => _linkMode;
  String? get linkSourceId => _linkSourceId;
  bool get selectionDone => _selectionDone;

  // ---------------- 混排对象状态 ----------------

  String? _selectedItemId;
  String? _editingItemId;
  PageTextItem? _pendingTextItem;

  String? get selectedItemId => _selectedItemId;
  String? get editingItemId => _editingItemId;
  PageTextItem? get pendingTextItem => _pendingTextItem;

  // ---------------- 细粒度状态 setter（供 editor_page 委托接入） ----------------

  void setEyedropperActive(bool v) {
    _eyedropperActive = v;
    notifyListeners();
  }

  void setTextToolActive(bool v) {
    _textToolActive = v;
    notifyListeners();
  }

  void setSelectionDone(bool v) {
    _selectionDone = v;
    notifyListeners();
  }

  void setLinkMode(bool v) {
    _linkMode = v;
    notifyListeners();
  }

  void setLinkSourceId(String? v) {
    _linkSourceId = v;
    notifyListeners();
  }

  // ---------------- 工具切换（UI 只调用这些方法） ----------------

  /// 切到画笔。
  void selectBrush() {
    _eyedropperActive = false;
    _textToolActive = false;
    controller.tool = BrushType.pen;
    notifyListeners();
  }

  /// 切到橡皮擦。
  void selectEraser() {
    _eyedropperActive = false;
    _textToolActive = false;
    controller.tool = BrushType.eraser;
    notifyListeners();
  }

  /// 进入吸管取色模式。
  void selectEyedropper() {
    _eyedropperActive = true;
    _textToolActive = false;
    notifyListeners();
  }

  /// 切到文字工具（点击画布放置文字）。
  void selectText() {
    _textToolActive = true;
    _eyedropperActive = false;
    controller.selectionTool = SelectionTool.none;
    notifyListeners();
  }

  /// 切到矩形选区。
  void selectRect() {
    _eyedropperActive = false;
    _textToolActive = false;
    _selectionDone = false;
    controller.selectionTool = SelectionTool.rect;
    notifyListeners();
  }

  /// 切到套索选区。
  void selectLasso() {
    _eyedropperActive = false;
    _textToolActive = false;
    _selectionDone = false;
    controller.selectionTool = SelectionTool.lasso;
    notifyListeners();
  }

  /// 连线模式开关（D1：依次点选两个元素创建连接）。
  void toggleLinkMode() {
    _linkMode = !_linkMode;
    _linkSourceId = null;
    notifyListeners();
  }

  /// 选区完成后置位（供画布手势回调调用）。
  void markSelectionDone() {
    _selectionDone = true;
    notifyListeners();
  }

  /// 退出吸管/文字模式（点击画布其他位置时）。
  void clearTools() {
    _eyedropperActive = false;
    _textToolActive = false;
    notifyListeners();
  }

  // ---------------- 混排对象 ----------------

  void selectItem(String id) {
    _selectedItemId = id;
    notifyListeners();
  }

  void clearSelection() {
    _selectedItemId = null;
    notifyListeners();
  }

  void startEditing(String id, PageTextItem pending) {
    _editingItemId = id;
    _pendingTextItem = pending;
    notifyListeners();
  }

  void finishEditing() {
    _editingItemId = null;
    _pendingTextItem = null;
    notifyListeners();
  }

  // ---------------- 防抖自动保存 ----------------

  Timer? _autosaveTimer;

  /// 停笔后 2 秒自动保存（高频手势期间不落盘）。
  void scheduleAutosave() {
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(autosaveDelay, () {
      _autosaveTimer = null;
      final save = onSave?.call();
      if (save != null) unawaited(save);
    });
  }

  /// 立即保存并取消未触发的防抖。调用方可 await 该 Future 再安全关闭页面。
  Future<void> saveNow() async {
    _autosaveTimer?.cancel();
    _autosaveTimer = null;
    await onSave?.call();
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _autosaveTimer = null;
    super.dispose();
  }
}
