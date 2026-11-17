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
///
/// VM 双轨收口（R5 连带裁决，业主批准 2026-11-17）：本类此前 extends
/// ChangeNotifier 且每个 setter 都 notifyListeners()，但全库（lib + test 生产
/// 装配）**没有任何订阅者**——页面刷新从来都靠调用方把 VM 调用包进
/// `_applyState`（PR #72 已钉成唯一刷新入口，门禁
/// test/editor_page_setstate_single_entry_test.dart）。死通知轨道整体删除：
/// 本类是**纯状态协作者**，改状态不发通知；可见性由调用方的 `_applyState`
/// 单点负责（VM 状态只被 build 经 getter 读取，整页重建即最新值）。
/// 若将来要给 VM 接 ListenableBuilder，须先过单点门禁评审——不许悄悄
/// 恢复第二刷新轨道。
class EditorViewModel {
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
  // 双轨收口后 setter 只赋状态；调用方负责包 _applyState（见类注释）。

  void setEyedropperActive(bool v) {
    _eyedropperActive = v;
  }

  void setTextToolActive(bool v) {
    _textToolActive = v;
  }

  void setSelectionDone(bool v) {
    _selectionDone = v;
  }

  void setLinkMode(bool v) {
    _linkMode = v;
  }

  void setLinkSourceId(String? v) {
    _linkSourceId = v;
  }

  /// 退出连线模式——`_linkMode` 与它的端点草稿必须成对清，判据只写在这一处。
  ///
  /// 为什么这里要有这个方法，而不是让每个入口自己写 `setLinkMode(false)`：
  /// 连线模式不改 `controller.tool`，它靠 `_linkMode` 接管**元素点击**
  /// （`_onItemTap` 的 `if (_linkMode)` 分支）。EUI-03（审计 2026-10-15）实测
  /// 到 14 格工具条里只有形状/手型/框选三格清了它，画笔系、吸管、矩形选区、
  /// 套索、文字全都没清——工具条与上下文栏两套入口都没清。后果有两半：
  /// ① 工具条的 `writingActive` 因 `!linkMode` 互斥判据一格都不亮，用户看不出
  ///    自己在哪个模式；② 点任何元素仍被当成连线端点，选不中、也切不出去。
  ///
  /// 所以下面每一个 `select*` 意图方法都调用它；editor_page 的十个入口也各自
  /// 显式调一行（宁可多十行，也不要「赋值某个别的标志位就顺手退出连线」这种
  /// 隐式副作用——`toggleLinkMode()` 里「先清吸管、后置 linkMode」的语句顺序
  /// 不该是承重结构）。
  void leaveLinkMode() {
    // 什么都不变时直接返回（幂等守卫保留：成对清的判据仍只写在这一处）。
    if (!_linkMode && _linkSourceId == null) return;
    _linkMode = false;
    _linkSourceId = null;
  }

  // ---------------- 工具切换意图 API ----------------
  // 双轨收口后这组方法生产调用方为零（页面走 editor_page_tools 的
  // _selectWritingTool/_toolMode 路径）；保留为意图 API 的单一判据载体——
  // editor_viewmodel_link_mode_test 逐格钉住「切换必退连线」互斥语义，
  // 将来工具条重构接回这组 API 时判据不丢。

  /// 切到画笔。
  void selectBrush() {
    _eyedropperActive = false;
    _textToolActive = false;
    controller.tool = BrushType.pen;
    leaveLinkMode();
  }

  /// 切到橡皮擦。
  void selectEraser() {
    _eyedropperActive = false;
    _textToolActive = false;
    controller.tool = BrushType.eraser;
    leaveLinkMode();
  }

  /// 进入吸管取色模式。
  void selectEyedropper() {
    _eyedropperActive = true;
    _textToolActive = false;
    leaveLinkMode();
  }

  /// 切到文字工具（点击画布放置文字）。
  void selectText() {
    _textToolActive = true;
    _eyedropperActive = false;
    controller.selectionTool = SelectionTool.none;
    leaveLinkMode();
  }

  /// 切到矩形选区。
  void selectRect() {
    _eyedropperActive = false;
    _textToolActive = false;
    _selectionDone = false;
    controller.selectionTool = SelectionTool.rect;
    leaveLinkMode();
  }

  /// 切到套索选区。
  void selectLasso() {
    _eyedropperActive = false;
    _textToolActive = false;
    _selectionDone = false;
    controller.selectionTool = SelectionTool.lasso;
    leaveLinkMode();
  }

  /// 连线模式开关（D1：依次点选两个元素创建连接）。
  void toggleLinkMode() {
    _linkMode = !_linkMode;
    _linkSourceId = null;
  }

  /// 选区完成后置位（供画布手势回调调用）。
  void markSelectionDone() {
    _selectionDone = true;
  }

  // ---------------- 保存调度（委托 SaveScheduler） ----------------

  /// 改动后最多每 5 秒自动保存一次（[SaveScheduler.autoSaveInterval]）；
  /// 高频手势期间不落盘，无修改时决策器直接 skip。
  void scheduleAutosave() => _saveScheduler.markDirty();

  /// 立即保存并取消防抖。**返回的是落盘结果，不是「一定存好了」**：
  /// 保存失败时链照样收敛（调度器不外抛，见 [SaveFlushResult]），调用方
  /// 必须读 [SaveFlushResult.isSafeToLeave] 再决定是否关闭页面（DN-005）。
  /// 委托给 [SaveScheduler.flush]，获得退出兜底 + 失败重试语义。
  Future<SaveFlushResult> saveNow() => _saveScheduler.flush();

  /// 退出兜底（脏检查版）：无未落盘改动时零等待返回
  /// [SaveFlushOutcome.nothingToSave]。退出路径优先用这个（v1.17.18 退出卡顿
  /// 优化），并同样按结果裁决——[SaveFlushOutcome.failedStillDirty] 意味着
  /// 此刻离开就会丢改动。
  Future<SaveFlushResult> flushIfDirty() => _saveScheduler.flushIfDirty();

  /// 保存链飞行状态（v1.17.20 保存状态指示器）：覆盖防抖/手动/退出兜底
  /// 全部保存路径；UI 侧监听即可，无需在各自 save 回调里手工置位。
  ValueNotifier<bool> get savingState => _saveScheduler.savingState;

  /// 释放保存调度（页面 dispose 调用）。双轨收口后本类无监听器需要清理。
  void dispose() {
    // 已在飞行中的保存链会自然收敛；这里只取消尚未触发的防抖。
    _saveScheduler.dispose();
  }
}