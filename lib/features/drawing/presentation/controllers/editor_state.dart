/// 编辑器状态集中管理 — 从 _EditorPageState 拆分出的状态层。
///
/// 将编辑器 UI 相关的状态集中到 [ChangeNotifier] 中，使各子组件
/// 通过 Provider 读写状态，不再依赖 editor_page.dart 的私有成员。
///
/// 架构原则：
/// - 状态与 UI 分离：状态变更通过 [notifyListeners] 通知
/// - 子组件只读：通过 getter 访问状态
/// - 状态修改通过方法：封装业务逻辑，避免外部直接修改字段
library;

import 'package:flutter/material.dart';

import '../../../notes/domain/notebook.dart';

/// 编辑器 UI 状态。
///
/// 集中管理编辑器页面中所有 UI 相关的状态，供子组件通过 Provider 访问。
class EditorState extends ChangeNotifier {
  // ─── 视口状态 ──────────────────────────────────────────────

  bool viewportInitialized = false;
  Size? viewportSize;
  double scaleValue = 1.0;
  double rotateDegrees = 0.0;

  // ─── 工具状态 ──────────────────────────────────────────────

  bool eyedropperActive = false;
  bool textToolActive = false;
  bool selectionDone = false;
  bool linkMode = false;
  String? linkSourceId;
  ShapeType? activeShapeTool;
  bool fillShapeEnabled = false;
  bool marqueeActive = false;
  bool handToolActive = false;
  bool gridVisible = false;
  bool snapToGrid = false;

  // ─── 选择状态 ──────────────────────────────────────────────

  String? selectedItemId;
  final Set<String> multiSelectedIds = {};
  final Set<String> deletingIds = {};

  // ─── 编辑状态 ──────────────────────────────────────────────

  String? editingItemId;
  PageTextItem? pendingTextItem;
  bool slashOpen = false;

  // ─── 显示状态 ──────────────────────────────────────────────

  bool fullscreen = false;
  bool readingInverted = false;
  bool layersVisible = false;
  bool inspectorVisible = false;

  // ─── 拖放状态 ──────────────────────────────────────────────

  bool isDraggingFile = false;

  // ─── 形状草稿 ──────────────────────────────────────────────

  Offset? shapeDraftStart;
  Offset? shapeDraftCurrent;

  // ─── 文字缩放锚点 ──────────────────────────────────────────

  ({double width, double fontSize, double x})? textResizeAnchor;

  // ─── 图片裁剪 ──────────────────────────────────────────────

  PageImageItem? cropItem;
  Rect? cropRect;

  // ─── 框选状态 ──────────────────────────────────────────────

  Rect? marqueeRect;
  Offset? marqueeStart;

  // ─── 对齐参考线 ────────────────────────────────────────────

  List<({bool vertical, double pos})> snapGuides = [];

  // ─── 拖动轨迹 ──────────────────────────────────────────────

  final List<Offset> trailPoints = [];

  // ─── 剪贴板 ────────────────────────────────────────────────

  final List<Map<String, dynamic>> copiedElements = [];
  Map<String, dynamic>? copiedStyle;

  // ─── 命令面板 ──────────────────────────────────────────────

  String? lastCommandId;

  // ─── 状态查询方法 ──────────────────────────────────────────

  /// 是否有对象选中。
  bool get hasObjectSelection =>
      selectedItemId != null || multiSelectedIds.isNotEmpty;

  /// 是否处于多指手势中。
  bool get inPinch => _activePointersCount >= 2;

  int _activePointersCount = 0;

  void setActivePointersCount(int count) {
    _activePointersCount = count;
    notifyListeners();
  }

  /// 当前选中的文字块（需要外部注入 page 引用）。
  PageTextItem? getSelectedTextItem(dynamic page) {
    if (page == null || selectedItemId == null) return null;
    return page.textItems.where((t) => t.id == selectedItemId).firstOrNull;
  }

  /// 当前选中的图片元素（需要外部注入 page 引用）。
  PageImageItem? getSelectedImageItem(dynamic page) {
    if (page == null || selectedItemId == null) return null;
    return page.imageItems.where((i) => i.id == selectedItemId).firstOrNull;
  }

  // ─── 状态修改方法 ──────────────────────────────────────────

  void setEyedropperActive(bool value) {
    eyedropperActive = value;
    notifyListeners();
  }

  void setTextToolActive(bool value) {
    textToolActive = value;
    notifyListeners();
  }

  void setSelectionDone(bool value) {
    selectionDone = value;
    notifyListeners();
  }

  void setLinkMode(bool value) {
    linkMode = value;
    notifyListeners();
  }

  void setLinkSourceId(String? value) {
    linkSourceId = value;
    notifyListeners();
  }

  void setActiveShapeTool(ShapeType? value) {
    activeShapeTool = value;
    notifyListeners();
  }

  void setHandToolActive(bool value) {
    handToolActive = value;
    notifyListeners();
  }

  void setFullscreen(bool value) {
    fullscreen = value;
    notifyListeners();
  }

  void setReadingInverted(bool value) {
    readingInverted = value;
    notifyListeners();
  }

  void setLayersVisible(bool value) {
    layersVisible = value;
    notifyListeners();
  }

  void setInspectorVisible(bool value) {
    inspectorVisible = value;
    notifyListeners();
  }

  void setSelectedItem(String? id) {
    selectedItemId = id;
    notifyListeners();
  }

  void toggleGrid() {
    gridVisible = !gridVisible;
    notifyListeners();
  }

  void toggleSnapToGrid() {
    snapToGrid = !snapToGrid;
    notifyListeners();
  }

  void clearSelection() {
    selectedItemId = null;
    multiSelectedIds.clear();
    notifyListeners();
  }

  void setMarqueeActive(bool value) {
    marqueeActive = value;
    notifyListeners();
  }

  void setShapeDraft(Offset? start, Offset? current) {
    shapeDraftStart = start;
    shapeDraftCurrent = current;
    notifyListeners();
  }

  void setCropTarget(PageImageItem? item, Rect? rect) {
    cropItem = item;
    cropRect = rect;
    notifyListeners();
  }

  void setEditingItem(String? id) {
    editingItemId = id;
    notifyListeners();
  }

  void setPendingTextItem(PageTextItem? item) {
    pendingTextItem = item;
    notifyListeners();
  }

  void setSlashOpen(bool value) {
    slashOpen = value;
    notifyListeners();
  }

  void setTextResizeAnchor(({double width, double fontSize, double x})? anchor) {
    textResizeAnchor = anchor;
    notifyListeners();
  }

  void setDraggingFile(bool value) {
    isDraggingFile = value;
    notifyListeners();
  }

  void setViewportSize(Size size) {
    viewportSize = size;
    notifyListeners();
  }

  void setScaleValue(double value) {
    scaleValue = value;
    notifyListeners();
  }

  void setRotateDegrees(double value) {
    rotateDegrees = value;
    notifyListeners();
  }

  void setMarqueeRect(Rect? rect) {
    marqueeRect = rect;
    notifyListeners();
  }

  void setMarqueeStart(Offset? start) {
    marqueeStart = start;
    notifyListeners();
  }

  void setSnapGuides(List<({bool vertical, double pos})> guides) {
    snapGuides = guides;
    notifyListeners();
  }

  void setLastCommandId(String? id) {
    lastCommandId = id;
    notifyListeners();
  }

  void addTrailPoint(Offset point) {
    trailPoints.add(point);
    if (trailPoints.length > 50) {
      trailPoints.removeAt(0);
    }
    notifyListeners();
  }

  void clearTrail() {
    trailPoints.clear();
    notifyListeners();
  }

  void addMultiSelectedId(String id) {
    multiSelectedIds.add(id);
    notifyListeners();
  }

  void removeMultiSelectedId(String id) {
    multiSelectedIds.remove(id);
    notifyListeners();
  }

  void markDeleting(String id) {
    deletingIds.add(id);
    notifyListeners();
  }

  void unmarkDeleting(String id) {
    deletingIds.remove(id);
    notifyListeners();
  }

  void setCopiedElements(List<Map<String, dynamic>> elements) {
    copiedElements.clear();
    copiedElements.addAll(elements);
    notifyListeners();
  }

  void setCopiedStyle(Map<String, dynamic>? style) {
    copiedStyle = style;
    notifyListeners();
  }
}
