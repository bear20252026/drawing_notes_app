// M11 契约测试：All Docs 搜索过滤纯函数（all_doc_search.dart）。
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/features/all_docs/application/all_doc_search.dart';
import 'package:drawing_notes_app/features/all_docs/domain/all_doc.dart';

AllDoc _doc(String id, String title, {String desc = ''}) => AllDoc(
  id: id,
  title: title,
  kind: AllDocKind.blockdoc,
  folder: '',
  createdAt: DateTime(2026, 8, 1),
  updatedAt: DateTime(2026, 8, 2),
  description: desc,
);

void main() {
  test('空查询原样返回', () {
    final sections = [
      AllDocSection(
        group: AllDocGroup.today,
        label: '今天',
        docs: [_doc('a', '设计稿')],
      ),
    ];
    expect(filterSections(sections, ''), same(sections));
    expect(filterSections(sections, '   '), same(sections));
  });

  test('标题大小写不敏感包含匹配', () {
    final sections = [
      AllDocSection(
        group: AllDocGroup.today,
        label: '今天',
        docs: [_doc('a', 'Meeting Notes'), _doc('b', '设计稿')],
      ),
    ];
    final out = filterSections(sections, 'meeting');
    expect(out.single.docs.map((d) => d.id), ['a']);
  });

  test('description 也可命中', () {
    final sections = [
      AllDocSection(
        group: AllDocGroup.today,
        label: '今天',
        docs: [_doc('a', '草稿', desc: '关于绘图引擎的调研')],
      ),
    ];
    final out = filterSections(sections, '引擎');
    expect(out.single.docs.single.id, 'a');
  });

  test('无命中的区段被剔除', () {
    final sections = [
      AllDocSection(
        group: AllDocGroup.today,
        label: '今天',
        docs: [_doc('a', '设计稿')],
      ),
      AllDocSection(
        group: AllDocGroup.earlier,
        label: '更早',
        docs: [_doc('b', '旧笔记')],
      ),
    ];
    final out = filterSections(sections, '设计');
    expect(out.length, 1);
    expect(out.single.label, '今天');
  });
}
