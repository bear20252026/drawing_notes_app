import 'package:test/test.dart';

import 'package:editor_core/editor_core.dart';

/// Excalidraw 借鉴——ChartData 图表测试（纯逻辑——不可变——不搞崩）。
void main() {
  test('ChartDataPoint：默认值 + copyWith 不可变', () {
    const point = ChartDataPoint(label: 'A', value: 10);
    expect(point.label, 'A');
    expect(point.value, 10);
    expect(point.color, '#000000');
    final updated = point.copyWith(value: 20, color: '#FF0000');
    expect(point.value, 10); // 原实例不变。
    expect(updated.value, 20);
    expect(updated.color, '#FF0000');
  });

  test('ChartDataset：total/max/min/average', () {
    const dataset = ChartDataset(
      name: 'Sales',
      points: [
        ChartDataPoint(label: 'Q1', value: 100),
        ChartDataPoint(label: 'Q2', value: 200),
        ChartDataPoint(label: 'Q3', value: 150),
      ],
    );
    expect(dataset.total, 450);
    expect(dataset.maxValue, 200);
    expect(dataset.minValue, 100);
    expect(dataset.average, 150);
  });

  test('ChartDataset：空数据集', () {
    const dataset = ChartDataset(name: 'Empty', points: []);
    expect(dataset.total, 0);
    expect(dataset.maxValue, 0);
    expect(dataset.minValue, 0);
    expect(dataset.average, 0);
  });

  test('ChartData：柱状图（bar）', () {
    const chart = ChartData(
      id: 'c1',
      type: ChartType.bar,
      datasets: [
        ChartDataset(name: 'Sales', points: [
          ChartDataPoint(label: 'Jan', value: 100),
          ChartDataPoint(label: 'Feb', value: 200),
        ]),
      ],
      title: 'Monthly Sales',
    );
    expect(chart.type, ChartType.bar);
    expect(chart.isEmpty, false);
    expect(chart.pointCount, 2);
    expect(chart.globalMax, 200);
  });

  test('ChartData：折线图（line）', () {
    const chart = ChartData(
      id: 'c2',
      type: ChartType.line,
      datasets: [
        ChartDataset(name: 'Temperature', points: [
          ChartDataPoint(label: 'Mon', value: 20),
          ChartDataPoint(label: 'Tue', value: 22),
          ChartDataPoint(label: 'Wed', value: 18),
        ]),
      ],
    );
    expect(chart.type, ChartType.line);
    expect(chart.globalMax, 22);
  });

  test('ChartData：饼图百分比（pie）', () {
    const chart = ChartData(
      id: 'c3',
      type: ChartType.pie,
      datasets: [
        ChartDataset(name: 'Market Share', points: [
          ChartDataPoint(label: 'A', value: 30),
          ChartDataPoint(label: 'B', value: 50),
          ChartDataPoint(label: 'C', value: 20),
        ]),
      ],
    );
    final percentages = chart.piePercentages(0);
    expect(percentages.length, 3);
    expect(percentages[0], closeTo(30, 0.01)); // 30/100 * 100 = 30%
    expect(percentages[1], closeTo(50, 0.01)); // 50/100 * 100 = 50%
    expect(percentages[2], closeTo(20, 0.01)); // 20/100 * 100 = 20%
  });

  test('ChartData：piePercentages 边界（非 pie 类型/越界）', () {
    const bar = ChartData(id: 'c4', type: ChartType.bar, datasets: []);
    expect(bar.piePercentages(0), isEmpty);
    const pie = ChartData(id: 'c5', type: ChartType.pie, datasets: []);
    expect(pie.piePercentages(0), isEmpty); // 越界。
    expect(pie.piePercentages(99), isEmpty);
  });

  test('ChartData：isEmpty 判断', () {
    const empty = ChartData(id: 'c6', type: ChartType.bar, datasets: []);
    expect(empty.isEmpty, true);
    const withEmptyDataset = ChartData(
      id: 'c7',
      type: ChartType.bar,
      datasets: [ChartDataset(name: 'Empty', points: [])],
    );
    expect(withEmptyDataset.isEmpty, true);
  });

  test('ChartData：copyWith 不可变', () {
    const original = ChartData(id: 'c8', type: ChartType.bar, datasets: []);
    final renamed = original.copyWith(title: 'New Title');
    expect(original.title, ''); // 原实例不变。
    expect(renamed.title, 'New Title');
  });

  test('ChartData/ChartDataset/ChartDataPoint：相等性', () {
    const a = ChartData(id: 'c1', type: ChartType.bar, datasets: []);
    const b = ChartData(id: 'c1', type: ChartType.bar, datasets: []);
    expect(a, b);
    const c = ChartDataset(name: 'S', points: []);
    const d = ChartDataset(name: 'S', points: []);
    expect(c, d);
    const e = ChartDataPoint(label: 'A', value: 1);
    const f = ChartDataPoint(label: 'A', value: 1);
    expect(e, f);
  });
}
