// 由 Claude 团队生成 | Drawing Notes App
// EdgelessController：Edgeless 无限画布的展示层控制器。
//
// 持有 EdgelessDoc（模型）+ 活动相机（EdgelessCamera），并把画布手势（平移/
// 缩放/拖帧/选中）翻译成对 EdgelessDoc 的不可变操作。依赖 M8-1 的
// edgeless_doc.dart（EdgelessDoc / EdgelessCamera / NoteFrame），不 import drawing。
//
// 手势语义（1:1 AFFiNE）：
//  - 单指按在空处拖动         → 平移相机
//  - 单指按在某个 note 帧拖动 → 移动该帧
//  - 双指捏合                → 以焦点为锚缩放
//  - 点按空白                → 取消选择；点按帧 → 选中并置顶

import 'package:flutter/widgets.dart';

import 'package:drawing_notes_app/features/notes/domain/edgeless_doc.dart';
import 'package:drawing_notes_app/features/notes/domain/note_block_doc.dart';

/// Edgeless 画布控制器（ChangeNotifier）。
class EdgelessController extends ChangeNotifier {
  EdgelessController({
    required EdgelessDoc doc,
    this.onChanged,
    this.minZoom = 0.1,
    this.maxZoom = 5.0,
  })  : _doc = doc,
        _camera = doc.camera;

  EdgelessDoc _doc;
  final void Function(EdgelessDoc doc)? onChanged;
  final double minZoom;
  final double maxZoom;
  EdgelessCamera _camera;

  // 手势暂存
  EdgelessCamera? _gestureStartCamera;
  Offset? _gestureStartFocal;
  String? _dragFrameId;
  Offset _dragStartTopLeft = Offset.zero;
  bool _gestureActive = false;

  EdgelessDoc get doc => _doc;
  EdgelessCamera get camera => _camera;
  String? get selectedFrameId => _doc.selectedFrameId;
  bool get gestureActive => _gestureActive;

  /// 内部：应用新 doc（不可变），仅在真正变化时触发 onChanged + notify。
  void _setDoc(EdgelessDoc next) {
    if (next == _doc) return;
    _doc = next;
    onChanged?.call(next);
    notifyListeners();
  }

  // ── 相机 ────────────────────────────────────────────────────

  /// 平移（世界坐标增量）。
  void panByWorld(double dxWorld, double dyWorld) {
    _camera = _camera.translated(dxWorld, dyWorld);
    _notifyCamera();
  }

  /// 以 [focusWorld]（世界坐标）为锚缩放 [factor] 倍。
  void zoomAt(double factor, {Offset? focusWorld}) {
    var target = _camera.zoomedBy(factor, focusWorld: focusWorld);
    target = _clampZoom(target);
    _camera = target;
    _notifyCamera();
  }

  /// fit-to-screen：使 [worldRect] 在 [viewport] 内完整可见居中。
  void fitTo(Rect worldRect, Size viewport, {double padding = 32}) {
    _camera = _clampZoom(_camera.fittedTo(worldRect, viewport, padding: padding));
    _notifyCamera();
  }

  void _notifyCamera() {
    notifyListeners();
  }

  EdgelessCamera _clampZoom(EdgelessCamera cam) {
    if (cam.zoom < minZoom || cam.zoom > maxZoom) {
      final z = cam.zoom.clamp(minZoom, maxZoom).toDouble();
      return EdgelessCamera(zoom: z, panX: cam.panX, panY: cam.panY);
    }
    return cam;
  }

  // ── 手势入口（由 Widget 的 GestureDetector 转发）─────────────

  /// 手势开始。单指落点命中帧则进入拖帧模式。
  void beginGesture(Offset localFocal, int pointerCount, Size viewport) {
    _gestureStartCamera = _camera;
    _gestureStartFocal = localFocal;
    _dragFrameId = null;
    _gestureActive = true;
    if (pointerCount == 1) {
      final world = _camera.screenToWorld(localFocal, viewport);
      final frame = _doc.hitTest(world);
      if (frame != null) {
        _dragFrameId = frame.id;
        _dragStartTopLeft = Offset(frame.x, frame.y);
      }
    }
  }

  /// 手势更新。[scale] 为从手势开始起的累计相对缩放（起点 1.0）。
  void updateGesture(Offset localFocal, double scale, int pointerCount, Size viewport) {
    if (!_gestureActive) return;
    if (pointerCount >= 2) {
      _dragFrameId = null; // 进入缩放，取消拖帧
    }
    if (_dragFrameId != null && pointerCount == 1) {
      // 拖帧：相机不变，按屏幕增量换算世界增量移动帧。
      final screenDelta = localFocal - (_gestureStartFocal ?? localFocal);
      final worldDelta = screenDelta / _camera.zoom;
      _setDoc(_doc.moveFrame(_dragFrameId!, _dragStartTopLeft + worldDelta));
      return;
    }
    // 平移/缩放相机：以手势起点的焦点世界点作为固定锚，让该世界点始终落在当前焦点下。
    final startCam = _gestureStartCamera;
    final startFocal = _gestureStartFocal;
    final anchorWorld = startCam?.screenToWorld(startFocal ?? localFocal, viewport);
    if (anchorWorld == null) return;
    final newZoom = (startCam!.zoom * scale).clamp(minZoom, maxZoom).toDouble();
    final center = Offset(viewport.width / 2, viewport.height / 2);
    final newCam = EdgelessCamera(
      zoom: newZoom,
      panX: anchorWorld.dx - (localFocal.dx - center.dx) / newZoom,
      panY: anchorWorld.dy - (localFocal.dy - center.dy) / newZoom,
    );
    _camera = newCam;
    _notifyCamera();
  }

  /// 手势结束，清空暂存。
  void endGesture() {
    _gestureActive = false;
    _dragFrameId = null;
    _gestureStartCamera = null;
    _gestureStartFocal = null;
  }

  // ── 选中 ────────────────────────────────────────────────────

  /// 点按某屏幕点：命中帧 → 选中并置顶；否则取消选中。
  void tapAt(Offset localFocal, Size viewport) {
    final world = _camera.screenToWorld(localFocal, viewport);
    final frame = _doc.hitTest(world);
    if (frame == null) {
      _setDoc(_doc.select(null));
    } else {
      var next = _doc.select(frame.id);
      if (next.selectedFrameId != null) {
        next = next.bringToFront(frame.id);
      }
      _setDoc(next);
    }
  }

  // ── 帧操作 ──────────────────────────────────────────────────

  /// 新增一帧（可选世界坐标位置）。
  void addFrame(NoteBlockDoc blockDoc, {Offset? at}) {
    _setDoc(_doc.addFrame(blockDoc, at: at));
  }

  /// 移除一帧。
  void removeFrame(String id) {
    _setDoc(_doc.removeFrame(id));
  }

  /// 替换整个文档（例：离开编辑后刷新）。
  void replaceDoc(EdgelessDoc next) {
    _setDoc(next);
  }

  /// 更新某帧内的文档（例：双击进入编辑器后写回）。
  void updateFrameDoc(String id, NoteBlockDoc doc) {
    _setDoc(_doc.updateFrameDoc(id, doc));
  }

  // ── 坐标换算 ────────────────────────────────────────────────

  Offset worldToScreen(Offset world, Size viewport) => _camera.worldToScreen(world, viewport);
  Offset screenToWorld(Offset screen, Size viewport) => _camera.screenToWorld(screen, viewport);

  /// 命中测试（世界坐标）。
  NoteFrame? hitTest(Offset worldPoint) => _doc.hitTest(worldPoint);

  /// 所有帧按 z 升序。
  List<NoteFrame> get framesSortedByZ => _doc.framesSortedByZ;
}
