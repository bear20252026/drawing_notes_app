// 无限画布相机：zoom + pan 值类型（F9 自 edgeless_doc.dart 抽出，2026-09-24）。
// 使用方继续 import edgeless_doc.dart（re-export 兼容）或直接本文件。
import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;
/// 无限画布相机：zoom + pan，负责世界坐标 ↔ 屏幕坐标互转。
///
/// 坐标系约定（严格互逆）：
///   screen = (world - pan) * zoom + viewportCenter
///   world  = (screen - viewportCenter) / zoom + pan
/// 其中 pan 为"映射到视口中心的世界坐标"。
class EdgelessCamera {
  const EdgelessCamera({this.zoom = 1.0, this.panX = 0.0, this.panY = 0.0})
    : assert(zoom > 0, 'zoom must be positive');

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
  EdgelessCamera translated(double dx, double dy) =>
      EdgelessCamera(zoom: zoom, panX: panX + dx, panY: panY + dy);

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
  EdgelessCamera fittedTo(
    Rect worldRect,
    Size viewport, {
    double padding = 40,
  }) {
    final vw = viewport.width - padding * 2;
    final vh = viewport.height - padding * 2;
    if (worldRect.width <= 0 || worldRect.height <= 0) {
      return EdgelessCamera(
        zoom: 1.0,
        panX: worldRect.center.dx,
        panY: worldRect.center.dy,
      );
    }
    final scaleX = vw / worldRect.width;
    final scaleY = vh / worldRect.height;
    final z = math.min(scaleX, scaleY).clamp(0.1, 10.0);
    return EdgelessCamera(
      zoom: z,
      panX: worldRect.center.dx,
      panY: worldRect.center.dy,
    );
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
