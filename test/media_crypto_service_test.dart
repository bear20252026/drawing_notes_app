// K_note 接线（2026-11-16）：媒体加密改为每笔记本独立密钥（LRU 映射，
// 上限 32），删除全局会话密码派生路径。本套件不再含真 KDF 派生——
// 去掉 kdf 标签（密钥直接注入，无 Argon2id 计算）。

import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/security/media_crypto_service.dart';
import 'package:drawing_notes_app/core/security/session_secrets.dart';

/// MediaCryptoService——BusinessCrypto 层媒体加密（K_note 每笔记本密钥
/// 注入/清除 + AES-GCM 加解密 + LRU 上限 + AAD 绑定笔记本）。
void main() {
  setUp(MediaCryptoService.instance.clearSessionKey);
  tearDown(MediaCryptoService.instance.clearSessionKey);

  final key = List<int>.generate(32, (i) => i);
  Uint8List plainOf(String s) => Uint8List.fromList(s.codeUnits);

  test('媒体加密：注入笔记本密钥后往返解密', () async {
    MediaCryptoService.instance.setNotebookKey('nb1', key);
    final plain = plainOf('机密图片字节');
    final enc = await MediaCryptoService.instance.encryptBytes('nb1', plain);
    expect(enc.length, greaterThan(plain.length));
    final dec = await MediaCryptoService.instance.decryptBytes('nb1', enc);
    expect(dec, plain);
  });

  test('媒体加密：未注入密钥时抛 StateError', () async {
    expect(
      () => MediaCryptoService.instance.encryptBytes('nb1', Uint8List(4)),
      throwsStateError,
    );
    expect(
      () => MediaCryptoService.instance.decryptBytes('nb1', Uint8List(32)),
      throwsStateError,
    );
  });

  test('媒体加密：错误密钥解密认证失败', () async {
    MediaCryptoService.instance.setNotebookKey('nb1', key);
    final enc = await MediaCryptoService.instance.encryptBytes(
      'nb1',
      plainOf('数据'),
    );
    MediaCryptoService.instance.setNotebookKey(
      'nb1',
      List<int>.generate(32, (i) => i + 1),
    );
    expect(
      () => MediaCryptoService.instance.decryptBytes('nb1', enc),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });

  test('跨笔记隔离：同密钥不同 notebookId 也不能互解（AAD 绑定）', () async {
    // 即使两本笔记注入同一把密钥，AAD 含 notebookId——密文不可跨笔记移植。
    MediaCryptoService.instance.setNotebookKey('noteA', key);
    MediaCryptoService.instance.setNotebookKey('noteB', key);
    final enc = await MediaCryptoService.instance.encryptBytes(
      'noteA',
      plainOf('笔记A媒体'),
    );
    expect(
      () => MediaCryptoService.instance.decryptBytes('noteB', enc),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
    expect(
      await MediaCryptoService.instance.decryptBytes('noteA', enc),
      plainOf('笔记A媒体'),
    );
  });

  test('跨笔记隔离：不同 K_note 互解失败', () async {
    MediaCryptoService.instance.setNotebookKey('noteA', key);
    final enc = await MediaCryptoService.instance.encryptBytes(
      'noteA',
      plainOf('笔记A媒体'),
    );
    MediaCryptoService.instance.setNotebookKey(
      'noteB',
      List<int>.generate(32, (i) => i + 1),
    );
    expect(
      () => MediaCryptoService.instance.decryptBytes('noteB', enc),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });

  test('clearNotebookKey：只清指定笔记本，其他不受影响', () async {
    MediaCryptoService.instance.setNotebookKey('noteA', key);
    MediaCryptoService.instance.setNotebookKey('noteB', key);
    MediaCryptoService.instance.clearNotebookKey('noteA');
    expect(MediaCryptoService.instance.hasKeyFor('noteA'), isFalse);
    expect(MediaCryptoService.instance.hasKeyFor('noteB'), isTrue);
    expect(MediaCryptoService.instance.isActive, isTrue);
    expect(
      () => MediaCryptoService.instance.encryptBytes('noteA', Uint8List(4)),
      throwsStateError,
    );
  });

  test('clearSessionKey：清除全部后不可用', () async {
    MediaCryptoService.instance.setNotebookKey('noteA', key);
    MediaCryptoService.instance.setNotebookKey('noteB', key);
    expect(MediaCryptoService.instance.isActive, isTrue);
    MediaCryptoService.instance.clearSessionKey();
    expect(MediaCryptoService.instance.isActive, isFalse);
    expect(
      () => MediaCryptoService.instance.decryptBytes('noteA', Uint8List(32)),
      throwsStateError,
    );
  });

  test('SessionSecrets 联动：回锁清零全部笔记本密钥', () async {
    MediaCryptoService.instance.setNotebookKey('noteA', key);
    MediaCryptoService.instance.setNotebookKey('noteB', key);
    SessionSecrets.clearAll();
    expect(MediaCryptoService.instance.isActive, isFalse);
    expect(MediaCryptoService.instance.hasKeyFor('noteA'), isFalse);
    expect(MediaCryptoService.instance.hasKeyFor('noteB'), isFalse);
  });

  group('LRU 映射（业主决策：上限 32 本）', () {
    test('超上限逐出最久未用（密钥不可再用）', () async {
      final svc = MediaCryptoService.instance;
      for (var i = 0; i < MediaCryptoService.maxNotebookKeys; i++) {
        svc.setNotebookKey('nb$i', key);
      }
      expect(svc.hasKeyFor('nb0'), isTrue);
      // 第 33 本 → 逐出最久未用 nb0。
      svc.setNotebookKey('nb-extra', key);
      expect(svc.hasKeyFor('nb0'), isFalse, reason: '最久未用应被逐出');
      expect(svc.hasKeyFor('nb-extra'), isTrue);
      expect(svc.hasKeyFor('nb1'), isTrue);
      expect(
        () => svc.encryptBytes('nb0', Uint8List(4)),
        throwsStateError,
        reason: '逐出后密钥已零化，须重新解包注入',
      );
    });

    test('命中刷新 LRU 序：最近使用的不会被逐出', () async {
      final svc = MediaCryptoService.instance;
      for (var i = 0; i < MediaCryptoService.maxNotebookKeys; i++) {
        svc.setNotebookKey('nb$i', key);
      }
      // 使用 nb0（最旧）→ 移到队尾。
      await svc.encryptBytes('nb0', plainOf('x'));
      svc.setNotebookKey('nb-extra', key);
      expect(svc.hasKeyFor('nb0'), isTrue, reason: '刚使用过不应被逐出');
      expect(svc.hasKeyFor('nb1'), isFalse, reason: 'nb1 成为最久未用');
    });

    test('重复注入同笔记本 = 覆盖（不占额外名额）', () {
      final svc = MediaCryptoService.instance;
      for (var i = 0; i < MediaCryptoService.maxNotebookKeys; i++) {
        svc.setNotebookKey('nb$i', key);
      }
      svc.setNotebookKey('nb0', List<int>.generate(32, (i) => i + 1));
      expect(svc.hasKeyFor('nb0'), isTrue);
      expect(svc.hasKeyFor('nb31'), isTrue, reason: '覆盖不应触发逐出');
    });
  });

  group('DAN 文件封装', () {
    test('encryptFile/readMediaFile 往返（按笔记本）', () async {
      MediaCryptoService.instance.setNotebookKey('nb1', key);
      final plain = plainOf('图片字节');
      final file = await MediaCryptoService.instance.encryptFile('nb1', plain);
      expect(MediaCryptoService.isEncryptedFile(file), isTrue);
      final dec = await MediaCryptoService.instance.readMediaFile('nb1', file);
      expect(dec, plain);
    });

    test('readMediaFile：明文原样返回（未加密笔记本）', () async {
      final plain = plainOf('明文图片');
      final dec = await MediaCryptoService.instance.readMediaFile('nb1', plain);
      expect(dec, plain);
    });

    test('DAN 密文跨笔记本读取失败（AAD 绑定）', () async {
      MediaCryptoService.instance.setNotebookKey('nb1', key);
      MediaCryptoService.instance.setNotebookKey('nb2', key);
      final file = await MediaCryptoService.instance.encryptFile(
        'nb1',
        plainOf('图片'),
      );
      expect(
        () => MediaCryptoService.instance.readMediaFile('nb2', file),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });
  });

  test('generateNotebookKey：32B 随机且两次不同', () {
    final k1 = MediaCryptoService.generateNotebookKey();
    final k2 = MediaCryptoService.generateNotebookKey();
    expect(k1.length, 32);
    expect(k2.length, 32);
    expect(k1, isNot(equals(k2)));
  });
}