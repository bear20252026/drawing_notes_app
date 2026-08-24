import 'package:test/test.dart';

import 'package:editor_core/editor_core.dart';

/// Excalidraw 借鉴——ClipboardData 剪贴板测试（纯逻辑——不可变——不搞崩）。
void main() {
  test('ClipboardData：默认空', () {
    const clipboard = ClipboardData();
    expect(clipboard.isEmpty, true);
    expect(clipboard.count, 0);
    expect(clipboard.offsetX, 20.0);
    expect(clipboard.offsetY, 20.0);
  });

  test('ClipboardData：copyWith 不可变', () {
    const original = ClipboardData();
    final withStrokes = original.copyWith(
      strokes: [const LineItem(id: 's1', points: [Point(0, 0), Point(10, 10)])],
    );
    expect(original.isEmpty, true); // 原实例不变。
    expect(withStrokes.isEmpty, false);
    expect(withStrokes.count, 1);
  });

  test('ClipboardData：withNextOffset（连续粘贴偏移）', () {
    const clipboard = ClipboardData();
    final next = clipboard.withNextOffset();
    expect(next.offsetX, 40.0); // 20 + 20。
    expect(next.offsetY, 40.0);
  });

  test('ClipboardData：混和元素', () {
    const clipboard = ClipboardData(
      strokes: [LineItem(id: 's1', points: [])],
      shapes: [ShapeItem(id: 'sh1', type: 'rect', x: 0, y: 0, width: 10, height: 10)],
      texts: [TextItem(id: 't1', content: 'hi', x: 0, y: 0)],
    );
    expect(clipboard.count, 3);
    expect(clipboard.isEmpty, false);
  });

  test('ClipboardData：相等性', () {
    const a = ClipboardData(strokes: [LineItem(id: 's1', points: [])]);
    const b = ClipboardData(strokes: [LineItem(id: 's2', points: [])]);
    expect(a, b); // count 相同。
  });
}
