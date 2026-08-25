import 'package:test/test.dart';

import 'package:editor_core/editor_core.dart';

/// PageV2 分页模型测试（多页画布——不可变——纯 Dart 可测试）。
void main() {
  group('PageV2', () {
    test('构造 + 字段访问', () {
      const doc = DocumentV2(id: 'd1', pageCount: 1);
      const page = PageV2(id: 'p1', document: doc, index: 0);
      expect(page.id, 'p1');
      expect(page.document.id, 'd1');
      expect(page.index, 0);
    });

    test('copyWith 保持 id 不变', () {
      const doc1 = DocumentV2(id: 'd1', pageCount: 1);
      const doc2 = DocumentV2(id: 'd2', pageCount: 2);
      const page = PageV2(id: 'p1', document: doc1, index: 0);
      final updated = page.copyWith(document: doc2, index: 1);

      expect(page.document.id, 'd1'); // 原实例不变。
      expect(page.index, 0);
      expect(updated.document.id, 'd2');
      expect(updated.index, 1);
      expect(updated.id, 'p1'); // id 保留。
    });

    test('copyWith 部分更新', () {
      const doc = DocumentV2(id: 'd1', pageCount: 1);
      const page = PageV2(id: 'p1', document: doc, index: 0);
      final updated = page.copyWith(index: 5);
      expect(updated.index, 5);
      expect(updated.document.id, 'd1'); // document 保留。
    });

    test('相等性基于 id + document + index', () {
      const doc = DocumentV2(id: 'd1', pageCount: 1);
      const a = PageV2(id: 'p1', document: doc, index: 0);
      const b = PageV2(id: 'p1', document: doc, index: 0);
      const c = PageV2(id: 'p2', document: doc, index: 0);
      expect(a, b);
      expect(a == c, isFalse);
    });

    test('hashCode 一致', () {
      const doc = DocumentV2(id: 'd1', pageCount: 1);
      const a = PageV2(id: 'p1', document: doc, index: 0);
      const b = PageV2(id: 'p1', document: doc, index: 0);
      expect(a.hashCode, b.hashCode);
    });
  });

  group('DocumentV2', () {
    test('默认 revision 为 0', () {
      const doc = DocumentV2(id: 'd1', pageCount: 3);
      expect(doc.revision, 0);
      expect(doc.layers, isEmpty);
    });

    test('copyWith 保持 id 不变', () {
      const doc = DocumentV2(id: 'd1', pageCount: 1);
      final updated = doc.copyWith(pageCount: 5, revision: 3);
      expect(doc.pageCount, 1); // 原实例不变。
      expect(doc.revision, 0);
      expect(updated.pageCount, 5);
      expect(updated.revision, 3);
      expect(updated.id, 'd1'); // id 保留。
    });

    test('toJson 序列化 + fromJson 反序列化往返', () {
      const doc = DocumentV2(id: 'd1', pageCount: 3, revision: 7);
      final json = doc.toJson();
      expect(json['id'], 'd1');
      expect(json['pageCount'], 3);
      expect(json['revision'], 7);

      final restored = DocumentV2.fromJson(json);
      expect(restored.id, 'd1');
      expect(restored.pageCount, 3);
      expect(restored.revision, 7);
    });

    test('相等性基于 id + pageCount + revision', () {
      const a = DocumentV2(id: 'd1', pageCount: 1);
      const b = DocumentV2(id: 'd1', pageCount: 1);
      const c = DocumentV2(id: 'd1', pageCount: 2);
      expect(a, b);
      expect(a == c, isFalse);
    });
  });
}
