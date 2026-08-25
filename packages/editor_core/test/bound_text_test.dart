import 'package:test/test.dart';

import 'package:editor_core/editor_core.dart';

/// Excalidraw 借鉴——BoundText 文本绑定容器测试（纯逻辑——不搞崩）。
void main() {
  test('TextBinding：默认值 + copyWith 不可变', () {
    const binding = TextBinding(textId: 't1', containerId: 'c1');
    expect(binding.textId, 't1');
    expect(binding.containerId, 'c1');
    expect(binding.padding, 8.0);
    expect(binding.verticalAlign, VerticalAlign.top);
    expect(binding.horizontalAlign, HorizontalAlign.left);
    expect(binding.autoResize, true);
    final updated = binding.copyWith(padding: 16, verticalAlign: VerticalAlign.middle);
    expect(binding.padding, 8.0); // 原实例不变。
    expect(updated.padding, 16);
    expect(updated.verticalAlign, VerticalAlign.middle);
  });

  test('ShapeContainer：bounds + contentArea + hasText', () {
    const container = ShapeContainer(id: 'c1', type: ContainerType.rectangle, x: 10, y: 20, width: 100, height: 80);
    expect(container.bounds.left, 10);
    expect(container.bounds.right, 110);
    expect(container.bounds.top, 20);
    expect(container.bounds.bottom, 100);
    expect(container.contentArea.x, 18); // 10 + 8
    expect(container.contentArea.y, 28); // 20 + 8
    expect(container.contentArea.width, 84); // 100 - 16
    expect(container.contentArea.height, 64); // 80 - 16
    expect(container.hasText, false);
  });

  test('ShapeContainer：addText/removeText', () {
    const container = ShapeContainer(id: 'c1', type: ContainerType.rectangle, x: 0, y: 0, width: 100, height: 100);
    final withText = container.addText('t1');
    expect(withText.textCount, 1);
    expect(withText.hasText, true);
    // 不重复添加。
    final again = withText.addText('t1');
    expect(again.textCount, 1);
    // 移除。
    final removed = withText.removeText('t1');
    expect(removed.textCount, 0);
  });

  test('ShapeContainer：getTextPosition（对齐计算）', () {
    const container = ShapeContainer(
      id: 'c1', type: ContainerType.rectangle,
      x: 0, y: 0, width: 100, height: 100, padding: 10,
    );
    // 左上。
    final topLeft = container.getTextPosition(60, 20);
    expect(topLeft.x, 10); // padding。
    expect(topLeft.y, 10);
    // 居中。
    final center = container.getTextPosition(60, 20,
        vAlign: VerticalAlign.middle, hAlign: HorizontalAlign.center);
    expect(center.x, closeTo(20, 1)); // (100-16-60)/2 + 10 = 22
    expect(center.y, closeTo(40, 1)); // (100-16-20)/2 + 10 = 42
    // 右下。
    final bottomRight = container.getTextPosition(60, 20,
        vAlign: VerticalAlign.bottom, hAlign: HorizontalAlign.right);
    expect(bottomRight.x, 30); // 100-10-60
    expect(bottomRight.y, 70); // 100-10-20
  });

  test('ShapeContainer：moveTo/resize 不可变', () {
    const container = ShapeContainer(id: 'c1', type: ContainerType.rectangle, x: 0, y: 0, width: 100, height: 100);
    final moved = container.moveTo(50, 60);
    expect(moved.x, 50);
    expect(moved.y, 60);
    expect(container.x, 0); // 原实例不变。
    final resized = container.resize(200, 300);
    expect(resized.width, 200);
    expect(resized.height, 300);
  });

  test('ShapeContainer：resize 最小值限制（padding * 2）', () {
    const container = ShapeContainer(id: 'c1', type: ContainerType.rectangle, x: 0, y: 0, width: 100, height: 100, padding: 20);
    final resized = container.resize(10, 10);
    expect(resized.width, 40); // 最小值 = padding * 2 = 40
    expect(resized.height, 40);
  });

  test('TextBindingManager：addBinding/removeBinding', () {
    const manager = TextBindingManager();
    final withBinding = manager.addBinding(const TextBinding(textId: 't1', containerId: 'c1'));
    expect(withBinding.bindingCount, 1);
    expect(withBinding.containerCount, 0);
    final removed = withBinding.removeBinding('t1');
    expect(removed.bindingCount, 0);
  });

  test('TextBindingManager：addContainer/removeContainer', () {
    const manager = TextBindingManager();
    final withContainer = manager.addContainer(const ShapeContainer(id: 'c1', type: ContainerType.rectangle, x: 0, y: 0, width: 100, height: 100));
    expect(withContainer.containerCount, 1);
    // 移除容器同时移除相关绑定。
    final withBinding = withContainer.addBinding(const TextBinding(textId: 't1', containerId: 'c1'));
    expect(withBinding.bindingCount, 1);
    final removed = withBinding.removeContainer('c1');
    expect(removed.containerCount, 0);
    expect(removed.bindingCount, 0);
  });

  test('TextBindingManager：getContainerForText / getTextsForContainer', () {
    var manager = const TextBindingManager();
    manager = manager.addContainer(const ShapeContainer(id: 'c1', type: ContainerType.ellipse, x: 0, y: 0, width: 100, height: 100));
    manager = manager.addBinding(const TextBinding(textId: 't1', containerId: 'c1'));
    manager = manager.addBinding(const TextBinding(textId: 't2', containerId: 'c1'));
    expect(manager.getContainerForText('t1')!.id, 'c1');
    expect(manager.getTextsForContainer('c1'), ['t1', 't2']);
    expect(manager.getContainerForText('t3'), isNull);
  });

  test('VerticalAlign/HorizontalAlign/ContainerType 枚举', () {
    expect(VerticalAlign.values.length, 3);
    expect(HorizontalAlign.values.length, 3);
    expect(ContainerType.values.length, 4);
  });
}
