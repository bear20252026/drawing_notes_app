import 'package:test/test.dart';

import 'package:editor_core/editor_core.dart';

/// Excalidraw 借鉴——ArrowBinding 箭头绑定测试（纯逻辑——不可变——不搞崩）。
void main() {
  test('EndpointBinding：默认值', () {
    const binding = EndpointBinding(elementId: 'rect1');
    expect(binding.elementId, 'rect1');
    expect(binding.focus, 0.0); // 中心。
    expect(binding.gap, 4.0);  // 默认间距。
  });

  test('EndpointBinding：copyWith 不可变', () {
    const original = EndpointBinding(elementId: 'rect1');
    final updated = original.copyWith(focus: 0.5, gap: 8);
    expect(original.focus, 0.0); // 原实例不变。
    expect(updated.focus, 0.5);
    expect(updated.gap, 8);
  });

  test('ArrowBinding：默认无绑定', () {
    const binding = ArrowBinding();
    expect(binding.isBound, false);
    expect(binding.isFullyBound, false);
    expect(binding.startBinding, isNull);
    expect(binding.endBinding, isNull);
  });

  test('ArrowBinding：bindStart / bindEnd', () {
    const binding = ArrowBinding();
    final boundStart = binding.bindStart('rect1', focus: -0.5);
    expect(boundStart.isBound, true);
    expect(boundStart.isFullyBound, false);
    expect(boundStart.startBinding!.elementId, 'rect1');
    expect(boundStart.startBinding!.focus, -0.5);

    final fullyBound = boundStart.bindEnd('circle1', focus: 0.3);
    expect(fullyBound.isFullyBound, true);
    expect(fullyBound.endBinding!.elementId, 'circle1');
  });

  test('ArrowBinding：unbindStart / unbindEnd', () {
    const binding = ArrowBinding(
      startBinding: EndpointBinding(elementId: 'rect1'),
      endBinding: EndpointBinding(elementId: 'circle1'),
    );
    expect(binding.isFullyBound, true);

    final unboundStart = binding.unbindStart();
    expect(unboundStart.isFullyBound, false);
    expect(unboundStart.startBinding, isNull);
    expect(unboundStart.endBinding, isNotNull);

    final fullyUnbound = binding.unbindEnd();
    expect(fullyUnbound.isFullyBound, false);
    expect(fullyUnbound.endBinding, isNull);
  });

  test('ArrowBinding：copyWith 不可变', () {
    const original = ArrowBinding(
      startBinding: EndpointBinding(elementId: 'rect1'),
    );
    final modified = original.copyWith(
      endBinding: const EndpointBinding(elementId: 'circle1'),
    );
    expect(original.isFullyBound, false); // 原实例不变。
    expect(modified.isFullyBound, true);
  });

  test('ArrowBinding：相等性', () {
    const a = ArrowBinding(startBinding: EndpointBinding(elementId: 'rect1'));
    const b = ArrowBinding(startBinding: EndpointBinding(elementId: 'rect1'));
    expect(a, b);
  });
}
