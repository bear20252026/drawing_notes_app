// strokes_notifier.dart — 笔画状态 ChangeNotifier（P2 #22 Phase 3 拆分）。
//
// 从 DrawingController 提取的笔画管理：
// - 笔画列表、当前绘制中的笔画、笔画数量
// - 通知图层面板/工具栏等低频 UI

import 'package:flutter/material.dart';
import '../domain/stroke.dart';

/// 笔画状态 ChangeNotifier。
///
/// 笔画列表变更时通知（添加/删除/撤销/重做）。
/// 高频绘制帧不触发通知——使用 frameTick 替代。
class StrokesNotifier extends ChangeNotifier {
  /// 所有笔画列表（由 DrawingController 管理，本类提供只读视图）。
  List<Stroke>? _strokes;

  /// 设置笔画列表引用（DrawingController 调用）。
  void bindStrokes(List<Stroke> strokes) {
    _strokes = strokes;
  }

  /// 当前笔画列表。
  List<Stroke> get strokes => _strokes ?? [];

  /// 笔画总数。
  int get strokeCount => _strokes?.length ?? 0;

  /// 当前正在绘制的笔画（拖动中，尚未提交）。
  Stroke? _currentStroke;
  Stroke? get currentStroke => _currentStroke;

  /// 笔画已添加（从 DrawingController 转发）。
  void onStrokeAdded() {
    notifyListeners();
  }

  /// 笔画已删除（从 DrawingController 转发）。
  void onStrokeRemoved() {
    notifyListeners();
  }

  /// 撤销/重做后通知。
  void onHistoryChanged() {
    notifyListeners();
  }

  /// 当前笔画更新（高频——由 frameTick 处理，不触发 notifyListeners）。
  void onCurrentStrokeUpdated(Stroke stroke) {
    _currentStroke = stroke;
    // 不调用 notifyListeners——高频事件由 frameTick 处理。
  }

  /// 当前笔画提交完成。
  void onCurrentStrokeCommitted() {
    _currentStroke = null;
    notifyListeners();
  }
}
