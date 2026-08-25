import 'package:test/test.dart';

import 'package:editor_core/editor_core.dart';

/// Excalidraw 借鉴——ShapeLibrary 形状库测试（纯逻辑——不可变——不搞崩）。
void main() {
  test('ShapeLibraryItem：copyWith 不可变', () {
    const item = ShapeLibraryItem(id: 's1', name: 'Arrow');
    final renamed = item.copyWith(name: 'Arrow v2');
    expect(item.name, 'Arrow'); // 原实例不变。
    expect(renamed.name, 'Arrow v2');
  });

  test('ShapeLibraryItem：isEmpty / elementCount', () {
    const empty = ShapeLibraryItem(id: 's1', name: 'Empty');
    expect(empty.isEmpty, true);
    expect(empty.elementCount, 0);

    const withShapes = ShapeLibraryItem(
      id: 's2',
      name: 'Shapes',
      shapes: [ShapeDef(type: 'rect', x: 0, y: 0, width: 100, height: 80)],
    );
    expect(withShapes.isEmpty, false);
    expect(withShapes.elementCount, 1);
  });

  test('ShapeLibrary：addItem 去重（按 id）', () {
    const library = ShapeLibrary();
    const item = ShapeLibraryItem(id: 's1', name: 'Arrow');
    final added = library.addItem(item);
    expect(added.count, 1);
    // 再次添加同一 id——不重复。
    final again = added.addItem(item);
    expect(again.count, 1);
  });

  test('ShapeLibrary：removeItem / updateItem', () {
    const library = ShapeLibrary(items: [
      ShapeLibraryItem(id: 's1', name: 'Arrow'),
      ShapeLibraryItem(id: 's2', name: 'Star'),
    ]);
    final removed = library.removeItem('s1');
    expect(removed.count, 1);
    expect(removed.items.first.name, 'Star');

    final updated = library.updateItem(
      const ShapeLibraryItem(id: 's2', name: 'Star v2'),
    );
    expect(updated.items.last.name, 'Star v2'); // 's2' 在第二个位置。
  });

  test('ShapeLibrary：search（按名称/标签）', () {
    const library = ShapeLibrary(items: [
      ShapeLibraryItem(id: 's1', name: 'Arrow', tags: ['direction']),
      ShapeLibraryItem(id: 's2', name: 'Star', tags: ['shape', 'decoration']),
      ShapeLibraryItem(id: 's3', name: 'Rectangle', tags: ['basic']),
    ]);
    expect(library.search('arrow').length, 1);
    expect(library.search('shape').length, 1);
    expect(library.search('').length, 3); // 空查询返回全部。
    expect(library.search('nonexistent').length, 0);
  });

  test('ShapeLibrary：copyWith 不可变', () {
    const library = ShapeLibrary();
    final renamed = library.copyWith(name: 'New Library');
    expect(library.name, 'My Library'); // 原实例不变。
    expect(renamed.name, 'New Library');
  });

  test('ShapeDef / StrokeDef / TextDef 相等性', () {
    const a = ShapeDef(type: 'rect', x: 0, y: 0, width: 100, height: 80);
    const b = ShapeDef(type: 'rect', x: 0, y: 0, width: 100, height: 80);
    expect(a, b);

    const c = StrokeDef(points: [(x: 0.0, y: 0.0), (x: 10.0, y: 10.0)]);
    const d = StrokeDef(points: [(x: 0.0, y: 0.0), (x: 10.0, y: 10.0)]);
    expect(c, d);

    const e = TextDef(content: 'Hello', x: 10, y: 20);
    const f = TextDef(content: 'Hello', x: 10, y: 20);
    expect(e, f);
  });
}
