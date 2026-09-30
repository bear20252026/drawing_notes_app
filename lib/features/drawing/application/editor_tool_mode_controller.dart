/// 工具模式互斥状态机 Controller（C-04 第二批）。
///
/// 手型 / 框选 / 形状工具互斥；非形状工具（书写、取色、选区、文字）进入
/// 时清空指针模式。逻辑与原 `EditorToolModeState` 等价，迁到 application
/// 并可被测试独立驱动；页面仍负责同步 DrawingController / ViewModel。
library;

import 'package:flutter/foundation.dart';

import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';

/// 画布工具模式互斥状态。
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
