/// 编辑器交互状态机 Controllers（C-04 第一/二批合并）。
///
/// 斜杠菜单、指针/压感采样、就地文字会话、工具模式互斥——均属
/// 一次手势/一次会话内的交互状态机，集中本文件以满足
/// `features/drawing/application` 的 sloc-guard 目录文件数上限（40）。
library;

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'package:drawing_notes_app/core/canvas_model/page_chart_item.dart';
import 'package:drawing_notes_app/core/canvas_model/page_image_item.dart';
import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';
import 'package:drawing_notes_app/core/canvas_model/text_item.dart';
import 'package:drawing_notes_app/features/drawing/application/document_commands.dart';
import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/features/drawing/application/text_edit_session_state_machine.dart';

// ── 斜杠命令菜单 ─────────────────────────────────────────────

/// 斜杠命令菜单的交互状态（V-08：↑↓/Enter/Esc 驱动）。
class EditorSlashMenuController extends ChangeNotifier {
  bool _open = false;
  int _highlight = 0;

  bool get open => _open;
  int get highlight => _highlight;

  /// 打开或关闭菜单；打开时高亮归零。
  void setOpen(bool value) {
    if (_open == value) return;
    _open = value;
    if (value) _highlight = 0;
    notifyListeners();
  }

  void close() => setOpen(false);

  /// 强制设置高亮（测试/装配用）。
  void setHighlight(int value) {
    if (_highlight == value) return;
    _highlight = value;
    notifyListeners();
  }

  /// 高亮重置到 0（菜单打开或重新计算命令列表时）。
  void resetHighlight() => setHighlight(0);

  /// 下一项（循环）。
  void moveNext(int itemCount) {
    if (itemCount <= 0) return;
    setHighlight((_highlight + 1) % itemCount);
  }

  /// 上一项（循环）。
  void movePrev(int itemCount) {
    if (itemCount <= 0) return;
    setHighlight((_highlight - 1 + itemCount) % itemCount);
  }

  /// 取当前高亮项；越界时回退到 0 或 null。
  T? selected<T>(List<T> items) {
    if (items.isEmpty) return null;
    return items[_highlight.clamp(0, items.length - 1)];
  }
}

// ── 指针/压感采样 ────────────────────────────────────────────

/// 编辑器指针/压感采样暂态（C-04）。
class EditorPointerSampleState {
  /// 上次拖动位置（画布坐标），用于计算移动增量。
  Offset? lastDragCanvas;

  /// 上次取色时间：pickColorAt 全量重绘的冷却节流锚点。
  DateTime? lastPickColorAt;

  /// 压感笔：上一采样点位置与时间（鼠标速度模拟压感）。
  Offset? lastPenPos;
  DateTime? lastPenTime;

  /// 抬起/取消手势：清空拖动增量基准。
  void resetDrag() {
    lastDragCanvas = null;
  }

  /// 新一轮书写：重置压感采样。
  void resetPen() {
    lastPenPos = null;
    lastPenTime = null;
  }

  /// 记录拖动增量基准。
  void noteDrag(Offset canvasPoint) {
    lastDragCanvas = canvasPoint;
  }

  /// 记录压感采样点。
  void notePen(Offset canvasPoint, DateTime at) {
    lastPenPos = canvasPoint;
    lastPenTime = at;
  }

  /// 标记取色时间（冷却节流）。
  void notePickColor(DateTime at) {
    lastPickColorAt = at;
  }
}

// ── 就地文字编辑会话 ─────────────────────────────────────────

/// 就地文字编辑会话 Controller（C-04 第二批）。
///
/// 包装 [TextEditSessionStateMachine] + 会话字段（editingItemId /
/// pendingTextItem）。页面 part 经 getter 读、经 [beginEdit] /
/// [completeCommit] 写；不持有 Widget / FocusNode / TextEditingController。
class EditorInPlaceTextSessionController extends ChangeNotifier {
  EditorInPlaceTextSessionController({
    TextEditSessionStateMachine? stateMachine,
  }) : _stateMachine = stateMachine ?? TextEditSessionStateMachine();

  final TextEditSessionStateMachine _stateMachine;

  String? _editingItemId;
  PageTextItem? _pendingTextItem;

  /// 纯逻辑阶段（idle/editing/committing/canceling/settled）。
  TextEditSessionPhase get phase => _stateMachine.phase;

  String? get editingItemId => _editingItemId;
  PageTextItem? get pendingTextItem => _pendingTextItem;

  bool get isEditing => _editingItemId != null || _pendingTextItem != null;

  /// 进入就地编辑。若已在编辑中，先按取消语义收掉上一会话。
  TextEditSessionTransition beginEdit({
    required String id,
    required PageTextItem draft,
  }) {
    if (isEditing) {
      _stateMachine.event(TextEditSessionEvent.cancelRequest);
    }
    final transition = _stateMachine.event(TextEditSessionEvent.begin);
    _editingItemId = id;
    _pendingTextItem = draft;
    notifyListeners();
    return transition;
  }

  /// 显式请求提交（回车 / 点外 / 工具切换前）。
  TextEditSessionTransition requestCommit() =>
      _stateMachine.event(TextEditSessionEvent.commitRequest);

  /// 提交成功后调用：清空会话字段并进入 settled。
  TextEditSessionTransition completeCommit() {
    final transition = _stateMachine.event(
      TextEditSessionEvent.commitSucceeded,
    );
    _editingItemId = null;
    _pendingTextItem = null;
    notifyListeners();
    return transition;
  }

  /// 请求取消（不生成历史快照的取消路径）。
  TextEditSessionTransition requestCancel() =>
      _stateMachine.event(TextEditSessionEvent.cancelRequest);

  /// 取消完成后调用：与 completeCommit 同样清空会话。
  TextEditSessionTransition completeCancel() => completeCommit();

  /// 强制回到 idle（页面销毁 / 新建画布时）。
  void reset() {
    _stateMachine.event(TextEditSessionEvent.reset);
    _editingItemId = null;
    _pendingTextItem = null;
    notifyListeners();
  }
}

// ── 工具模式互斥 ─────────────────────────────────────────────

/// 工具模式互斥状态机 Controller（C-04 第二批）。
///
/// 手型 / 框选 / 形状工具互斥；非形状工具（书写、取色、选区、文字）进入
/// 时清空指针模式。页面仍负责同步 DrawingController / ViewModel。
class EditorToolModeController extends ChangeNotifier {
  bool _handActive = false;
  bool _marqueeActive = false;
  ShapeType? _activeShape;

  bool get handActive => _handActive;
  bool get marqueeActive => _marqueeActive;
  ShapeType? get activeShape => _activeShape;

  /// 进入手型模式。返回新状态。
  bool toggleHand() {
    _handActive = !_handActive;
    _marqueeActive = false;
    _activeShape = null;
    notifyListeners();
    return _handActive;
  }

  /// 进入或切换框选模式。返回新状态。
  bool toggleMarquee() {
    _marqueeActive = !_marqueeActive;
    _handActive = false;
    _activeShape = null;
    notifyListeners();
    return _marqueeActive;
  }

  /// 选择形状工具。
  void selectShape(ShapeType type) {
    _handActive = false;
    _marqueeActive = false;
    _activeShape = type;
    notifyListeners();
  }

  /// 进入非形状的画布工具时清空指针模式。
  void clearPointerModes() {
    _handActive = false;
    _marqueeActive = false;
    _activeShape = null;
    notifyListeners();
  }
}

// ── 画布混排对象交互（原 presentation 协作者，迁 application）──

/// 编辑器画布上混排对象交互的短生命周期状态（C-04）。
class EditorCanvasInteractionState {
  String? selectedItemId;
  final Set<String> _multiSelectedIds = <String>{};

  bool marqueeActive = false;
  Rect? marqueeRect;
  Offset? marqueeStart;

  List<({bool vertical, double pos})> _snapGuides =
      <({bool vertical, double pos})>[];
  final List<Offset> _trailPoints = <Offset>[];
  final Set<String> _deletingIds = <String>{};

  PageImageItem? cropItem;
  Rect? cropRect;

  ({double width, double fontSize, double x})? textResizeAnchor;

  /// 进行中的混排拖拽会话（P1 架构收口 2026-11-18）：null = 无手势。
  /// depth/快照/group 三态私有化进 MixedDragSession——外部只经
  /// begin/commit/cancel/abort 操作，三态不可能脱节（此前三裸 public
  /// 字段靠约定同步，三轮审计 H-1/H-2 的根）。
  ///
  /// 第四轮审计缺口 3：会话类从 presentation 下沉本层（原在
  /// editor_page_object_mutation.dart），槽位改强类型——application→presentation
  /// 反向依赖（Object? + 页面侧 cast）消除。
  MixedDragSession? mixedDragSession;

  /// 不可变的多选结果视图；修改必须通过本类的命令方法完成。
  Set<String> get multiSelectedIds =>
      Set<String>.unmodifiable(_multiSelectedIds);

  /// 不可变的当前拖动轨迹视图。
  List<Offset> get trailPoints => List<Offset>.unmodifiable(_trailPoints);

  /// 不可变的当前对齐参考线视图。
  List<({bool vertical, double pos})> get snapGuides =>
      List<({bool vertical, double pos})>.unmodifiable(_snapGuides);

  /// 不可变的当前删除动画目标视图。
  Set<String> get deletingIds => Set<String>.unmodifiable(_deletingIds);

  bool get hasMultiSelection => _multiSelectedIds.isNotEmpty;
  bool get isCropping => cropItem != null && cropRect != null;

  /// 开始框选，并清空上一轮混排对象多选结果。
  void beginMarquee(Offset origin) {
    marqueeStart = origin;
    marqueeRect = Rect.fromPoints(origin, origin);
    clearMultiSelection();
  }

  /// 根据当前指针位置更新框选矩形。
  void updateMarquee(Offset current) {
    final origin = marqueeStart;
    if (origin == null) return;
    marqueeRect = Rect.fromPoints(origin, current);
  }

  /// 提交框选结果并清理草稿；单选状态由页面流程按既有语义决定是否清理。
  void completeMarquee(Iterable<String> itemIds) {
    replaceMultiSelection(itemIds);
    clearMarquee();
  }

  /// 丢弃框选草稿，不改变已完成的选择结果。
  void clearMarquee() {
    marqueeRect = null;
    marqueeStart = null;
  }

  /// 以给定集合替换多选结果。
  void replaceMultiSelection(Iterable<String> itemIds) {
    _multiSelectedIds
      ..clear()
      ..addAll(itemIds);
  }

  /// 将一批项目加入当前多选结果。
  void addToMultiSelection(Iterable<String> itemIds) {
    _multiSelectedIds.addAll(itemIds);
  }

  /// 清理多选结果，而不影响当前单选。
  void clearMultiSelection() => _multiSelectedIds.clear();

  /// 清理单选和多选结果。
  void clearObjectSelection() {
    selectedItemId = null;
    clearMultiSelection();
  }

  /// 记录有限长度的画布拖动轨迹，用于轻量视觉反馈。
  void recordTrail(Offset canvasDelta, {int maxPoints = 8}) {
    _trailPoints.add(canvasDelta);
    if (_trailPoints.length > maxPoints) {
      _trailPoints.removeRange(0, _trailPoints.length - maxPoints);
    }
  }

  /// 清空拖动轨迹：拖拽手势结束（onPanEnd/onPanCancel）必须调用——
  /// 此前无任何清理点，一次拖动结束后 8 点 ghost 轨迹永久残留绘制。
  void clearTrail() => _trailPoints.clear();

  /// 更新本次拖动的对齐参考线。
  void replaceSnapGuides(List<({bool vertical, double pos})> guides) {
    _snapGuides = List<({bool vertical, double pos})>.of(guides);
  }

  void clearSnapGuides() => _snapGuides = <({bool vertical, double pos})>[];

  /// 标记项目进入删除淡出动画。
  void beginDeleting(Iterable<String> itemIds) => _deletingIds.addAll(itemIds);

  /// 移除项目的删除淡出动画标记。
  void finishDeleting(Iterable<String> itemIds) =>
      _deletingIds.removeAll(itemIds);

  /// 进入图片裁剪交互，初始区域为图片当前边界。
  void beginCrop(PageImageItem item) {
    cropItem = item;
    cropRect = Rect.fromLTWH(item.x, item.y, item.width, item.height);
  }

  /// 退出图片裁剪交互。
  void clearCrop() {
    cropItem = null;
    cropRect = null;
  }
}

/// 选中内容的缩放与旋转滑块暂态（C-04）。
class EditorSelectionTransformState {
  double _scaleValue = 1.0;
  double _rotationDegrees = 0.0;

  double get scaleValue => _scaleValue;
  double get rotationDegrees => _rotationDegrees;

  /// 应用新的缩放滑块值并返回相对上次值的倍率。
  double updateScale(double value) {
    final factor = value / _scaleValue;
    _scaleValue = value;
    return factor;
  }

  /// 应用新的旋转滑块值并返回相对上次值的弧度增量。
  double updateRotationDegrees(double value) {
    final delta = (value - _rotationDegrees) * math.pi / 180;
    _rotationDegrees = value;
    return delta;
  }

  /// 在选择被清理或新建时复位控件显示值。
  void reset() {
    _scaleValue = 1.0;
    _rotationDegrees = 0.0;
  }
}

// ── 编辑器壳层 UI 模式（C-04 第三批）────────────────────────

/// 编辑器壳层 UI 模式 Controller（全屏/阅读反相/侧栏面板/网格吸附/命令记忆）。
///
/// 与手势会话状态不同：这些是**会话级 UI 开关**，随页面生命周期保持，
/// 不随单次手势复位。State 经 getter 读、经 toggle/set 写。
class EditorChromeController extends ChangeNotifier {
  /// 深色阅读反相矩阵（问题9修复，仅显示层反相）：标准 RGB 反相保证
  /// 白底→黑、黑墨→白；原 Rec.709 保亮度矩阵会把白色误反相为纯绿。
  static const ColorFilter readingInvertFilter = ColorFilter.matrix(<double>[
    -1,
    0,
    0,
    0,
    255,
    0,
    -1,
    0,
    0,
    255,
    0,
    0,
    -1,
    0,
    255,
    0,
    0,
    0,
    1,
    0,
  ]);

  bool _fullscreen = false;
  bool _readingInverted = false;
  bool _layersVisible = false;
  bool _inspectorVisible = false;
  bool _gridVisible = false;
  bool _snapToGrid = false;
  String? _lastCommandId;

  bool get fullscreen => _fullscreen;
  bool get readingInverted => _readingInverted;
  bool get layersVisible => _layersVisible;
  bool get inspectorVisible => _inspectorVisible;
  bool get gridVisible => _gridVisible;
  bool get snapToGrid => _snapToGrid;
  String? get lastCommandId => _lastCommandId;

  void setFullscreen(bool v) {
    if (_fullscreen == v) return;
    _fullscreen = v;
    notifyListeners();
  }

  bool toggleFullscreen() {
    setFullscreen(!_fullscreen);
    return _fullscreen;
  }

  void setReadingInverted(bool v) {
    if (_readingInverted == v) return;
    _readingInverted = v;
    notifyListeners();
  }

  bool toggleReadingInverted() {
    setReadingInverted(!_readingInverted);
    return _readingInverted;
  }

  void setLayersVisible(bool v) {
    if (_layersVisible == v) return;
    _layersVisible = v;
    notifyListeners();
  }

  bool toggleLayers() {
    setLayersVisible(!_layersVisible);
    return _layersVisible;
  }

  void setInspectorVisible(bool v) {
    if (_inspectorVisible == v) return;
    _inspectorVisible = v;
    notifyListeners();
  }

  bool toggleInspector() {
    setInspectorVisible(!_inspectorVisible);
    return _inspectorVisible;
  }

  void setGridVisible(bool v) {
    if (_gridVisible == v) return;
    _gridVisible = v;
    notifyListeners();
  }

  bool toggleGrid() {
    setGridVisible(!_gridVisible);
    return _gridVisible;
  }

  void setSnapToGrid(bool v) {
    if (_snapToGrid == v) return;
    _snapToGrid = v;
    notifyListeners();
  }

  bool toggleSnapToGrid() {
    setSnapToGrid(!_snapToGrid);
    return _snapToGrid;
  }

  void setLastCommandId(String? id) {
    if (_lastCommandId == id) return;
    _lastCommandId = id;
    notifyListeners();
  }
}

/// 混排对象**拖拽事务会话**（P1 架构收口 2026-11-18，取代静态 Recorder）。
///
/// 三轮审计的根因：depth+group+快照三态靠「记得配对 begin/commit/cancel」
/// 维持——dispose/切页早退漏关组（H-1）、closeGroup 返回值被丢弃吞掉窗口内
/// Delete 命令（H-2）、漏 flush 挂起通知（M-1）。收口为**会话对象**：
///
/// - 会话在 begin 时**捕获四份列表引用与 host**——commit/cancel/abort 不再
///   依赖 widget.session 存活，切页/dispose 照样能关组还原（H-1 构造性消除）。
/// - 关组只经 host.commitGroup()/rollbackGroup() 公开入口——「消费窗口内
///   命令 + 补发挂起通知」是入口的结构保证，会话想丢都丢不掉（H-2/M-1）。
/// - depth/快照是会话私有字段，外部拿不到——三态不可能脱节（裸 public
///   字段 mixedDragDepth/mixedDragBefore 已从交互态移除）。
/// - [abort] 供 dispose 兜底：无论嵌套多深强制还原+回滚，幂等。
///
/// 嵌套语义保留：一次拖拽的指针/键盘路径各自 begin 可嵌套，内层 commit/cancel
/// 只递减；最外层才结算。
///
/// 第四轮审计缺口 3：从 presentation（editor_page_object_mutation.dart）下沉
/// 本层——事务会话属 application 域，不再反向依赖 presentation。
class MixedDragSession {
  MixedDragSession({
    required this.textItems,
    required this.imageItems,
    required this.shapes,
    required this.charts,
    required this.host,
    required this.markDirty,
  });

  /// 会话捕获的四份列表引用（begin 时绑定，commit/cancel/abort 不依赖
  /// 页面存活——H-1 构造性消除的关键）。
  final List<PageTextItem> textItems;
  final List<PageImageItem> imageItems;
  final List<PageShapeItem> shapes;
  final List<PageChartItem> charts;
  final DrawingController host;
  final void Function() markDirty;

  int _depth = 0;
  MixedObjectCollections? _before;
  bool _closed = false;

  /// 会话是否已结算/还原（幂等守卫：panEnd 与 abort 双触发不重复关组）。
  bool get isClosed => _closed;

  /// 手势起点：首层开 history group + 拍起始深快照（嵌套不覆盖基准）。
  void begin() {
    if (_closed) return;
    if (_depth == 0) {
      host.historyService.beginGroup();
      _before = MixedObjectCollections(
        textItems: textItems,
        imageItems: imageItems,
        shapes: shapes,
        charts: charts,
      );
    }
    _depth++;
  }

  /// 手势终点：最外层关组结算，返回 true=会话已闭合（调用方清槽）。
  /// 内层只递减返回 false。窗口内混入的命令经 commitGroup 合成一条事务入栈
  /// ——不再被吞（H-2）。
  bool commit() {
    if (_closed) return true;
    if (_depth > 1) {
      _depth--;
      return false;
    }
    _closed = true;
    _depth = 0;
    final before = _before;
    _before = null;
    // 关组入口保证：消费窗口命令 + flush 挂起通知（H-2/M-1 结构收口）。
    host.commitGroup();
    if (before == null) return true;
    final after = MixedObjectCollections(
      textItems: textItems,
      imageItems: imageItems,
      shapes: shapes,
      charts: charts,
    );
    if (_same(before, after)) return true;
    host.pushCommand(
      MixedObjectsSnapshotCommand(
        textItems: textItems,
        imageItems: imageItems,
        shapes: shapes,
        charts: charts,
        before: before,
        after: after,
        onRestored: () {
          host.invalidateLayer(host.currentLayer.id);
          host.tickFrame();
          markDirty();
        },
      ),
    );
    return true;
  }

  /// 手势取消：最外层回滚窗口命令 + 还原起始快照，不入栈。
  /// 返回 true=会话已闭合。内层只递减（防抹掉外层进行中改动）。
  bool cancel() {
    if (_closed) return true;
    if (_depth > 1) {
      _depth--;
      return false;
    }
    _closed = true;
    _depth = 0;
    final before = _before;
    _before = null;
    // 回滚入口保证：逆序 undo 窗口命令 + flush（Delete 被撤回到位）。
    host.rollbackGroup();
    if (before != null) {
      MixedObjectsSnapshotCommand.restoreCollections(textItems, before.textItems);
      MixedObjectsSnapshotCommand.restoreCollections(imageItems, before.imageItems);
      MixedObjectsSnapshotCommand.restoreCollections(shapes, before.shapes);
      MixedObjectsSnapshotCommand.restoreCollections(charts, before.charts);
    }
    host.invalidateLayer(host.currentLayer.id);
    host.tickFrame();
    return true;
  }

  /// dispose/切页兜底（H-1）：无论嵌套多深强制按取消结算，幂等。
  /// 会话持有列表引用，不依赖页面存活。
  void abort() {
    if (_closed) return;
    _depth = 1; // 压平嵌套，cancel 走最外层路径
    cancel();
  }

  /// 逐字段比对（toJson 串，与 DocumentObjectsSnapshot.isSame 同口径）。
  static bool _same(MixedObjectCollections a, MixedObjectCollections b) {
    bool sameList<T>(List<T> x, List<T> y, String Function(T) json) {
      if (x.length != y.length) return false;
      for (var i = 0; i < x.length; i++) {
        if (json(x[i]) != json(y[i])) return false;
      }
      return true;
    }

    String t(PageTextItem e) => e.toJson().toString();
    String i(PageImageItem e) => e.toJson().toString();
    String s(PageShapeItem e) => e.toJson().toString();
    String c(PageChartItem e) => e.toJson().toString();
    return sameList(a.textItems, b.textItems, t) &&
        sameList(a.imageItems, b.imageItems, i) &&
        sameList(a.shapes, b.shapes, s) &&
        sameList(a.charts, b.charts, c);
  }
}
