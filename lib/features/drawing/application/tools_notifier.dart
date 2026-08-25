// tools_notifier.dart — 工具状态 ChangeNotifier（P2 #22 Phase 3 拆分）。
//
// 从 DrawingController 提取的工具/笔刷状态管理：
// - 当前工具类型、颜色、粗细、橡皮擦模式
// - 仅通知工具栏等低频 UI 组件
//
// DrawingController 仍持有 ToolsNotifier 实例，工具变更时同步更新并转发通知。

import 'package:flutter/material.dart';
import 'package:drawing_notes_app/features/drawing/application/eraser_mode.dart';
import 'package:drawing_notes_app/features/drawing/domain/stroke.dart';

/// 工具状态 ChangeNotifier。
///
/// 每个工具属性变更仅触发一次通知，不会导致画布局部重绘。
class ToolsNotifier extends ChangeNotifier {
  /// 当前工具类型。
  BrushType _tool = BrushType.pen;
  BrushType get tool => _tool;
  set tool(BrushType value) {
    if (_tool == value) return;
    _tool = value;
    notifyListeners();
  }

  /// 当前画笔颜色。
  Color _color = const Color(0xFF1A1A1A);
  Color get color => _color;
  set color(Color value) {
    _color = value;
    notifyListeners();
  }

  /// 画笔粗细（逻辑像素）。
  double _brushSize = 6.0;
  double get brushSize => _brushSize;
  set brushSize(double value) {
    if (_brushSize == value) return;
    _brushSize = value;
    notifyListeners();
  }

  /// 橡皮擦粗细（逻辑像素）。
  double _eraserSize = 24.0;
  double get eraserSize => _eraserSize;
  set eraserSize(double value) {
    if (_eraserSize == value) return;
    _eraserSize = value;
    // 橡皮擦粗细变更不通知（画布只在使用时读取）。
  }

  /// 橡皮擦模式。
  EraserMode _eraserMode = EraserMode.stroke;
  EraserMode get eraserMode => _eraserMode;
  set eraserMode(EraserMode value) {
    if (_eraserMode == value) return;
    _eraserMode = value;
    notifyListeners();
  }

  /// 画笔不透明度 (0.0–1.0)。
  double _currentToolOpacity = 1.0;
  double get currentToolOpacity => _currentToolOpacity;
  set currentToolOpacity(double value) {
    if (_currentToolOpacity == value) return;
    _currentToolOpacity = value.clamp(0.0, 1.0);
    notifyListeners();
  }

  /// 是否启用激光指示器模式。
  bool _isLaserMode = false;
  bool get isLaserMode => _isLaserMode;
  set isLaserMode(bool value) {
    if (_isLaserMode == value) return;
    _isLaserMode = value;
    notifyListeners();
  }
}
