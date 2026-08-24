// tool_manager.dart — 工具状态管理器（从 DrawingController 提取）。
//
// 职责：管理画笔/橡皮擦工具配置（类型、颜色、粗细、模式）。
// 设计：纯状态容器 + onChange 回调，不依赖 ChangeNotifier。

import 'dart:ui' show Color;

import 'package:drawing_notes_app/features/drawing/application/eraser_mode.dart';
import 'package:drawing_notes_app/features/drawing/domain/stroke.dart';

/// 工具状态管理器。
///
/// 从 DrawingController 的工具状态字段提取：
/// - tool / color / brushSize / eraserSize / eraserMode
/// - currentSize 计算属性
///
/// 使用方式：
/// ```dart
/// final toolManager = ToolManager(onChange: () => notifyListeners());
/// toolManager.setBrushType(BrushType.pen);
/// ```
class ToolManager {
  ToolManager({this.onChange});

  /// 状态变更回调（由 DrawingController 注入 notifyListeners）。
  final void Function()? onChange;

  // ─── 状态字段 ───

  BrushType _tool = BrushType.pen;
  Color _color = const Color(0xFF1A1A1A);
  double _brushSize = 6.0;
  double _eraserSize = 24.0;
  EraserMode _eraserMode = EraserMode.stroke;

  // ─── 只读访问器 ───

  BrushType get tool => _tool;
  Color get color => _color;
  double get brushSize => _brushSize;
  double get eraserSize => _eraserSize;
  EraserMode get eraserMode => _eraserMode;

  /// 当前工具对应的线宽（画笔粗细或橡皮擦粗细）。
  double get currentSize => _tool == BrushType.eraser ? _eraserSize : _brushSize;

  // ─── 写入方法 ───

  set tool(BrushType value) {
    if (_tool == value) return;
    _tool = value;
    onChange?.call();
  }

  set color(Color value) {
    _color = value;
    onChange?.call();
  }

  set brushSize(double value) {
    _brushSize = value;
    onChange?.call();
  }

  set eraserSize(double value) {
    _eraserSize = value;
    onChange?.call();
  }

  set eraserMode(EraserMode value) {
    if (_eraserMode == value) return;
    _eraserMode = value;
    onChange?.call();
  }
}
