// M11 契约测试：All Docs 排序（flattenSorted 纯函数）。
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/features/all_docs/application/all_doc_sort.dart';
import 'package:drawing_notes_app/features/all_docs/domain/all_doc.dart';

AllDoc _doc(String id, String title, DateTime updated, DateTime created) =>
    AllDoc(
      id: id,
      title: title,
      kind: AllDocKind.blockdoc,
      folder: '',
      createdAt: created,
      updatedAt: updated,
    );

void main() {
  final t1 = DateTime(2026, 8, 1);
  final t2 = DateTime(2026, 8, 2);
  final t3 = DateTime(2026, 8, 3);

  final sections = [
    AllDocSection(
      group: AllDocGroup.today,
      label: '今天',
      docs: [_doc('a', '设计稿', t3, t1), _doc('b', '会议记录', t2, t2)],
    ),
    AllDocSection(
      group: AllDocGroup.earlier,
      label: '更早',
      docs: [_doc('c', 'Alpha 笔记', t1, t3)],
    ),
  ];

  test('timeGrouped 返回 null（保持分组渲染）', () {
    expect(flattenSorted(sections, AllDocSort.timeGrouped), isNull);
  });

  test('按更新时间倒序', () {
    final out = flattenSorted(sections, AllDocSort.updatedAtDesc)!;
    expect(out.map((d) => d.id).toList(), ['a', 'b', 'c']);
  });

  test('按创建时间倒序', () {
    final out = flattenSorted(sections, AllDocSort.createdAtDesc)!;
    expect(out.map((d) => d.id).toList(), ['c', 'b', 'a']);
  });

  test('按标题升序（不区分大小写）', () {
    final out = flattenSorted(sections, AllDocSort.titleAsc)!;
    expect(out.map((d) => d.id).toList(), ['c', 'b', 'a']);
  });
}
