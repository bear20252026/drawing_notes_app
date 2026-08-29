// 由 Claude 团队生成 | Drawing Notes App
// AllDoc 领域模型 + 分组纯函数测试。

import 'package:drawing_notes_app/features/all_docs/domain/all_doc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AllDoc', () {
    final t0 = DateTime(2026, 1, 1);

    test('immutable with copyWith', () {
      final doc = AllDoc(
        id: '1',
        title: 'Doc',
        kind: AllDocKind.canvas,
        folder: '',
        createdAt: t0,
        updatedAt: t0,
      );
      final renamed = doc.copyWith(title: 'New');
      expect(renamed.title, 'New');
      expect(doc.title, 'Doc'); // 原对象未变
      expect(renamed.id, '1');
    });

    test('== and hashCode', () {
      final a = AllDoc(
        id: '1',
        title: 'Doc',
        kind: AllDocKind.canvas,
        folder: '',
        createdAt: t0,
        updatedAt: t0,
      );
      final b = AllDoc(
        id: '1',
        title: 'Doc',
        kind: AllDocKind.canvas,
        folder: '',
        createdAt: t0,
        updatedAt: t0,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);

      final c = a.copyWith(title: 'Other');
      expect(a, isNot(c));
    });

    test('dedupKey = kind:id', () {
      final doc = AllDoc(
        id: 'abc',
        title: '',
        kind: AllDocKind.note,
        folder: '',
        createdAt: t0,
        updatedAt: t0,
      );
      expect(doc.dedupKey, 'note:abc');
    });

    test('optional fields default correctly', () {
      final doc = AllDoc(
        id: '1',
        title: '',
        kind: AllDocKind.blockdoc,
        folder: '工作',
        createdAt: t0,
        updatedAt: t0,
      );
      expect(doc.description, '');
      expect(doc.isFavorite, isFalse);
      expect(doc.notebookId, isNull);
      expect(doc.pageId, isNull);
      expect(doc.drawingId, isNull);
    });
  });

  group('groupOf', () {
    final now = DateTime(2026, 8, 28, 12, 0); // 周四

    AllDoc mkDoc(DateTime created, DateTime updated) => AllDoc(
          id: 'x',
          title: '',
          kind: AllDocKind.canvas,
          folder: '',
          createdAt: created,
          updatedAt: updated,
        );

    test('today: updatedAt 与 now 同一天', () {
      final doc = mkDoc(DateTime(2026, 1, 1), DateTime(2026, 8, 28, 9, 0));
      expect(groupOf(doc, now: now), AllDocGroup.today);
    });

    test('today takes precedence over neverUpdated if same day', () {
      // createdAt == updatedAt == now（今天新建）→ today，不是 neverUpdated
      final doc = mkDoc(DateTime(2026, 8, 28, 10, 0), DateTime(2026, 8, 28, 10, 0));
      expect(groupOf(doc, now: now), AllDocGroup.today);
    });

    test('thisWeek: updatedAt 在本周内（非今天）', () {
      final doc = mkDoc(DateTime(2026, 1, 1), DateTime(2026, 8, 27, 15, 0)); // 昨天
      expect(groupOf(doc, now: now), AllDocGroup.thisWeek);

      final doc2 = mkDoc(DateTime(2026, 1, 1), DateTime(2026, 8, 24, 8, 0)); // 4天前
      expect(groupOf(doc2, now: now), AllDocGroup.thisWeek);
    });

    test('earlier: updatedAt 在 7 天前或更早', () {
      final doc = mkDoc(DateTime(2026, 1, 1), DateTime(2026, 8, 21, 12, 0)); // 7天前
      expect(groupOf(doc, now: now), AllDocGroup.earlier);

      final doc2 = mkDoc(DateTime(2026, 1, 1), DateTime(2026, 6, 1));
      expect(groupOf(doc2, now: now), AllDocGroup.earlier);
    });

    test('neverUpdated: updatedAt==createdAt 且早于今天', () {
      final doc = mkDoc(DateTime(2026, 5, 5, 10, 0), DateTime(2026, 5, 5, 10, 0));
      expect(groupOf(doc, now: now), AllDocGroup.neverUpdated);
    });

    test('neverUpdated requires different day from now', () {
      // 同一天创建且从未更新 → today（不是 neverUpdated）
      final doc = mkDoc(DateTime(2026, 8, 28, 8, 0), DateTime(2026, 8, 28, 8, 0));
      expect(groupOf(doc, now: now), AllDocGroup.today);
    });

    test('boundary: exactly 6 days ago → thisWeek', () {
      final doc = mkDoc(DateTime(2026, 1, 1), DateTime(2026, 8, 22, 12, 0));
      expect(groupOf(doc, now: now), AllDocGroup.thisWeek);
    });

    test('boundary: exactly 7 days ago → earlier', () {
      final doc = mkDoc(DateTime(2026, 1, 1), DateTime(2026, 8, 21, 12, 0));
      expect(groupOf(doc, now: now), AllDocGroup.earlier);
    });
  });

  group('labelForGroup / orderOfGroup', () {
    test('labels are non-empty and distinct', () {
      final labels = AllDocGroup.values.map(labelForGroup).toList();
      expect(labels.every((l) => l.isNotEmpty), isTrue);
      expect(labels.toSet().length, labels.length);
    });

    test('order is today=0, thisWeek=1, earlier=2, neverUpdated=3', () {
      expect(orderOfGroup(AllDocGroup.today), 0);
      expect(orderOfGroup(AllDocGroup.thisWeek), 1);
      expect(orderOfGroup(AllDocGroup.earlier), 2);
      expect(orderOfGroup(AllDocGroup.neverUpdated), 3);
    });
  });

  group('AllDocSection', () {
    test('== and isEmpty', () {
      final t0 = DateTime(2026, 1, 1);
      final doc = AllDoc(
        id: '1',
        title: '',
        kind: AllDocKind.canvas,
        folder: '',
        createdAt: t0,
        updatedAt: t0,
      );
      final s1 = AllDocSection(
          group: AllDocGroup.today, label: '今天', docs: [doc]);
      final s2 = AllDocSection(
          group: AllDocGroup.today, label: '今天', docs: [doc]);
      expect(s1, s2);
      expect(s1.isEmpty, isFalse);

      final empty =
          AllDocSection(group: AllDocGroup.today, label: '今天', docs: []);
      expect(empty.isEmpty, isTrue);
    });
  });

  group('determinism', () {
    test('groupOf is deterministic', () {
      final t0 = DateTime(2026, 1, 1);
      final doc = AllDoc(
        id: '1',
        title: '',
        kind: AllDocKind.canvas,
        folder: '',
        createdAt: t0,
        updatedAt: t0,
      );
      final now = DateTime(2026, 8, 28);
      final first = groupOf(doc, now: now);
      for (var i = 0; i < 10; i++) {
        expect(groupOf(doc, now: now), first);
      }
    });
  });
}
