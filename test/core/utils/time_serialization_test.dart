// 时区/UTC 兼容迁移回归测试（G15 2026-09-07）。
//
// 覆盖三态时间串 + 跨时区 LWW 一致性：
//   - 写侧 timeToIso 统一输出 UTC `Z` 后缀（跨时区读数恒定）；
//   - 读侧 timeFromIso 兼容 `Z` / 带偏移 / 历史无偏移三种字符串，归一到
//     设备本地（展示层读到正确的本地钟面，比较按绝对时刻）；
//   - timeFromIsoOrNull 保留「非法即 null」的严格语义；
//   - 四个聚合根 toJson/fromJson 往返保持绝对时刻，且新写入携带 `Z`。

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/utils/time_serialization.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block_doc.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook_entity.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook_page.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook_page_content.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('timeToIso 写侧：统一 UTC Z 后缀', () {
    test('本地 DateTime 序列化为带 Z 的 UTC 串', () {
      final local = DateTime(2026, 9, 7, 12, 30, 0); // 本地钟面 12:30
      final iso = timeToIso(local);
      expect(iso.endsWith('Z'), isTrue, reason: '必须带 UTC Z 后缀');
      // 序列化值代表与本地同一绝对时刻的 UTC 钟面。
      expect(
        DateTime.parse(iso),
        local.toUtc(),
        reason: 'Z 串解析回 UTC 应等于 local.toUtc()',
      );
    });

    test('UTC DateTime 序列化同样带 Z 且字节不变（对既有 UTC 数据无扰动）', () {
      final utc = DateTime.utc(2026, 9, 7, 12, 30, 0);
      expect(timeToIso(utc), utc.toIso8601String());
      expect(timeToIso(utc).endsWith('Z'), isTrue);
    });
  });

  group('timeFromIso 读侧：三态兼容', () {
    test('UTC Z 串解析为准确时刻并落到本地钟面', () {
      final utc = DateTime.utc(2026, 9, 7, 12, 30, 0);
      final read = timeFromIso('2026-09-07T12:30:00.000Z');
      // 绝对时刻不变。
      expect(read.toUtc(), utc);
      // 展示层读到的本地钟面应等于把该时刻转换到本地后的结果。
      expect(read, utc.toLocal());
    });

    test('带偏移串解析为准确时刻', () {
      // +08:00 的 12:30 即 UTC 04:30。
      final read = timeFromIso('2026-09-07T12:30:00.000+08:00');
      expect(read.toUtc(), DateTime.utc(2026, 9, 7, 4, 30, 0));
    });

    test('历史无偏移串按本地解读，展示层钟面不变（兼容存量）', () {
      // 旧数据：本地 toIso8601String 无时区标注，跨时区读出本地钟面。
      final read = timeFromIso('2026-09-07T12:30:00');
      expect(read.year, 2026);
      expect(read.month, 9);
      expect(read.day, 7);
      expect(read.hour, 12);
      expect(read.minute, 30);
      // 无偏移串按本地解析，toLocal() 幂等。
      expect(read.isUtc, isFalse);
    });

    test('缺字段/非法返回 fallback；OrNull 变体返回 null', () {
      expect(timeFromIso(null), isA<DateTime>());
      final fallback = DateTime.utc(2000, 1, 1);
      expect(timeFromIso('不是时间', fallback: fallback), fallback);
      expect(timeFromIsoOrNull('不是时间'), isNull);
      expect(timeFromIsoOrNull(null), isNull);
    });
  });

  group('跨时区 LWW/epoch 一致性', () {
    test('同一绝对时刻的不同时区表示归一到相同 epoch 毫秒', () {
      // 同一时刻在三个时区的 ISO 串（Z / +08 / -05）必须解析到同一瞬时。
      final z = timeFromIso('2026-09-07T04:30:00.000Z');
      final p8 = timeFromIso('2026-09-07T12:30:00.000+08:00');
      final m5 = timeFromIso('2026-09-06T23:30:00.000-05:00');
      expect(z.millisecondsSinceEpoch, p8.millisecondsSinceEpoch);
      expect(z.millisecondsSinceEpoch, m5.millisecondsSinceEpoch);
      // 都是本地表示（展示正常）。
      expect(z.isUtc, isFalse);
      expect(p8.isUtc, isFalse);
      expect(m5.isUtc, isFalse);
    });
  });

  group('聚合根往返保持绝对时刻且新写入带 Z', () {
    DrawingDocument doc() => DrawingDocument(
      id: 'doc1',
      title: '画布',
      createdAt: DateTime.utc(2026, 9, 7, 3, 0, 0),
      updatedAt: DateTime.utc(2026, 9, 7, 4, 0, 0),
    );

    NotebookPage page() => NotebookPage(
      id: 'p1',
      title: '页',
      content: NotebookPageContent(document: doc()),
      createdAt: DateTime.utc(2026, 9, 7, 3, 0, 0),
      updatedAt: DateTime.utc(2026, 9, 7, 5, 0, 0),
      lastOpenedAt: DateTime.utc(2026, 9, 7, 6, 0, 0),
    );

    test('DrawingDocument', () {
      final json = doc().toJson();
      expect(json['createdAt'] as String, endsWith('Z'));
      final back = DrawingDocument.fromJson(json);
      expect(back.createdAt.toUtc(), doc().createdAt);
      expect(back.updatedAt.toUtc(), doc().updatedAt);
    });

    test('NotebookPage（含 lastOpenedAt）', () {
      final json = page().toJson();
      expect(json['createdAt'] as String, endsWith('Z'));
      expect(json['updatedAt'] as String, endsWith('Z'));
      expect(json['lastOpenedAt'] as String, endsWith('Z'));
      final back = NotebookPage.fromJson(json);
      expect(back.createdAt.toUtc(), page().createdAt);
      expect(back.updatedAt.toUtc(), page().updatedAt);
      expect(back.lastOpenedAt!.toUtc(), page().lastOpenedAt);
    });

    test('Notebook', () {
      final nb = Notebook(
        id: 'nb1',
        title: '笔记本',
        pages: [page()],
        createdAt: DateTime.utc(2026, 9, 7, 3, 0, 0),
        updatedAt: DateTime.utc(2026, 9, 7, 5, 0, 0),
      );
      final json = nb.toJson();
      expect(json['createdAt'] as String, endsWith('Z'));
      expect(json['updatedAt'] as String, endsWith('Z'));
      final back = Notebook.fromJson(json);
      expect(back.createdAt.toUtc(), nb.createdAt);
      expect(back.updatedAt.toUtc(), nb.updatedAt);
      expect(back.pages.single.lastOpenedAt!.toUtc(), page().lastOpenedAt);
    });

    test('NoteBlockDoc', () {
      final bd = NoteBlockDoc(
        id: 'bd1',
        title: '块文档',
        createdAt: DateTime.utc(2026, 9, 7, 3, 0, 0),
        updatedAt: DateTime.utc(2026, 9, 7, 4, 0, 0),
      );
      final json = bd.toJson();
      expect(json['createdAt'] as String, endsWith('Z'));
      expect(json['updatedAt'] as String, endsWith('Z'));
      final back = NoteBlockDoc.fromJson(json);
      expect(back.createdAt.toUtc(), bd.createdAt);
      expect(back.updatedAt.toUtc(), bd.updatedAt);
    });

    test('NoteBlockDoc 缺失字段回退 epoch 0（保持旧契约）', () {
      final back = NoteBlockDoc.fromJson(const {'id': 'x'});
      expect(back.createdAt, DateTime.fromMillisecondsSinceEpoch(0));
      expect(back.updatedAt, DateTime.fromMillisecondsSinceEpoch(0));
    });
  });
}
