import 'package:flutter/foundation.dart';

import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/core/saving/save_scheduler.dart';
import 'package:drawing_notes_app/core/canvas_model/selection.dart';
import 'package:drawing_notes_app/core/canvas_model/stroke.dart';

/// 编辑器 ViewModel 胶水层（架构重构 R4，见 docs/ARCHITECTURE_REVISION.md）。
///
/// 职责（View 只显示，ViewModel 调度，Engine/Storage 执行）：
/// - 管理编辑器**工具状态**（吸管/文字/连线/选区完成态）；
/// - 把**保存调度**委托给 [SaveScheduler]（见 P0-3b：防抖/串行化/退出兜底/失败重试）；
/// - 管理**混排对象选中/就地编辑状态**；
/// - 不读写文件、不直接操作图层位图——这些仍由 Storage/Engine 负责。
class EditorViewModel extends ChangeNotifier {
  EditorViewModel({
    required this.controller,
    required SaveScheduler saveScheduler,
  })
    // ignore: prefer_initializing_formals -- 保留公共命名参数，见 P0-3b
    : _saveScheduler = saveScheduler;

  /// 绘图引擎（状态机）。
  final DrawingController controller;

  /// 统一保存门面：防抖、串行化、退出兜底、失败重试都由它编排。
  final SaveScheduler _saveScheduler;

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

  // ---------------- 保存调度（委托 SaveScheduler） ----------------

  /// 停笔后 800ms 自动保存（高频手势期间不落盘；由 [SaveScheduler] 统一去抖）。
  void scheduleAutosave() => _saveScheduler.markDirty();

  /// 立即保存并取消防抖。调用方可 await 该 Future 再安全关闭页面。
  /// 委托给 [SaveScheduler.flush]，获得退出兜底 + 失败重试语义。
  Future<void> saveNow() => _saveScheduler.flush();

  @override
  void dispose() {
    // 已在飞行中的保存链会自然收敛；这里只取消尚未触发的防抖。
    _saveScheduler.dispose();
    super.dispose();
  }
}
