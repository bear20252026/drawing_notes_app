// 修复 2 回归锁：达阈值的同步 AES-GCM 载荷离开主 isolate（SyncService
// 逐文档加解密，数十/数百条笔记时纯 Dart AES 挤占主线程 → UI 掉帧），
// 且两条路径必须产出**可互相解回**的字节（跨设备/跨版本互操作的前提）。
//
// 路径由 `AesSyncCipher(isolateThreshold:)` 逼迫：极大值 = 永不进 isolate，
// 0 = 必进 isolate。同一份明文分别用两侧加密/解密，验的是「下沉只是换了
// 执行位置，没换格式与语义」。
//
// 同时锁死泄密红线：主密钥/口令不得出现在异常文案或审计日志里。

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/security/audit_logger.dart';
import 'package:drawing_notes_app/core/sync/sync_cipher.dart';
import 'package:drawing_notes_app/features/notes/presentation/webdav_sync_settings_page.dart'
    show humanizeWebDavSyncError;

final _key = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));
final _otherKey = Uint8List.fromList(List<int>.generate(32, (i) => i + 99));

/// 永不进 isolate（全部主线程）。
AesSyncCipher inlineCipher(List<int> key) =>
    AesSyncCipher(key: key, isolateThreshold: 1 << 30);

/// 任何载荷都进 worker isolate。
AesSyncCipher offloadCipher(List<int> key) =>
    AesSyncCipher(key: key, isolateThreshold: 0);

Uint8List _payload(int bytes) =>
    Uint8List.fromList(List<int>.generate(bytes, (i) => 32 + (i % 95)));

/// 密钥的所有可见形态（base64 / hex / 十进制串）——用于断言它们不外泄。
List<String> keyFormations(List<int> key) => [
  base64Encode(key),
  key.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
  key.join(','),
];

void main() {
  setUp(() => AuditLogger.clear());

  String allAudit() => AuditLogger.snapshot().join(' || ');

  group('阈值上下两条路径：字节可互相解回', () {
    for (final size in [64, 4096, 40 * 1024]) {
      test('载荷 $size 字节：主↔worker 双向', () async {
        final plain = _payload(size);
        final onMain = inlineCipher(_key);
        final onWorker = offloadCipher(_key);

        final fromMain = await onMain.encryptDocumentBytes(plain, 'doc-1');
        final fromWorker = await onWorker.encryptDocumentBytes(plain, 'doc-1');

        // 交叉解密：主线程加密的字节要能在 worker 里解回，反之亦然。
        expect(
          await onWorker.decryptDocumentBytes(fromMain, 'doc-1'),
          equals(plain),
          reason: 'worker 路径解不开主线程产出的字节 ⇒ 格式漂移',
        );
        expect(
          await onMain.decryptDocumentBytes(fromWorker, 'doc-1'),
          equals(plain),
          reason: '主线程解不开 worker 产出的字节 ⇒ 格式漂移',
        );

        // 线格式两侧同构（同 mode / 同 nonce+MAC 长度）。
        for (final wire in [fromMain, fromWorker]) {
          final map = jsonDecode(utf8.decode(wire)) as Map<String, dynamic>;
          expect(map['mode'], 'sync-doc');
          expect(map['v'], 1);
          expect(base64Decode(map['n'] as String), hasLength(12));
          expect(base64Decode(map['m'] as String), hasLength(16));
        }
      });
    }

    test('manifest 密封同理双向（大清单不例外）', () async {
      final manifest = jsonEncode({
        'entries': {
          for (var i = 0; i < 900; i++)
            'doc-$i': {
              'id': 'doc-$i',
              'updatedAt': 1700000000000 + i,
              'size': 4096,
            },
        },
        'deletedIds': <String>[],
      });
      expect(
        utf8.encode(manifest).length,
        greaterThan(AesSyncCipher.isolateCodecThreshold),
        reason: '样本必须达阈值，否则这条锁不住 worker 路径',
      );
      final sealedOnWorker = await offloadCipher(_key).sealManifestJson(manifest);
      expect(
        await inlineCipher(_key).openManifestJson(sealedOnWorker),
        manifest,
      );
      final sealedOnMain = await inlineCipher(_key).sealManifestJson(manifest);
      expect(
        await offloadCipher(_key).openManifestJson(sealedOnMain),
        manifest,
      );
    });
  });

  group('默认阈值：达 32 KiB 才进 isolate，两侧都要能往返', () {
    test('阈值常量取文档侧口径（32 KiB）', () {
      expect(AesSyncCipher.isolateCodecThreshold, 32 * 1024);
    });

    test('默认实例：小载荷与大载荷都成功往返', () async {
      final cipher = AesSyncCipher(key: _key);
      for (final size in [1024, 64 * 1024]) {
        final plain = _payload(size);
        final wire = await cipher.encryptDocumentBytes(plain, 'doc-9');
        expect(await cipher.decryptDocumentBytes(wire, 'doc-9'), equals(plain));
      }
    });

    test('默认阈值确实跨过分界（小载荷的密文 < 阈值、大载荷 ≥ 阈值）', () async {
      final small = await AesSyncCipher(key: _key).encryptDocumentBytes(
        _payload(1024),
        'doc-s',
      );
      final big = await AesSyncCipher(key: _key).encryptDocumentBytes(
        _payload(64 * 1024),
        'doc-b',
      );
      expect(small.length, lessThan(AesSyncCipher.isolateCodecThreshold));
      expect(big.length, greaterThanOrEqualTo(AesSyncCipher.isolateCodecThreshold));
    });
  });

  group('AAD 绑定与版本分支语义未变（两条路径同口径）', () {
    for (final cipherFactory in <AesSyncCipher Function()>[
      () => inlineCipher(_key),
      () => offloadCipher(_key),
    ]) {
      test('跨 docId 解密被拒 / 错 key 解密被拒 / mode 混用被拒', () async {
        final cipher = cipherFactory();
        final wire = await cipher.encryptDocumentBytes(_payload(4096), 'doc-A');

        // AAD 绑 docId：换 docId 就认证失败。
        await expectLater(
          cipher.decryptDocumentBytes(wire, 'doc-B'),
          throwsA(isA<SyncKeyMismatchException>()),
        );
        // 换 key 同样认证失败（修复 1 的判据类型）。
        await expectLater(
          offloadCipher(_otherKey).decryptDocumentBytes(wire, 'doc-A'),
          throwsA(isA<SyncKeyMismatchException>()),
        );
        // 仍是 FormatException 家族（既有调用方 on FormatException 不破）。
        await expectLater(
          cipher.decryptDocumentBytes(wire, 'doc-B'),
          throwsA(isA<FormatException>()),
        );
        // 文档密文当 manifest 打开 → mode 不匹配（不是认证失败）。
        await expectLater(
          cipher.openManifestJson(utf8.decode(wire)),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('mode 不匹配'),
            ),
          ),
        );
      });
    }

    test('畸形载荷仍按既有口径抛 FormatException（不是密钥错配）', () async {
      for (final cipher in [inlineCipher(_key), offloadCipher(_key)]) {
        await expectLater(
          cipher.decryptDocumentBytes(
            Uint8List.fromList(utf8.encode('{"mode":"sync-doc","v":1}')),
            'doc-A',
          ),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('缺少字段'),
            ),
          ),
        );
      }
    });
  });

  group('泄密红线：密钥/口令不进异常文案、UI 文案与审计日志', () {
    test('worker 路径的认证失败异常不带密钥任何形态', () async {
      final wire = await offloadCipher(_key).encryptDocumentBytes(
        _payload(40 * 1024),
        'doc-1',
      );
      late Object thrown;
      try {
        await offloadCipher(_otherKey).decryptDocumentBytes(wire, 'doc-1');
        fail('应当认证失败');
      } catch (e) {
        thrown = e;
      }
      final asText = thrown.toString();
      expect(thrown, isA<SyncKeyMismatchException>());
      // 异常原文是本地固定文案：既不含本端密钥，也不含对端密钥。
      for (final form in [
        ...keyFormations(_key),
        ...keyFormations(_otherKey),
      ]) {
        expect(asText, isNot(contains(form)), reason: '异常文案泄露密钥：$form');
      }
      // 载荷本体里的 base64 片段也不得被拼进异常（远端原文不进 UI）。
      expect(asText, isNot(contains(base64Encode(_payload(64)))));
    });

    test('humanize 给的是可执行静态文案，审计日志侧零密钥痕迹', () async {
      final wire = await offloadCipher(_key).encryptDocumentBytes(
        _payload(64 * 1024),
        'doc-1',
      );
      Object? thrown;
      try {
        await inlineCipher(_otherKey).decryptDocumentBytes(wire, 'doc-1');
      } catch (e) {
        thrown = e;
      }
      final ui = humanizeWebDavSyncError(thrown);
      expect(ui, contains('同步口令'));
      expect(ui, isNot(contains('检查网络')));
      expect(ui, isNot(contains('FormatException')));
      final audit = allAudit();
      expect(audit, contains('webdav.sync'));
      for (final form in [...keyFormations(_key), ...keyFormations(_otherKey)]) {
        expect(audit, isNot(contains(form)), reason: '审计日志泄露密钥');
      }
      expect(audit, isNot(contains(base64Encode(_payload(64)))));
    });

    test('密钥不进密文载荷（两侧路径都查）', () async {
      for (final cipher in [inlineCipher(_key), offloadCipher(_key)]) {
        final wire = utf8.decode(
          await cipher.encryptDocumentBytes(_payload(4096), 'doc-1'),
        );
        for (final form in keyFormations(_key)) {
          expect(wire, isNot(contains(form)));
        }
      }
    });
  });

  test('remotePath 语义未变：同 key 确定性、跨 key 全变（口令轮换的成因）', () {
    final a = AesSyncCipher(key: _key);
    final b = AesSyncCipher(key: _otherKey);
    expect(a.remotePath('doc-1'), a.remotePath('doc-1'));
    expect(a.remotePath('doc-1'), isNot(b.remotePath('doc-1')));
  });
}
