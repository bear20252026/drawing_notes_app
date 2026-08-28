import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'package:drawing_notes_app/features/drawing/domain/page_image_item.dart';
import 'package:drawing_notes_app/features/drawing/domain/shape_item.dart';

// ---------------------------------------------------------------------------
// 编辑器画布交互短生命周期状态（presentation 层）。
//
// 本文件聚合编辑器在"一次手势/一次交互"内产生的展示态，而非页面可持久化
// 状态。它们均只在 `setState` 中被页面调用变更方法，由页面决定何时通知上层
// 保存，不持有领域数据、不触发 Widget 重建、不落盘。聚合可避免这些暂态
// 分散在组合根及多个 `part` 扩展中，也减少目录文件数逼近结构门禁上限。
// ---------------------------------------------------------------------------

/// 选中内容的缩放与旋转滑块暂态。
///
/// 状态仅服务于展示层控件：它把新的滑块值转换为控制器所需的缩放倍率或旋转
/// 弧度增量。实际对象变换、事务提交、文档通知和持久化仍由 `EditorPage` 协调。
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

/// 编辑器画布工具的短生命周期展示状态。
///
/// 该协作者只维护手型、框选和形状工具之间的互斥规则。页面仍负责在同一
/// `setState` 周期内同步 `DrawingController`、`EditorViewModel`、框选草稿及
/// 实际输入路由，因而不会形成第二个持久化工具状态源。
class EditorToolModeState {
  bool _handActive = false;
  bool _marqueeActive = false;
  ShapeType? _activeShape;

  bool get handActive => _handActive;
  bool get marqueeActive => _marqueeActive;
  ShapeType? get activeShape => _activeShape;

  /// 进入手型模式。返回新状态，便于页面决定是否清理手势暂态。
  bool toggleHand() {
    _handActive = !_handActive;
    _marqueeActive = false;
    _activeShape = null;
    return _handActive;
  }

  /// 进入或切换框选模式。形状和手型模式必然退出。
  bool toggleMarquee() {
    _marqueeActive = !_marqueeActive;
    _handActive = false;
    _activeShape = null;
    return _marqueeActive;
  }

  /// 选择形状工具。手型和框选模式必然退出。
  void selectShape(ShapeType type) {
    _handActive = false;
    _marqueeActive = false;
    _activeShape = type;
  }

  /// 进入非形状的画布工具（书写、取色、选区或文字）。
  void clearPointerModes() {
    _handActive = false;
    _marqueeActive = false;
    _activeShape = null;
  }
}

/// 编辑器画布上混排对象交互的短生命周期状态。
///
/// 该状态不持有页面数据、不执行 Widget 重建，也不负责落盘；页面状态仅在
/// `setState` 中调用它的变更方法，再由页面决定何时通知上层保存。将框选、
/// 多选、裁剪、拖动反馈和对齐反馈收口在此处，可避免这些暂态分散在编辑器
/// 组合根及多个 `part` 扩展中。
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
