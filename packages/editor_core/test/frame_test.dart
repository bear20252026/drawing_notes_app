import 'package:test/test.dart';

import 'package:editor_core/editor_core.dart';

/// Excalidraw 借鉴——Frame 框架系统测试（纯逻辑——不搞崩）。
void main() {
  test('Frame：默认值 + bounds + center', () {
    const frame = Frame(id: 'f1', name: 'Frame 1', x: 10, y: 20, width: 100, height: 80);
    expect(frame.bounds.left, 10);
    expect(frame.bounds.right, 110);
    expect(frame.bounds.top, 20);
    expect(frame.bounds.bottom, 100);
    expect(frame.center.x, 60);
    expect(frame.center.y, 60);
    expect(frame.clipChildren, true);
    expect(frame.locked, false);
  });

  test('Frame：containsPoint 点包含检测', () {
    const frame = Frame(id: 'f1', name: 'Frame 1', x: 0, y: 0, width: 100, height: 100);
    expect(frame.containsPoint(50, 50), true);  // 内部。
    expect(frame.containsPoint(0, 0), true);    // 边界。
    expect(frame.containsPoint(150, 50), false); // 外部。
  });

  test('Frame：containsElement 元素完全包含', () {
    const frame = Frame(id: 'f1', name: 'Frame 1', x: 0, y: 0, width: 200, height: 200);
    expect(frame.containsElement(50, 50, 100, 100), true);  // 完全内部。
    expect(frame.containsElement(150, 150, 100, 100), false); // 部分超出。
    expect(frame.containsElement(250, 50, 100, 100), false); // 完全外部。
  });

  test('Frame：intersectsElement 元素相交', () {
    const frame = Frame(id: 'f1', name: 'Frame 1', x: 0, y: 0, width: 100, height: 100);
    expect(frame.intersectsElement(50, 50, 100, 100), true);  // 相交。
    expect(frame.intersectsElement(150, 50, 100, 100), false); // 不相交。
    expect(frame.intersectsElement(-50, -50, 60, 60), true);  // 部分相交。
  });

  test('Frame：addChild/removeChild/hasChild', () {
    const frame = Frame(id: 'f1', name: 'Frame 1', x: 0, y: 0, width: 100, height: 100);
    final withChild = frame.addChild('elem1');
    expect(withChild.childCount, 1);
    expect(withChild.hasChild('elem1'), true);
    expect(withChild.isEmpty, false);
    // 不重复添加。
    final again = withChild.addChild('elem1');
    expect(again.childCount, 1);
    // 移除。
    final removed = withChild.removeChild('elem1');
    expect(removed.childCount, 0);
    expect(removed.isEmpty, true);
  });

  test('Frame：moveTo/resize 不可变', () {
    const frame = Frame(id: 'f1', name: 'Frame 1', x: 0, y: 0, width: 100, height: 100);
    final moved = frame.moveTo(50, 60);
    expect(moved.x, 50);
    expect(moved.y, 60);
    expect(frame.x, 0); // 原实例不变。
    final resized = frame.resize(200, 300);
    expect(resized.width, 200);
    expect(resized.height, 300);
  });

  test('Frame：copyWith 不可变', () {
    const frame = Frame(id: 'f1', name: 'Frame 1', x: 0, y: 0, width: 100, height: 100);
    final renamed = frame.copyWith(name: 'New Frame', backgroundColor: '#FF0000');
    expect(frame.name, 'Frame 1'); // 原实例不变。
    expect(renamed.name, 'New Frame');
    expect(renamed.backgroundColor, '#FF0000');
  });

  test('FrameManager：add/remove/get', () {
    const manager = FrameManager();
    final withFrame = manager.add(const Frame(id: 'f1', name: 'Frame 1', x: 0, y: 0, width: 100, height: 100));
    expect(withFrame.count, 1);
    expect(withFrame.get('f1')!.name, 'Frame 1');
    final removed = withFrame.remove('f1');
    expect(removed.count, 0);
  });

  test('FrameManager：assignElementToFrame（自动从其他 Frame 移除）', () {
    var manager = FrameManager();
    manager = manager.add(const Frame(id: 'f1', name: 'Frame 1', x: 0, y: 0, width: 200, height: 200));
    manager = manager.add(const Frame(id: 'f2', name: 'Frame 2', x: 300, y: 0, width: 200, height: 200));
    // 分配到 f1。
    manager = manager.assignElementToFrame('elem1', 'f1');
    expect(manager.get('f1')!.hasChild('elem1'), true);
    // 重新分配到 f2——自动从 f1 移除。
    manager = manager.assignElementToFrame('elem1', 'f2');
    expect(manager.get('f1')!.hasChild('elem1'), false);
    expect(manager.get('f2')!.hasChild('elem1'), true);
  });

  test('FrameManager：getFrameForElement / detectFramesForElement', () {
    var manager = FrameManager();
    manager = manager.add(const Frame(id: 'f1', name: 'Frame 1', x: 0, y: 0, width: 200, height: 200));
    manager = manager.assignElementToFrame('elem1', 'f1');
    expect(manager.getFrameForElement('elem1')!.id, 'f1');
    expect(manager.getFrameForElement('elem2'), isNull);
    // 几何检测。
    final detected = manager.detectFramesForElement(50, 50, 100, 100);
    expect(detected.length, 1);
    expect(detected.first.id, 'f1');
  });

  test('FrameManager：unassignElement', () {
    var manager = FrameManager();
    manager = manager.add(const Frame(id: 'f1', name: 'Frame 1', x: 0, y: 0, width: 200, height: 200));
    manager = manager.assignElementToFrame('elem1', 'f1');
    expect(manager.get('f1')!.hasChild('elem1'), true);
    manager = manager.unassignElement('elem1');
    expect(manager.get('f1')!.hasChild('elem1'), false);
  });

  test('FrameType 枚举', () {
    expect(FrameType.values.length, 2);
  });
}
