import 'package:test/test.dart';

import 'package:editor_core/editor_core.dart';

/// 专家 I-007（2026-08-16——批次 B）：GeometryEngine 测试——
/// 四象限 golden tests（端点/包围盒/方向/距离——接管直线几何）。
void main() {
  test('四象限：直线方向判定（1↗ 2↘ 3↙ 4↖）', () {
    // 第 1 象限（右上 ↗）：dx>0, dy<0。
    expect(GeometryEngine.line(x1: 0, y1: 10, x2: 10, y2: 0).quadrant, 1);
    // 第 2 象限（右下 ↘）：dx>0, dy>0。
    expect(GeometryEngine.line(x1: 0, y1: 0, x2: 10, y2: 10).quadrant, 2);
    // 第 3 象限（左下 ↙）：dx<0, dy>0。
    expect(GeometryEngine.line(x1: 10, y1: 0, x2: 0, y2: 10).quadrant, 3);
    // 第 4 象限（左上 ↖）：dx<0, dy<0。
    expect(GeometryEngine.line(x1: 10, y1: 10, x2: 0, y2: 0).quadrant, 4);
  });

  test('包围盒：直线外接矩形（四象限一致）', () {
    final b1 = GeometryEngine.line(x1: 0, y1: 10, x2: 10, y2: 0).bounds;
    expect(b1.left, 0);
    expect(b1.top, 0);
    expect(b1.right, 10);
    expect(b1.bottom, 10);

    final b3 = GeometryEngine.line(x1: 10, y1: 0, x2: 0, y2: 10).bounds;
    expect(b3.left, 0);
    expect(b3.top, 0);
    expect(b3.right, 10);
    expect(b3.bottom, 10);
  });

  test('点到线段距离：投影 t + clamp（权威算法）', () {
    final line = GeometryEngine.line(x1: 0, y1: 0, x2: 10, y2: 0);
    // 垂足在线段内——距离 = 5。
    expect(line.distanceTo(5, 5), closeTo(5, 1e-9));
    // 投影在段外——距离 = 端点 (10,0) 距离 √(25+25)。
    expect(line.distanceTo(15, 5), closeTo(7.0710678119, 1e-6));
    // 零长度段——退化为点到端点距离。
    final point = GeometryEngine.line(x1: 0, y1: 0, x2: 0, y2: 0);
    expect(point.distanceTo(3, 4), closeTo(5, 1e-9));
  });

  test('矩形几何：bounds/area/center/containsPoint', () {
    final rect = GeometryEngine.rectangle(x: 10, y: 20, width: 30, height: 40);
    expect(rect.bounds.left, 10);
    expect(rect.bounds.top, 20);
    expect(rect.bounds.right, 40);
    expect(rect.bounds.bottom, 60);
    expect(rect.area, 1200);
    expect(rect.center.x, 25);
    expect(rect.center.y, 40);
    expect(rect.containsPoint(25, 40), true);
    expect(rect.containsPoint(10, 20), true);
    expect(rect.containsPoint(5, 5), false);
  });

  test('矩形几何：distanceToEdge', () {
    final rect = GeometryEngine.rectangle(x: 0, y: 0, width: 10, height: 10);
    // 内部点——到最近边的距离
    expect(rect.distanceToEdge(5, 5), 5);
    expect(rect.distanceToEdge(1, 1), 1);
    expect(rect.distanceToEdge(9, 9), 1);
    // 外部点
    expect(rect.distanceToEdge(15, 5), 5);
  });

  test('椭圆几何：bounds/area/containsPoint', () {
    final ellipse = GeometryEngine.ellipse(cx: 50, cy: 50, rx: 30, ry: 20);
    expect(ellipse.bounds.left, 20);
    expect(ellipse.bounds.top, 30);
    expect(ellipse.bounds.right, 80);
    expect(ellipse.bounds.bottom, 70);
    expect(ellipse.area, closeTo(3.14159265358979 * 30 * 20, 1e-6));
    expect(ellipse.containsPoint(50, 50), true);
    expect(ellipse.containsPoint(81, 50), false);
  });

  test('箭头几何：bounds/direction/distanceToLine', () {
    final arrow = GeometryEngine.arrow(x1: 0, y1: 0, x2: 10, y2: 10, headWidth: 5);
    expect(arrow.bounds.left, -5);
    expect(arrow.bounds.top, -5);
    expect(arrow.bounds.right, 15);
    expect(arrow.bounds.bottom, 15);
    expect(arrow.direction, closeTo(0.7853981633974483, 1e-6)); // 45°
    expect(arrow.distanceToLine(5, 0), closeTo(3.5355339059327378, 1e-6));
    expect(arrow.distanceToLine(0, 5), closeTo(3.5355339059327378, 1e-6));
  });
}
