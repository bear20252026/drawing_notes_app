import 'dart:ui' show Color, Offset;

import 'package:drawing_notes_app/core/storage/local_id_generator.dart';
import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';
import 'package:drawing_notes_app/features/drawing/domain/stroke.dart';
import 'package:drawing_notes_app/features/drawing/rendering/shape_recognizer.dart';
import 'package:drawing_notes_app/features/drawing/rendering/stroke_geometry_cache.dart';

/// 笔画输入会话与文档宿主之间的最小协作边界。
///
/// 会话持有活动笔画及其采样生命周期，并决定临时墨迹、激光、形状识别或
/// 普通笔画的提交分支；宿主拥有当前工具配置、持久化文档、命令历史、缓存
/// 刷新和 UI 通知。
abstract interface class StrokeInputHost {
  BrushType get strokeTool;
  Color get strokeColor;
  double get strokeSize;
  bool get temporaryMarkerEnabled;

  void addTemporaryMarker(Stroke stroke);
  void addTemporaryLaser(Stroke stroke, DateTime startedAt);
  Future<void> commitRecognizedShape(Stroke stroke, PageShapeItem shape);
  Future<void> commitPersistentStroke(Stroke stroke);
  void requestFrame();
}

/// 一次原始笔画的起笔、采样、取消和提交会话。
///
/// 所有活动状态只存在于该会话中，未提交笔画不会修改文档、历史或保存状态；
/// 收笔时以完整原始采样替换预览点列，并将持久化工作交给宿主执行。
class StrokeInputSession {
  StrokeInputSession(this._host);

  final StrokeInputHost _host;

  Stroke? _activeStroke;
  StrokeGeometryCache? _activeGeometry;
  DateTime? _activeLaserStartedAt;

  Stroke? get activeStroke => _activeStroke;
  bool get isDrawing => _activeStroke != null;

  void startStroke(Offset canvasPoint, {double pressure = 1.0}) {
    _activeLaserStartedAt = _host.strokeTool == BrushType.laser
        ? DateTime.now()
        : null;
    final first = StrokePoint(canvasPoint.dx, canvasPoint.dy, pressure);
    final geometry = StrokeGeometryCache(first);
    _activeGeometry = geometry;
    _activeStroke = Stroke(
      points: geometry.previewPoints,
      color: _host.strokeTool == BrushType.eraser
          ? const Color(0x00000000)
          : _host.strokeColor,
      width: _host.strokeSize,
      type: _host.strokeTool,
    );
    _host.requestFrame();
  }

  void extendStroke(Offset canvasPoint, {double pressure = 1.0}) {
    final geometry = _activeGeometry;
    if (_activeStroke == null || geometry == null) return;
    geometry.append(StrokePoint(canvasPoint.dx, canvasPoint.dy, pressure));
    _host.requestFrame();
  }

  /// 丢弃尚未提交的活动笔画，仅刷新画布预览。
  void cancelActiveStroke() {
    if (_activeStroke == null) return;
    _clearActiveStroke();
    _host.requestFrame();
  }

  Future<void> endStroke() async {
    final stroke = _activeStroke;
    final geometry = _activeGeometry;
    final laserStartedAt = _activeLaserStartedAt;
    if (stroke == null || geometry == null) return;
    _clearActiveStroke();

    // 收笔改用完整输入采样，递增几何版本以失效渲染路径缓存。
    stroke.replacePoints(geometry.finish());

    if (stroke.type == BrushType.marker && _host.temporaryMarkerEnabled) {
      _host.addTemporaryMarker(stroke);
      _host.requestFrame();
      return;
    }

    if (stroke.type == BrushType.laser) {
      _host.addTemporaryLaser(stroke, laserStartedAt ?? DateTime.now());
      _host.requestFrame();
      return;
    }

    final recognized = ShapeRecognizer.recognize(stroke);
    if (recognized != null) {
      await _host.commitRecognizedShape(
        stroke,
        PageShapeItem(
          id: LocalIdGenerator.next('shape'),
          shapeType: recognized.type,
          x: recognized.bounds.left,
          y: recognized.bounds.top,
          width: recognized.bounds.width,
          height: recognized.bounds.height,
          color: stroke.color.toARGB32(),
          strokeWidth: stroke.width.clamp(1, 20).toDouble(),
          flipX: recognized.flipX,
          flipY: recognized.flipY,
          lineStart: recognized.lineStart,
          lineEnd: recognized.lineEnd,
        ),
      );
      return;
    }

    await _host.commitPersistentStroke(stroke);
  }

  void _clearActiveStroke() {
    _activeStroke = null;
    _activeGeometry = null;
    _activeLaserStartedAt = null;
  }
}
