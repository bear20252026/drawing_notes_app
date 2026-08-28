import 'package:drawing_notes_app/features/drawing/presentation/editor_layer_order_mutation.dart';
import 'package:flutter_test/flutter_test.dart';

EditorLayerOrderEntry entry(String id, String key, int zOrder) =>
    EditorLayerOrderEntry(id: id, fractionalIndex: key, zOrder: zOrder);

void main() {
  final entries = [
    entry('a', 'a1', 1),
    entry('b', 'a2', 2),
    entry('c', 'a3', 3),
  ];

  test('置顶和置底只为选中对象生成边界键', () {
    final top = EditorLayerOrderMutation.reorder(
      entries: entries,
      selectedIds: {'b'},
      mode: 0,
    );
    final bottom = EditorLayerOrderMutation.reorder(
      entries: entries,
      selectedIds: {'b'},
      mode: 1,
    );

    expect(top.keys, {'b'});
    expect(top['b']!.compareTo('a3'), greaterThan(0));
    expect(bottom.keys, {'b'});
    expect(bottom['b']!.compareTo('a1'), lessThan(0));
  });

  test('上移和下移交换相邻对象的排序键', () {
    final up = EditorLayerOrderMutation.reorder(
      entries: entries,
      selectedIds: {'b'},
      mode: 2,
    );
    final down = EditorLayerOrderMutation.reorder(
      entries: entries,
      selectedIds: {'b'},
      mode: 3,
    );

    expect(up, {'a': 'a2', 'b': 'a1'});
    expect(down, {'c': 'a2', 'b': 'a3'});
  });

  test('连续选择对象不会跨越同一选择集合', () {
    final result = EditorLayerOrderMutation.reorder(
      entries: entries,
      selectedIds: {'a', 'b'},
      mode: 2,
    );

    expect(result, isEmpty);
  });

  test('旧文档缺少 fractionalIndex 时使用 zOrder 参与排序但只返回写回键', () {
    final result = EditorLayerOrderMutation.reorder(
      entries: [
        const EditorLayerOrderEntry(
          id: 'old-a',
          fractionalIndex: null,
          zOrder: 1,
        ),
        const EditorLayerOrderEntry(
          id: 'old-b',
          fractionalIndex: null,
          zOrder: 2,
        ),
      ],
      selectedIds: {'old-b'},
      mode: 2,
    );

    expect(result, {'old-a': 'a0.268435458', 'old-b': 'a0.268435457'});
  });

  test('没有选中对象时不产生任何写回', () {
    final result = EditorLayerOrderMutation.reorder(
      entries: entries,
      selectedIds: const {},
      mode: 0,
    );

    expect(result, isEmpty);
  });
}
