// VFS 加密对象清单（vault_manifest.dart）单测：
// 序列化往返 / 版本链递增保留 / 版本门禁（拒绝未来版本）/ 损坏输入行为。

import 'dart:convert';

import 'package:drawing_notes_app/core/storage/vfs/vault_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

VaultManifestEntry _entry({
  required String id,
  int version = 1,
  String type = 'doc',
}) {
  return VaultManifestEntry(
    id: id,
    type: type,
    version: version,
    size: 128,
    aad: 'app|doc|$id|$version',
    modified: DateTime.utc(2026, 9, 1, 12, 30),
  );
}

void main() {
  group('序列化往返', () {
    test('encode→decode 保留全部条目字段', () {
      final manifest = VaultManifest(
        entries: [
          _entry(id: 'obj_a', version: 3),
          _entry(id: 'obj_b', version: 7, type: 'page'),
        ],
      );

      final decoded = VaultManifest.decode(manifest.encode());

      expect(decoded.entries, hasLength(2));
      final a = decoded.find('obj_a')!;
      expect(a.type, 'doc');
      expect(a.version, 3);
      expect(a.size, 128);
      expect(a.aad, 'app|doc|obj_a|3');
      expect(a.modified.toUtc(), DateTime.utc(2026, 9, 1, 12, 30));
      expect(decoded.find('obj_b')!.type, 'page');
    });

    test('toJson 是合法 JSON 且 format 版本为当前常量', () {
      final manifest = VaultManifest(entries: [_entry(id: 'obj_a')]);
      final raw = jsonDecode(manifest.encode()) as Map<String, dynamic>;

      expect(raw['format'], VaultManifest.formatVersion);
      expect(raw['format'], 1);
      expect((raw['entries'] as List), hasLength(1));
    });
  });

  group('版本链', () {
    test('对象版本递增（变更链 v1→v2→v3）在往返后逐级保留', () {
      // 模拟 openbucket 版本保留：同一对象每次变更 version+1，
      // AAD 上下文随之重绑（防拼接/重排——NIST SP 800-38D）。
      var manifest = VaultManifest(entries: [_entry(id: 'obj_a', version: 1)]);
      for (var v = 2; v <= 3; v++) {
        final next = VaultManifest(
          entries: [
            VaultManifestEntry(
              id: 'obj_a',
              type: 'doc',
              version: v,
              size: 128,
              aad: 'app|doc|obj_a|$v',
              modified: DateTime.utc(2026, 9, 1, 12, 30),
            ),
          ],
        );
        manifest = VaultManifest.decode(next.encode());
        expect(manifest.find('obj_a')!.version, v);
        expect(manifest.find('obj_a')!.aad, 'app|doc|obj_a|$v');
      }
    });

    test('find 命中已知 id、未知 id 返回 null', () {
      final manifest = VaultManifest(entries: [_entry(id: 'obj_a')]);

      expect(manifest.find('obj_a'), isNotNull);
      expect(manifest.find('missing'), isNull);
    });
  });

  group('版本门禁', () {
    test('缺失 format 字段被拒绝（FormatException）', () {
      const raw = '{"entries":[]}';
      expect(() => VaultManifest.decode(raw), throwsA(isA<FormatException>()));
    });

    test('未来版本（format=2）被拒绝，本版本（format=1）接受', () {
      expect(
        () => VaultManifest.decode('{"format":2,"entries":[]}'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('版本不支持'),
          ),
        ),
      );

      final ok = VaultManifest.decode('{"format":1,"entries":[]}');
      expect(ok.entries, isEmpty);
    });

    test('format 字段类型错（字符串）抛 TypeError 而非静默通过', () {
      expect(
        () => VaultManifest.decode('{"format":"1","entries":[]}'),
        throwsA(isA<TypeError>()),
      );
    });
  });

  group('损坏输入与空清单', () {
    test('空清单往返为空、find 恒 null', () {
      final decoded = VaultManifest.decode(
        VaultManifest(entries: const []).encode(),
      );

      expect(decoded.entries, isEmpty);
      expect(decoded.find('any'), isNull);
    });

    test('entries 缺失键按空清单处理', () {
      final decoded = VaultManifest.decode('{"format":1}');

      expect(decoded.entries, isEmpty);
    });

    test('条目缺必填字段（id/version）抛 TypeError', () {
      expect(
        () => VaultManifest.decode(
          '{"format":1,"entries":[{"type":"doc","size":1}]}',
        ),
        throwsA(isA<TypeError>()),
      );
      expect(
        () => VaultManifest.decode(
          '{"format":1,"entries":[{"id":"a","type":"doc","version":"1",'
          '"size":1,"aad":"x","modified":"2026-09-01T00:00:00Z"}]}',
        ),
        throwsA(isA<TypeError>()),
      );
    });

    test('modified 损坏（垃圾字符串/缺失）回退当前时间，不抛错', () {
      final decoded = VaultManifest.decode(
        '{"format":1,"entries":[{"id":"a","type":"doc","version":1,'
        '"size":1,"aad":"x","modified":"garbage"}]}',
      );

      expect(decoded.entries, hasLength(1));
      expect(
        decoded.find('a')!.modified.year,
        greaterThanOrEqualTo(2026),
        reason: '解析失败回退 DateTime.now()，而非 null/抛错',
      );
    });

    test('顶层非对象 JSON（数组）抛 TypeError', () {
      expect(() => VaultManifest.decode('[1,2]'), throwsA(isA<TypeError>()));
    });
  });
}
