// 无限画布（edgeless）文档模型：note 帧 + 相机（M8-1）。
// 纯 Dart，仅依赖 note_block_doc.dart。
//
// 本文件是 M8-2（note_block_doc_to_frames.dart）的契约层：
// 双方仅通过 NoteFrame / EdgelessCamera 的公开 API 耦合。

import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'package:drawing_notes_app/features/notes/domain/note_block_doc.dart';
import 'package:drawing_notes_app/features/notes/domain/edgeless_connector.dart';

/// 默认帧尺寸。
const double kDefaultFrameWidth = 360;
const double kDefaultFrameHeight = 400;

/// 帧最小尺寸约束。
const double kMinFrameWidth = 120;
const double kMinFrameHeight = 60;

/// 级联偏移：addFrame 无 at 时防重叠。
const double kCascadeOrigin = 80;
const double kCascadeStep = 32;

/// 无限画布相机：zoom + pan，负责世界坐标 ↔ 屏幕坐标互转。
///
/// 坐标系约定（严格互逆）：
///   screen = (world - pan) * zoom + viewportCenter
///   world  = (screen - viewportCenter) / zoom + pan
/// 其中 pan 为"映射到视口中心的世界坐标"。
class EdgelessCamera {
  const EdgelessCamera({
    this.zoom = 1.0,
    this.panX = 0.0,
    this.panY = 0.0,
  }) : assert(zoom > 0, 'zoom must be positive');

  /// 初始相机（zoom=1, pan=0,0）。
  static const EdgelessCamera initial = EdgelessCamera();

  /// 缩放倍率（>0）。
  final double zoom;

  /// 视口中心对应的世界坐标 X。
  final double panX;

  /// 视口中心对应的世界坐标 Y。
  final double panY;

  /// 世界坐标 → 屏幕坐标。
  Offset worldToScreen(Offset world, Size viewport) {
    return Offset(
      (world.dx - panX) * zoom + viewport.width / 2,
      (world.dy - panY) * zoom + viewport.height / 2,
    );
  }

  /// 屏幕坐标 → 世界坐标（worldToScreen 的严格逆）。
  Offset screenToWorld(Offset screen, Size viewport) {
    return Offset(
      (screen.dx - viewport.width / 2) / zoom + panX,
      (screen.dy - viewport.height / 2) / zoom + panY,
    );
  }

  /// 增量平移：pan 增加 (dx, dy)。
  EdgelessCamera translated(double dx, double dy) => EdgelessCamera(
        zoom: zoom,
        panX: panX + dx,
        panY: panY + dy,
      );

  /// 以 [focusWorld] 为锚点缩放 [factor] 倍（锚点屏幕位置不变）。
  /// 无焦点时 pan 不变（绕视口中心缩放）。
  EdgelessCamera zoomedBy(double factor, {Offset? focusWorld}) {
    if (focusWorld == null || factor == 1.0) {
      return EdgelessCamera(zoom: zoom * factor, panX: panX, panY: panY);
    }
    final newZoom = zoom * factor;
    // 锚点屏幕位置不变：(focusWorld.dx - newPanX) * newZoom = (focusWorld.dx - panX) * zoom
    final newPanX = focusWorld.dx - (focusWorld.dx - panX) * zoom / newZoom;
    final newPanY = focusWorld.dy - (focusWorld.dy - panY) * zoom / newZoom;
    return EdgelessCamera(zoom: newZoom, panX: newPanX, panY: newPanY);
  }

  /// 使 [worldRect] 完整可见并居中。zoom 被 clamp 到 [0.1, 10] 防退化。
  EdgelessCamera fittedTo(Rect worldRect, Size viewport, {double padding = 40}) {
    final vw = viewport.width - padding * 2;
    final vh = viewport.height - padding * 2;
    if (worldRect.width <= 0 || worldRect.height <= 0) {
      return EdgelessCamera(
          zoom: 1.0, panX: worldRect.center.dx, panY: worldRect.center.dy);
    }
    final scaleX = vw / worldRect.width;
    final scaleY = vh / worldRect.height;
    final z = math.min(scaleX, scaleY).clamp(0.1, 10.0);
    return EdgelessCamera(zoom: z, panX: worldRect.center.dx, panY: worldRect.center.dy);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EdgelessCamera &&
          runtimeType == other.runtimeType &&
          zoom == other.zoom &&
          panX == other.panX &&
          panY == other.panY;

  @override
  int get hashCode => Object.hash(zoom, panX, panY);

  @override
  String toString() => 'EdgelessCamera(zoom: $zoom, panX: $panX, panY: $panY)';
}

/// 无限画布上的 note 帧：承载一个 NoteBlockDoc 及其在画布上的位置/层级。
class NoteFrame {
  const NoteFrame({
    required this.id,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.doc,
    required this.zIndex,
    this.background = '#FFFFFF',
  });

  /// 帧唯一标识。
  final String id;

  /// 画布 X 坐标。
  final double x;

  /// 画布 Y 坐标。
  final double y;

  /// 帧宽度。
  final double w;

  /// 帧高度。
  final double h;

  /// 帧内块文档。
  final NoteBlockDoc doc;

  /// 层级（越大越靠前）。
  final int zIndex;

  /// 背景色（CSS 颜色字符串）。
  final String background;

  /// 矩形区域（由 x/y/w/h 派生）。
  Rect get rect => Rect.fromLTWH(x, y, w, h);

  /// 中心点。
  Offset get center => rect.center;

  /// 是否包含世界坐标点。
  bool contains(Offset worldPoint) => rect.contains(worldPoint);

  NoteFrame copyWith({
    String? id,
    double? x,
    double? y,
    double? w,
    double? h,
    NoteBlockDoc? doc,
    int? zIndex,
    String? background,
  }) =>
      NoteFrame(
        id: id ?? this.id,
        x: x ?? this.x,
        y: y ?? this.y,
        w: w ?? this.w,
        h: h ?? this.h,
        doc: doc ?? this.doc,
        zIndex: zIndex ?? this.zIndex,
        background: background ?? this.background,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'x': x,
        'y': y,
        'w': w,
        'h': h,
        'doc': doc.toJson(),
        'zIndex': zIndex,
        'background': background,
      };

  factory NoteFrame.fromJson(Map<String, dynamic> json) => NoteFrame(
        id: json['id'] as String,
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        w: (json['w'] as num).toDouble(),
        h: (json['h'] as num).toDouble(),
        doc: NoteBlockDoc.fromJson(json['doc'] as Map<String, dynamic>),
        zIndex: json['zIndex'] as int,
        background: json['background'] as String? ?? '#FFFFFF',
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NoteFrame &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          x == other.x &&
          y == other.y &&
          w == other.w &&
          h == other.h &&
          doc == other.doc &&
          zIndex == other.zIndex &&
          background == other.background;

  @override
  int get hashCode => Object.hash(id, x, y, w, h, doc, zIndex, background);

  @override
  String toString() => 'NoteFrame(id: $id, x: $x, y: $y, w: $w, h: $h, z: $zIndex)';
}

/// Edgeless 文档聚合根：无限画布上的多帧 + 相机 + 选择态。
///
/// 全部操作返回**新 EdgelessDoc**，不修改原实例。
class EdgelessDoc {
  const EdgelessDoc({
    required this.id,
    this.frames = const [],
    this.connectors = const [],
    this.camera = EdgelessCamera.initial,
    this.selectedFrameId,
    this.nextZIndex = 1,
  });

  final String id;
  final List<NoteFrame> frames;

  /// 画布上的连接线集合（1:1 对标 `affine:connector`）。
  final List<NoteConnector> connectors;

  final EdgelessCamera camera;

  /// 当前选中帧 id（可为 null）。
  final String? selectedFrameId;

  /// 下一个待分配的 zIndex。
  final int nextZIndex;

  /// 空文档工厂。[initialDoc] 非空时自动 addFrame 一个。
  factory EdgelessDoc.empty(String id, {NoteBlockDoc? initialDoc}) {
    var doc = EdgelessDoc(id: id);
    if (initialDoc != null) {
      doc = doc.addFrame(initialDoc);
    }
    return doc;
  }

  /// 按 id 查找帧。
  NoteFrame? frameById(String id) {
    for (final f in frames) {
      if (f.id == id) return f;
    }
    return null;
  }

  /// 按 z 升序排列的帧。
  List<NoteFrame> get framesSortedByZ =>
      [...frames]..sort((a, b) => a.zIndex.compareTo(b.zIndex));

  int get _maxZ => frames.isEmpty
      ? 0
      : frames.map((f) => f.zIndex).reduce((a, b) => a > b ? a : b);

  int get _minZ => frames.isEmpty
      ? 0
      : frames.map((f) => f.zIndex).reduce((a, b) => a < b ? a : b);

  /// 添加帧。默认尺寸 360x400；at 空时级联偏移 (80+n*32) 防重叠；分配 nextZIndex++。
  EdgelessDoc addFrame(NoteBlockDoc doc, {Offset? at}) {
    final n = frames.length;
    final topLeft = at ??
        Offset(kCascadeOrigin + n * kCascadeStep, kCascadeOrigin + n * kCascadeStep);
    final frame = NoteFrame(
      id: 'frame_$nextZIndex',
      x: topLeft.dx,
      y: topLeft.dy,
      w: kDefaultFrameWidth,
      h: kDefaultFrameHeight,
      doc: doc,
      zIndex: nextZIndex,
    );
    return EdgelessDoc(
      id: id,
      frames: [...frames, frame],
      connectors: connectors,
      camera: camera,
      selectedFrameId: selectedFrameId,
      nextZIndex: nextZIndex + 1,
    );
  }

  /// 移除帧；若移除的是选中帧则清除选择；同时级联删除所有引用该帧的连接线；
  /// 帧不存在则返回同一实例。
  EdgelessDoc removeFrame(String id) {
    final newFrames = frames.where((f) => f.id != id).toList();
    if (newFrames.length == frames.length) return this;
    return EdgelessDoc(
      id: this.id,
      frames: newFrames,
      connectors: _pruneConnectors(connectors, removedFrameId: id),
      camera: camera,
      selectedFrameId: selectedFrameId == id ? null : selectedFrameId,
      nextZIndex: nextZIndex,
    );
  }

  /// 移动帧左上角到 newTopLeft。
  EdgelessDoc moveFrame(String id, Offset newTopLeft) =>
      _mapFrame(id, (f) => f.copyWith(x: newTopLeft.dx, y: newTopLeft.dy));

  /// 调整帧尺寸（w/h 有最小值约束 120/60）；可选同时移动左上角。
  EdgelessDoc resizeFrame(String id, {Offset? topLeft, double? w, double? h}) =>
      _mapFrame(id, (f) => f.copyWith(
            x: topLeft?.dx,
            y: topLeft?.dy,
            w: w != null ? (w < kMinFrameWidth ? kMinFrameWidth : w) : null,
            h: h != null ? (h < kMinFrameHeight ? kMinFrameHeight : h) : null,
          ));

  /// 设置帧背景色（CSS 颜色字符串，如 '#FFF8E1'）。
  EdgelessDoc setFrameBackground(String id, String background) =>
      _mapFrame(id, (f) => f.copyWith(background: background));

  /// 更新帧内文档。
  EdgelessDoc updateFrameDoc(String id, NoteBlockDoc doc) =>
      _mapFrame(id, (f) => f.copyWith(doc: doc));

  /// 置于顶层：zIndex 设为 maxZ+1，保持其余相对序。
  EdgelessDoc bringToFront(String id) {
    final target = frameById(id);
    if (target == null) return this;
    final newZ = _maxZ + 1;
    if (target.zIndex == newZ) return this;
    return _mapFrame(id, (f) => f.copyWith(zIndex: newZ));
  }

  /// 置于底层：zIndex 设为 minZ-1，保持其余相对序。
  EdgelessDoc sendToBack(String id) {
    final target = frameById(id);
    if (target == null) return this;
    final newZ = _minZ - 1;
    if (target.zIndex == newZ) return this;
    return _mapFrame(id, (f) => f.copyWith(zIndex: newZ));
  }

  /// 选中指定帧（null 取消选择）。
  EdgelessDoc select(String? selectedFrameId) => EdgelessDoc(
        id: id,
        frames: frames,
        connectors: connectors,
        camera: camera,
        selectedFrameId: selectedFrameId,
        nextZIndex: nextZIndex,
      );

  /// 命中测试：返回含 [worldPoint] 的最上层帧（z 最大），无则 null。
  NoteFrame? hitTest(Offset worldPoint) {
    NoteFrame? topmost;
    for (final f in frames) {
      if (f.contains(worldPoint)) {
        if (topmost == null || f.zIndex > topmost.zIndex) topmost = f;
      }
    }
    return topmost;
  }

  /// 按 id 查找连接线。
  NoteConnector? connectorById(String id) {
    for (final c in connectors) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// 两个帧之间是否已存在连接线（忽略方向），防止重复连线。
  bool hasConnectorBetween(String a, String b) => connectors.any(
      (c) => (c.fromFrameId == a && c.toFrameId == b) ||
          (c.fromFrameId == b && c.toFrameId == a));

  /// 添加连接线；自环、缺帧、与端点已存在的重复连线均会被拒绝并返回同一实例。
  /// 未显式指定锚点时按两帧相对位置自动推荐（见 autoConnectorAnchors）。
  EdgelessDoc addConnector({
    required String fromFrameId,
    required String toFrameId,
    ConnectorAnchor? fromAnchor,
    ConnectorAnchor? toAnchor,
    String? color,
    double? width,
    String? label,
  }) {
    final source = frameById(fromFrameId);
    final target = frameById(toFrameId);
    if (source == null || target == null) return this;
    if (fromFrameId == toFrameId) return this;
    if (hasConnectorBetween(fromFrameId, toFrameId)) return this;

    final anchors = (fromAnchor != null && toAnchor != null)
        ? (from: fromAnchor, to: toAnchor)
        : autoConnectorAnchors(source.rect, target.rect);

    final connector = NoteConnector(
      id: 'conn_${connectors.length + 1}',
      fromFrameId: fromFrameId,
      toFrameId: toFrameId,
      fromAnchor: anchors.from,
      toAnchor: anchors.to,
      color: color ?? kDefaultConnectorColor,
      width: width ?? kDefaultConnectorWidth,
      label: label,
    );
    return EdgelessDoc(
      id: id,
      frames: frames,
      connectors: [...connectors, connector],
      camera: camera,
      selectedFrameId: selectedFrameId,
      nextZIndex: nextZIndex,
    );
  }

  /// 移除指定连接线；不存在则返回同一实例。
  EdgelessDoc removeConnector(String id) {
    final retained = connectors.where((c) => c.id != id).toList();
    if (retained.length == connectors.length) return this;
    return EdgelessDoc(
      id: this.id,
      frames: frames,
      connectors: retained,
      camera: camera,
      selectedFrameId: selectedFrameId,
      nextZIndex: nextZIndex,
    );
  }

  EdgelessDoc _mapFrame(String id, NoteFrame Function(NoteFrame) transform) {
    var changed = false;
    final newFrames = frames.map((f) {
      if (f.id != id) return f;
      changed = true;
      return transform(f);
    }).toList();
    if (!changed) return this;
    return EdgelessDoc(
      id: this.id,
      frames: newFrames,
      connectors: connectors,
      camera: camera,
      selectedFrameId: selectedFrameId,
      nextZIndex: nextZIndex,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'frames': frames.map((f) => f.toJson()).toList(),
        'connectors': connectors.map((c) => c.toJson()).toList(),
        'camera': {
          'zoom': camera.zoom,
          'panX': camera.panX,
          'panY': camera.panY,
        },
        'selectedFrameId': selectedFrameId,
        'nextZIndex': nextZIndex,
      };

  factory EdgelessDoc.fromJson(Map<String, dynamic> json) => EdgelessDoc(
        id: json['id'] as String,
        frames: (json['frames'] as List? ?? const [])
            .map((e) => NoteFrame.fromJson(e as Map<String, dynamic>))
            .toList(),
        connectors: (json['connectors'] as List? ?? const [])
            .map((e) => NoteConnector.fromJson(e as Map<String, dynamic>))
            .toList(),
        camera: json['camera'] != null
            ? EdgelessCamera(
                zoom: (json['camera']['zoom'] as num).toDouble(),
                panX: (json['camera']['panX'] as num).toDouble(),
                panY: (json['camera']['panY'] as num).toDouble(),
              )
            : EdgelessCamera.initial,
        selectedFrameId: json['selectedFrameId'] as String?,
        nextZIndex: json['nextZIndex'] as int? ?? 1,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EdgelessDoc &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          _listEquals(frames, other.frames) &&
          _listEquals(connectors, other.connectors) &&
          camera == other.camera &&
          selectedFrameId == other.selectedFrameId &&
          nextZIndex == other.nextZIndex;

  @override
  int get hashCode => Object.hash(id, Object.hashAll(frames),
      Object.hashAll(connectors), camera, selectedFrameId, nextZIndex);

  @override
  String toString() =>
      'EdgelessDoc(id: $id, frames: ${frames.length}, z: $nextZIndex)';
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// 移除一切引用 [removedFrameId] 的连接线（级联清理，防止残留悬空引用）。
List<NoteConnector> _pruneConnectors(
  List<NoteConnector> connectors, {
  required String removedFrameId,
}) =>
    connectors
        .where((c) =>
            c.fromFrameId != removedFrameId && c.toFrameId != removedFrameId)
        .toList();
