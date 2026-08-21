import 'package:test/test.dart';

import 'package:editor_core/editor_core.dart';

/// Excalidraw 借鉴——LassoSelection 套索选择测试（纯逻辑——不可变——不搞崩）。
void main() {
  test('LassoSelection.rectangle：矩形框选', () {
    final lasso = LassoSelection.rectangle(10, 20, 100, 80);
    expect(lasso.type, LassoType.rectangle);
    expect(lasso.points.length, 4);
    expect(lasso.isEmpty, false);
    expect(lasso.bounds.left, 10);
    expect(lasso.bounds.top, 20);
    expect(lasso.bounds.right, 100);
    expect(lasso.bounds.bottom, 80);
  });

  test('LassoSelection.freeform：自由曲线套索', () {
    final lasso = LassoSelection.freeform([
      (x: 0.0, y: 0.0),
      (x: 100.0, y: 0.0),
      (x: 100.0, y: 100.0),
      (x: 0.0, y: 100.0),
    ]);
    expect(lasso.type, LassoType.freeform);
    expect(lasso.points.length, 4);
  });

  test('containsPoint：矩形框选', () {
    final lasso = LassoSelection.rectangle(10, 20, 100, 80);
    expect(lasso.containsPoint(50, 50), true);  // 内部。
    expect(lasso.containsPoint(5, 50), false);   // 左侧外部。
    expect(lasso.containsPoint(50, 5), false);   // 上方外部。
    expect(lasso.containsPoint(150, 50), false); // 右侧外部。
  });

  test('containsPoint：自由曲线（射线法）', () {
    // 正方形区域。
    final lasso = LassoSelection.freeform([
      (x: 0.0, y: 0.0),
      (x: 100.0, y: 0.0),
      (x: 100.0, y: 100.0),
      (x: 0.0, y: 100.0),
    ]);
    expect(lasso.containsPoint(50, 50), true);  // 内部。
    expect(lasso.containsPoint(150, 50), false); // 外部。
  });

  test('containsElement：元素包含检测', () {
    final lasso = LassoSelection.rectangle(0, 0, 200, 200);
    expect(lasso.containsElement(50, 50, 100, 100), true);  // 完全内部。
    expect(lasso.containsElement(250, 50, 100, 100), false); // 完全外部。
    // 边界交叉（元素部分在区域内——bounds 交叉但不完全包含）。
    expect(lasso.containsElement(150, 150, 100, 100), false); // 部分交叉但不完全包含。
  });

  test('isEmpty：点数不足', () {
    final empty = LassoSelection(type: LassoType.rectangle, points: [(x: 0.0, y: 0.0)]);
    expect(empty.isEmpty, true);
  });

  test('相等性', () {
    final a = LassoSelection.rectangle(0, 0, 100, 100);
    final b = LassoSelection.rectangle(0, 0, 100, 100);
    expect(a, b);
  });
}
