import 'dart:ui' show Offset, Rect;

import 'package:drawing_notes_app/features/drawing/domain/page_image_item.dart';

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
