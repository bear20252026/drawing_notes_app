import 'package:test/test.dart';

import 'package:editor_core/editor_core.dart';

/// Excalidraw 借鉴——GridConfig 网格吸附测试（纯逻辑——不可变——不搞崩）。
void main() {
  test('GridConfig：默认值（20px 网格——吸附开启——显示开启）', () {
    const config = GridConfig();
    expect(config.size, 20);
    expect(config.snapEnabled, true);
    expect(config.showGrid, true);
  });

  test('GridConfig：copyWith 不可变', () {
    const original = GridConfig();
    final disabled = original.copyWith(snapEnabled: false, showGrid: false);
    expect(original.snapEnabled, true); // 原实例不变。
    expect(disabled.snapEnabled, false);
    expect(disabled.showGrid, false);
  });

  test('GridConfig：预设（disabled/fine/coarse）', () {
    expect(GridConfig.disabled.snapEnabled, false);
    expect(GridConfig.fine.size, 10);
    expect(GridConfig.coarse.size, 40);
  });

  test('GridSnap.snapToGrid：坐标吸附到最近网格点', () {
    // 网格 20px——round() 半值向上取整。
    expect(GridSnap.snapToGrid(0, 20), 0.0);
    expect(GridSnap.snapToGrid(10, 20), 20.0);  // 10/20=0.5 → round=1 → 20。
    expect(GridSnap.snapToGrid(25, 20), 20.0);  // 25/20=1.25 → round=1 → 20。
    expect(GridSnap.snapToGrid(30, 20), 40.0);  // 30/20=1.5 → round=2 → 40。
    expect(GridSnap.snapToGrid(31, 20), 40.0);  // 31/20=1.55 → round=2 → 40。
    expect(GridSnap.snapToGrid(-10, 20), -20.0); // -10/20=-0.5 → round=-1 → -20。
  });

  test('GridSnap.snapPointToGrid：二维吸附', () {
    const config = GridConfig();
    final snapped = GridSnap.snapPointToGrid(25, 35, config);
    expect(snapped.x, 20.0);
    expect(snapped.y, 40.0);
    // 吸附关闭——不变。
    final noSnap = GridSnap.snapPointToGrid(25, 35, GridConfig.disabled);
    expect(noSnap.x, 25.0);
    expect(noSnap.y, 35.0);
  });

  test('GridSnap.snapToElement：元素对齐吸附（边缘/中心）', () {
    // 移动元素(10,10,50,50) 目标元素(100,100,80,80)——阈值 5。
    final result = GridSnap.snapToElement(
      moveX: 98, moveY: 100, moveW: 50, moveH: 50,
      targetX: 100, targetY: 100, targetW: 80, targetH: 80,
    );
    // moveX=98 与 targetX=100 差 2 < 5——左-左对齐。
    expect(result.snappedX, 100.0);
    expect(result.snappedAnchorsX, contains(SnapAnchor.left));
    // moveY=100 与 targetY=100 差 0——上-上对齐。
    expect(result.snappedY, 100.0);
    expect(result.snappedAnchorsY, contains(SnapAnchor.top));
  });

  test('GridSnap.snapToElement：中心对齐', () {
    // moveX=120 moveW=50 → centerX=145; targetX=100 targetW=80 → centerX=140
    // centerX 差=5 < threshold=10 → 中心对齐。
    // 但 moveX=120 与 targetLeft=100 差=20 > 10，moveRight=170 与 targetRight=180 差=10 = 10 → right 对齐。
    // 右-右对齐先命中（遍历顺序）。
    final result = GridSnap.snapToElement(
      moveX: 120, moveY: 120, moveW: 50, moveH: 50,
      targetX: 100, targetY: 100, targetW: 80, targetH: 80,
      threshold: 10.0,
    );
    // 右-右对齐（moveRight=170 与 targetRight=180 差=10 ≤ 10）或中心对齐。
    expect(result.isSnapped, true);
  });

  test('GridSnap.snapToElement：无对齐（超出阈值）', () {
    final result = GridSnap.snapToElement(
      moveX: 500, moveY: 500, moveW: 50, moveH: 50,
      targetX: 100, targetY: 100, targetW: 80, targetH: 80,
    );
    expect(result.isSnapped, false);
  });

  test('GridSnap.gridPoints：生成网格点列表', () {
    const config = GridConfig(size: 50);
    final points = GridSnap.gridPoints(0, 0, 100, 100, config);
    // (0,0) 到 (100,100) 网格 50px——点(0,0)(0,50)(50,0)(50,50)(100,0)(100,50)(0,100)(50,100)(100,100)。
    expect(points.length, 9); // 3x3 网格。
    expect(points.first.x, 0.0);
    expect(points.first.y, 0.0);
    // 关闭显示——空列表。
    expect(GridSnap.gridPoints(0, 0, 100, 100, GridConfig.disabled), isEmpty);
  });

  test('SnapResult：isSnapped 判断', () {
    const snapped = SnapResult(
      snappedX: 100, snappedY: 100,
      snappedAnchorsX: [SnapAnchor.left],
    );
    expect(snapped.isSnapped, true);
    const notSnapped = SnapResult(snappedX: 100, snappedY: 100);
    expect(notSnapped.isSnapped, false);
  });
}
