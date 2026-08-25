// stroke_manager.dart — 笔画生命周期管理器（从 DrawingController 提取）。
//
// 职责：管理笔画的创建/延伸/提交/取消，以及对象橡皮擦手势。
// 设计：依赖 ToolManager 获取工具配置，通过回调通知上层。

import 'dart:ui' show Color, Offset;

import 'tool_manager.dart';
import '../domain/stroke.dart';
import '../../../core/rendering/stroke_geometry_cache.dart';

/// 笔画生命周期管理器。
///
/// 从 DrawingController 的笔画绘制逻辑提取：
/// - startStroke / extendStroke / endStroke / cancelActiveStroke
/// - 对象橡皮擦手势（beginObjectErase / eraseStrokesAt / endObjectErase）
///
/// 使用方式：
/// ```dart
/// final strokeManager = StrokeManager(
///   toolManager: toolManager,
///   onStrokeCompleted: (stroke) { /* 提交到图层 */ },
///   onFrameTick: () { /* 触发重绘 */ },
/// );
/// strokeManager.startStroke(point, pressure: 1.0);
/// ```
class StrokeManager {
  StrokeManager({
    required this.toolManager,
    this.onStrokeCompleted,
    this.onFrameTick,
  });

  /// 工具状态管理器（获取当前工具类型/颜色/粗细）。
  final ToolManager toolManager;

  /// 笔画完成回调（提交到图层前调用）。
  final void Function(Stroke stroke)? onStrokeCompleted;

  /// 高频帧通知回调（笔画延伸时触发重绘）。
  final void Function()? onFrameTick;

  // ─── 活动笔画状态 ───

  /// 当前正在绘制中的笔画（未提交到图层，仅用于实时预览）。
  Stroke? _activeStroke;
  Stroke? get activeStroke => _activeStroke;

  /// 一笔的原始采样与实时预览几何。仅在书写期间存在。
  StrokeGeometryCache? _activeGeometry;

  /// 是否正在绘制。
  bool get isDrawing => _activeStroke != null;

  // ─── 笔画生命周期 ───

  /// 开始一笔：创建活动笔画。
  void startStroke(Offset canvasPoint, {double pressure = 1.0}) {
    final first = StrokePoint(canvasPoint.dx, canvasPoint.dy, pressure);
    final geometry = StrokeGeometryCache(first);
    _activeGeometry = geometry;
    _activeStroke = Stroke(
      points: geometry.previewPoints,
      color: toolManager.tool == BrushType.eraser
          ? const Color(0x00000000)
          : toolManager.color,
      width: toolManager.currentSize,
      type: toolManager.tool,
    );
    onFrameTick?.call();
  }

  /// 延伸当前笔画（追加采样点）。
  void extendStroke(Offset canvasPoint, {double pressure = 1.0}) {
    final geometry = _activeGeometry;
    if (_activeStroke == null || geometry == null) return;
    geometry.append(StrokePoint(canvasPoint.dx, canvasPoint.dy, pressure));
    onFrameTick?.call();
  }

  /// 取消当前未提交笔画。
  ///
  /// 用于双指缩放或掌托策略判定为误触时的安全回退。取消动作不会修改图层、
  /// 历史栈、保存点或文档时间戳，只刷新活动笔画预览。
  void cancelActiveStroke() {
    if (_activeStroke == null) return;
    _activeStroke = null;
    _activeGeometry = null;
    onFrameTick?.call();
  }

  /// 结束一笔：构建最终点列并通知上层提交。
  ///
  /// 返回完成的笔画（已从活动状态移除）；如果无活动笔画则返回 null。
  Stroke? endStroke() {
    final s = _activeStroke;
    final geometry = _activeGeometry;
    if (s == null || geometry == null) return null;
    _activeStroke = null;
    _activeGeometry = null;

    // 收笔从完整输入样本构建持久化点列。
    s.replacePoints(geometry.finish());
    if (s.points.length < 2 && s.type != BrushType.eraser) {
      // 孤点（单击未拖动）：仍保留为单个圆点，便于"点一下"产生墨点。
    }

    onStrokeCompleted?.call(s);
    return s;
  }

  /// 释放资源。
  void dispose() {
    _activeStroke = null;
    _activeGeometry = null;
  }
}
