import 'package:test/test.dart';

import 'package:editor_core/editor_core.dart';

/// tldraw 借鉴——Alignment 对齐分布测试（纯逻辑——不可变——不搞崩）。
void main() {
  test('ElementPosition：bounds + center', () {
    const e = ElementPosition(id: 'e1', x: 10, y: 20, width: 100, height: 80);
    expect(e.left, 10);
    expect(e.right, 110);
    expect(e.top, 20);
    expect(e.bottom, 100);
    expect(e.centerX, 60);
    expect(e.centerY, 60);
  });

  test('ElementPosition：moveTo', () {
    const e = ElementPosition(id: 'e1', x: 10, y: 20, width: 100, height: 80);
    final moved = e.moveTo(50, 60);
    expect(moved.x, 50);
    expect(moved.y, 60);
    expect(e.x, 10); // 原实例不变。
  });

  test('align：左对齐', () {
    final elements = [
      const ElementPosition(id: 'e1', x: 10, y: 0, width: 50, height: 50),
      const ElementPosition(id: 'e2', x: 100, y: 0, width: 50, height: 50),
      const ElementPosition(id: 'e3', x: 200, y: 0, width: 50, height: 50),
    ];
    final result = Alignment.align(elements, AlignmentType.left);
    expect(result.count, 2); // e2 和 e3 需要移动到 x=10。
    expect(result.moves.firstWhere((m) => m.id == 'e2').x, 10);
    expect(result.moves.firstWhere((m) => m.id == 'e3').x, 10);
  });

  test('align：右对齐', () {
    final elements = [
      const ElementPosition(id: 'e1', x: 10, y: 0, width: 50, height: 50),  // right=60
      const ElementPosition(id: 'e2', x: 100, y: 0, width: 50, height: 50), // right=150
    ];
    final result = Alignment.align(elements, AlignmentType.right);
    expect(result.count, 1); // e1 需要移动到 x=100（right=150 对齐）。
    expect(result.moves.first.x, 100);
  });

  test('align：上对齐', () {
    final elements = [
      const ElementPosition(id: 'e1', x: 0, y: 10, width: 50, height: 50),
      const ElementPosition(id: 'e2', x: 0, y: 100, width: 50, height: 50),
    ];
    final result = Alignment.align(elements, AlignmentType.top);
    expect(result.count, 1);
    expect(result.moves.first.y, 10);
  });

  test('align：下对齐', () {
    final elements = [
      const ElementPosition(id: 'e1', x: 0, y: 10, width: 50, height: 50),  // bottom=60
      const ElementPosition(id: 'e2', x: 0, y: 100, width: 50, height: 50), // bottom=150
    ];
    final result = Alignment.align(elements, AlignmentType.bottom);
    expect(result.count, 1);
    expect(result.moves.first.y, 100);
  });

  test('align：水平居中', () {
    final elements = [
      const ElementPosition(id: 'e1', x: 0, y: 0, width: 100, height: 50),  // centerX=50
      const ElementPosition(id: 'e2', x: 200, y: 0, width: 100, height: 50), // centerX=250
    ];
    final result = Alignment.align(elements, AlignmentType.centerHorizontal);
    // 平均 centerX=150——e1 移到 x=100，e2 移到 x=100——两个都移动。
    expect(result.count, 2);
  });

  test('align：垂直居中', () {
    final elements = [
      const ElementPosition(id: 'e1', x: 0, y: 0, width: 50, height: 100),   // centerY=50
      const ElementPosition(id: 'e2', x: 0, y: 200, width: 50, height: 100), // centerY=250
    ];
    final result = Alignment.align(elements, AlignmentType.centerVertical);
    // 平均 centerY=150——e1 移到 y=100，e2 移到 y=100——两个都移动。
    expect(result.count, 2);
  });

  test('align：不足 2 个元素——不操作', () {
    final result = Alignment.align([const ElementPosition(id: 'e1', x: 0, y: 0, width: 50, height: 50)], AlignmentType.left);
    expect(result.isEmpty, true);
  });

  test('distribute：水平均匀分布', () {
    final elements = [
      const ElementPosition(id: 'e1', x: 0, y: 0, width: 50, height: 50),
      const ElementPosition(id: 'e2', x: 100, y: 0, width: 50, height: 50), // 间距不均匀。
      const ElementPosition(id: 'e3', x: 300, y: 0, width: 50, height: 50),
    ];
    final result = Alignment.distribute(elements, DistributionType.horizontal);
    expect(result.isEmpty, false); // e2 需要移动。
  });

  test('distribute：垂直均匀分布', () {
    final elements = [
      const ElementPosition(id: 'e1', x: 0, y: 0, width: 50, height: 50),
      const ElementPosition(id: 'e2', x: 0, y: 100, width: 50, height: 50),
      const ElementPosition(id: 'e3', x: 0, y: 300, width: 50, height: 50),
    ];
    final result = Alignment.distribute(elements, DistributionType.vertical);
    expect(result.isEmpty, false);
  });

  test('distribute：不足 3 个元素——不操作', () {
    final elements = [
      const ElementPosition(id: 'e1', x: 0, y: 0, width: 50, height: 50),
      const ElementPosition(id: 'e2', x: 100, y: 0, width: 50, height: 50),
    ];
    expect(Alignment.distribute(elements, DistributionType.horizontal).isEmpty, true);
  });

  test('AlignmentType/DistributionType 枚举', () {
    expect(AlignmentType.values.length, 6);
    expect(DistributionType.values.length, 2);
  });
}
