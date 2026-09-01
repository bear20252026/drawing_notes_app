// PBKDF2(600k) 用例在全量高并发下超默认 30s 超时，放宽到 3 分钟。
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/core/sync/sync_cipher.dart';

void main() {
  group('NoopSyncCipher', () {
    const cipher = NoopSyncCipher();

    test('remotePath 恒等', () {
      expect(cipher.remotePath('doc-123'), 'doc-123');
      expect(cipher.remotePath(''), '');
    });

    test('encrypt/decrypt 字节往返', () async {
      final plain = Uint8List.fromList([1, 2, 3, 255, 0, 128]);
      final cipherBytes = await cipher.encryptDocumentBytes(plain, 'd1');
      final restored = await cipher.decryptDocumentBytes(cipherBytes, 'd1');
      expect(restored, equals(plain));
    });

    test('seal/open 恒等', () async {
      final json = '{"hello":"world"}';
      final sealed = await cipher.sealManifestJson(json);
      expect(sealed, json);
      expect(await cipher.openManifestJson(sealed), json);
    });
  });

  group('AesSyncCipher 往返', () {
    final key = List<int>.generate(32, (i) => i + 1);
    final cipher = AesSyncCipher(key: key);

    test('同 key 同 docId encrypt→decrypt 还原明文', () async {
      final plain = utf8.encode('你好，世界！Hello World 123');
      final cipherBytes = await cipher.encryptDocumentBytes(
        Uint8List.fromList(plain),
        'doc-1',
      );
      final restored = await cipher.decryptDocumentBytes(cipherBytes, 'doc-1');
      expect(utf8.decode(restored), utf8.decode(plain));
    });

    test('mode/v/字段存在', () async {
      final cipherBytes = await cipher.encryptDocumentBytes(
        Uint8List.fromList([1, 2, 3]),
        'doc-1',
      );
      final map = jsonDecode(utf8.decode(cipherBytes)) as Map<String, dynamic>;
      expect(map['mode'], 'sync-doc');
      expect(map['v'], 1);
      expect(map['n'], isA<String>());
      expect(map['c'], isA<String>());
      expect(map['m'], isA<String>());
      // 可 base64 解码
      expect(base64Decode(map['n']), hasLength(12));
      expect(base64Decode(map['m']), hasLength(16));
    });

    test('nonce 每次不同（同明文两次密文不同）但可解', () async {
      final plain = Uint8List.fromList(utf8.encode('same plaintext'));
      final c1 = await cipher.encryptDocumentBytes(plain, 'doc-1');
      final c2 = await cipher.encryptDocumentBytes(plain, 'doc-1');
      expect(c1, isNot(equals(c2)));
      // 但两者都能解密
      expect(await cipher.decryptDocumentBytes(c1, 'doc-1'), plain);
      expect(await cipher.decryptDocumentBytes(c2, 'doc-1'), plain);
    });
  });

  group('AesSyncCipher AAD 绑定', () {
    final key = List<int>.generate(32, (i) => i + 1);
    final cipher = AesSyncCipher(key: key);

    test('用 A 的 docId 加密、用 B 的 docId 解密 → 抛异常', () async {
      final plain = Uint8List.fromList(utf8.encode('secret'));
      final cipherBytes = await cipher.encryptDocumentBytes(plain, 'doc-A');
      expect(
        () => cipher.decryptDocumentBytes(cipherBytes, 'doc-B'),
        throwsA(isA<FormatException>()),
      );
    });

    test('用错 key 解密 → 抛异常', () async {
      final plain = Uint8List.fromList(utf8.encode('secret'));
      final cipherBytes = await cipher.encryptDocumentBytes(plain, 'doc-1');
      final wrongCipher = AesSyncCipher(
        key: List<int>.generate(32, (i) => i + 99),
      );
      expect(
        () => wrongCipher.decryptDocumentBytes(cipherBytes, 'doc-1'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('AesSyncCipher manifest 密封', () {
    final key = List<int>.generate(32, (i) => i + 1);
    final cipher = AesSyncCipher(key: key);

    test('seal/open 往返', () async {
      final json = '{"entries":{},"deletedIds":[]}';
      final sealed = await cipher.sealManifestJson(json);
      expect(sealed, isNot(equals(json))); // 密文 ≠ 明文
      expect(await cipher.openManifestJson(sealed), json);
    });

    test('密封被挪到错 key 打开 → 抛异常', () async {
      final json = '{"entries":{}}';
      final sealed = await cipher.sealManifestJson(json);
      final wrongCipher = AesSyncCipher(
        key: List<int>.generate(32, (i) => i + 99),
      );
      expect(
        () => wrongCipher.openManifestJson(sealed),
        throwsA(isA<FormatException>()),
      );
    });

    test('mode 不匹配 → 抛异常', () async {
      // 用 sync-doc 字节当 manifest 打开
      final cipherBytes = await cipher.encryptDocumentBytes(
        Uint8List.fromList(utf8.encode('x')),
        'doc-1',
      );
      final sealedStr = utf8.decode(cipherBytes);
      expect(
        () => cipher.openManifestJson(sealedStr),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('AesSyncCipher remotePath', () {
    final key = List<int>.generate(32, (i) => i + 1);
    final cipher = AesSyncCipher(key: key);

    test('确定性：同 docId 两次同值', () {
      expect(cipher.remotePath('doc-1'), cipher.remotePath('doc-1'));
    });

    test('对 docId 敏感：不同 docId 不同值', () {
      expect(cipher.remotePath('doc-1'), isNot(cipher.remotePath('doc-2')));
    });

    test('不可逆：64 hex、不含原 id', () {
      final path = cipher.remotePath('my-doc-id');
      expect(path.length, 64);
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(path), isTrue);
      expect(path, isNot(contains('my-doc-id')));
    });
  });

  group('密钥派生工具', () {
    test('同 password+salt → 同 key', () async {
      final salt = generateSalt();
      final k1 = await deriveMasterKey('pw', salt);
      final k2 = await deriveMasterKey('pw', salt);
      expect(k1, equals(k2));
      expect(k1.length, 32);
    });

    test('不同 password → 不同 key', () async {
      final salt = generateSalt();
      final k1 = await deriveMasterKey('pw1', salt);
      final k2 = await deriveMasterKey('pw2', salt);
      expect(k1, isNot(equals(k2)));
    });

    test('不同 salt → 不同 key', () async {
      final k1 = await deriveMasterKey('pw', generateSalt());
      final k2 = await deriveMasterKey('pw', generateSalt());
      expect(k1, isNot(equals(k2)));
    });

    test('generateSalt 两次不同、长度 16', () {
      final s1 = generateSalt();
      final s2 = generateSalt();
      expect(s1.length, 16);
      expect(s2.length, 16);
      expect(s1, isNot(equals(s2)));
    });
  });
}
