import 'package:test/test.dart';

import 'package:editor_core/editor_core.dart';

/// 专家 I-007（2026-08-16——批次 B）：GeometryEngine 直线——
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

  // L-9 收口（2026-11-16）：轴对齐与退化边界——既有 golden 只测对角线，
  // 水平/垂直/零长/负坐标的包围盒与象限边界此前无覆盖。
  test('轴对齐：水平/垂直线包围盒（含退化零面积）', () {
    // 水平线（dy=0）——包围盒零高度。
    final h = GeometryEngine.line(x1: 2, y1: 5, x2: 8, y2: 5).bounds;
    expect((h.left, h.top, h.right, h.bottom), (2, 5, 8, 5));
    // 垂直线（dx=0）——包围盒零宽度。
    final v = GeometryEngine.line(x1: 3, y1: 1, x2: 3, y2: 9).bounds;
    expect((v.left, v.top, v.right, v.bottom), (3, 1, 3, 9));
    // 退化点——包围盒零面积。
    final p = GeometryEngine.line(x1: 4, y1: 4, x2: 4, y2: 4).bounds;
    expect((p.left, p.top, p.right, p.bottom), (4, 4, 4, 4));
  });

  test('轴对齐象限边界：dx=0/dy=0 归入确定象限（不抛错）', () {
    // 垂直向下（dx=0,dy>0）→ 象限 2（dx>=0 && dy>=0）。
    expect(GeometryEngine.line(x1: 0, y1: 0, x2: 0, y2: 5).quadrant, 2);
    // 水平向右（dx>0,dy=0）→ 象限 2。
    expect(GeometryEngine.line(x1: 0, y1: 0, x2: 5, y2: 0).quadrant, 2);
    // 退化点（dx=0,dy=0）→ 象限 2（确定值，非异常）。
    expect(GeometryEngine.line(x1: 1, y1: 1, x2: 1, y2: 1).quadrant, 2);
  });

  test('负坐标：包围盒与距离正确（画布平移后坐标可为负）', () {
    final line = GeometryEngine.line(x1: -10, y1: -5, x2: -2, y2: -5);
    final b = line.bounds;
    expect((b.left, b.top, b.right, b.bottom), (-10, -5, -2, -5));
    // 垂足在线段内（x=-6 在 [-10,-2]）——距离 = 3。
    expect(line.distanceTo(-6, -2), closeTo(3, 1e-9));
  });

  test('近退化段（lengthSquared≤1e-8）：退化为点到端点距离', () {
    // 端点差 1e-5 → lengthSquared=1e-10 ≤ 1e-8 → 走退化分支。
    final tiny = GeometryEngine.line(x1: 0, y1: 0, x2: 1e-5, y2: 0);
    expect(tiny.distanceTo(0, 3), closeTo(3, 1e-9));
  });
}
