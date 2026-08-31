// P3-3 契约测试：NoteAttachment 附件/PDF/书签卡领域模型。
// 由 lead 先写（锁定 API 契约），队友 B 实现 lib/features/notes/domain/note_attachment.dart 使其通过。
import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/features/doc/domain/note_attachment.dart';

void main() {
  group('AttachmentKind', () {
    test('三种类型', () {
      expect(AttachmentKind.values, [
        AttachmentKind.file,
        AttachmentKind.pdf,
        AttachmentKind.bookmark,
      ]);
    });
  });

  group('NoteAttachment 基础', () {
    test('默认字段', () {
      final a = NoteAttachment(
        id: 'a1',
        name: '附件',
        kind: AttachmentKind.file,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      expect(a.id, 'a1');
      expect(a.name, '附件');
      expect(a.kind, AttachmentKind.file);
      expect(a.mimeType, '');
      expect(a.byteSize, 0);
      expect(a.filePath, '');
      expect(a.url, '');
      expect(a.description, '');
    });

    test('isEmbeddable：pdf/bookmark 内嵌，file 非内嵌', () {
      final base = NoteAttachment(
        id: 'a',
        name: 'n',
        kind: AttachmentKind.file,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      expect(base.isEmbeddable, isFalse);
      expect(base.copyWith(kind: AttachmentKind.pdf).isEmbeddable, isTrue);
      expect(base.copyWith(kind: AttachmentKind.bookmark).isEmbeddable, isTrue);
    });

    test('displaySubtitle：PDF 显示 mime+大小，file 显示大小，bookmark 显示 url', () {
      final pdf = NoteAttachment(
        id: 'a',
        name: '报告.pdf',
        kind: AttachmentKind.pdf,
        mimeType: 'application/pdf',
        byteSize: 2048,
        url: 'https://cdn.example.com/report.pdf',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      expect(pdf.displaySubtitle, contains('PDF'));
      expect(pdf.displaySubtitle, contains('2 KB'));

      final file = NoteAttachment(
        id: 'b',
        name: 'data.zip',
        kind: AttachmentKind.file,
        byteSize: 1024,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      expect(file.displaySubtitle, contains('1 KB'));

      final bm = NoteAttachment(
        id: 'c',
        name: '官网',
        kind: AttachmentKind.bookmark,
        url: 'https://example.com',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      expect(bm.displaySubtitle, contains('https://example.com'));
    });

    test('copyWith 不可变更新', () {
      final a = NoteAttachment(
        id: 'a',
        name: 'n',
        kind: AttachmentKind.file,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      final a2 = a.copyWith(name: 'renamed', byteSize: 99);
      expect(a2.name, 'renamed');
      expect(a2.byteSize, 99);
      expect(a.name, 'n', reason: '不可变');
      expect(a.byteSize, 0, reason: '不可变');
    });
  });

  group('序列化与相等', () {
    test('toJson/fromJson 往返', () {
      final a = NoteAttachment(
        id: 'a1',
        name: '报告.pdf',
        kind: AttachmentKind.pdf,
        mimeType: 'application/pdf',
        byteSize: 2048,
        filePath: 'C:/files/report.pdf',
        url: 'https://cdn.example.com/report.pdf',
        description: '季度报告',
        createdAt: DateTime.utc(2026, 1, 2),
        updatedAt: DateTime.utc(2026, 1, 3),
      );
      final back = NoteAttachment.fromJson(a.toJson());
      expect(back, a);
      expect(back.createdAt, DateTime.utc(2026, 1, 2));
    });

    test('相等性', () {
      final a = NoteAttachment(
        id: 'a',
        name: 'n',
        kind: AttachmentKind.file,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      final b = NoteAttachment(
        id: 'a',
        name: 'n',
        kind: AttachmentKind.file,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      final c = a.copyWith(name: 'other');
      expect(a, b);
      expect(a == c, isFalse);
    });

    test('helperChecks 大小格式化：0/小数 KB', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(500), '500 B');
      expect(formatBytes(2048), '2 KB');
    });
  });
}
