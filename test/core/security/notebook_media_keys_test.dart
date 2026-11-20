// 框架级收口（2026-11-15）结构性回归：会话密钥编排器 NotebookMediaKeys。
//
// 钉住「被结构消解」的审计缺陷不再复发（每条对应一个 H/M）：
//  H-1 加密笔记本缺钥绝不落明文（sealMedia fail-closed，无明文回退）；
//  H-2 损坏槽/错密码 fail-closed，绝不懒补未持久化临时密钥；
//  H-3 并发 ensure 同本只生成一把 K_note（per-id 在途去重）；
//  M-2 LRU 逐出后 openMedia 自动重解包（不再渲染空白）；
//  M-4 回锁（SessionEpoch 翻篇）/页面遗忘（forget 世代）作废在途注入；
//  M-5 删除笔记本联动遗忘密钥。
//
// 真 Argon2id 派生用例打 kdf 标签参与 CI 分流。
@Tags(['kdf'])
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/security/media_crypto_service.dart';
import 'package:drawing_notes_app/core/security/notebook_media_keys.dart';
import 'package:drawing_notes_app/core/security/session_secrets.dart';
import 'package:drawing_notes_app/core/storage/encryption_service.dart';
import 'package:drawing_notes_app/core/storage/vault_file_codec.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/notebook_storage.dart';

import '../../helpers/temp_dir_cleanup.dart';

void main() {
  const enc = EncryptionService();
  const pw = 'orch-test-pw';
  final media = MediaCryptoService.instance;

  late Directory tempDir;
  late NotebookStorage storage;
  late NotebookMediaKeys keys;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('nb_keys_');
    media.clearSessionKey();
    // 与生产 app.dart 同一装配形状：单存储实例 + late 闭包端口。
    keys = NotebookMediaKeys(
      media: media,
      envelopes: _LatePort(() => storage),
    );
    storage = NotebookStorage(
      directoryProvider: () async => tempDir,
      mediaCrypto: media,
      mediaKeys: keys,
    );
  });

  tearDown(() async {
    media.clearSessionKey();
    await deleteTempDirWithRetry(tempDir);
  });

  Notebook nb(String id) => Notebook(id: id, title: '编排器测试本');
  Uint8List plainOf(String s) => Uint8List.fromList(utf8.encode(s));

  group('H-1：加密意图与可得性分离（无明文回退）', () {
    test('加密笔记本缺会话密码 → sealMedia 抛锁异常，绝不返回明文', () async {
      await storage.encryptAndSave(nb('nb-h1'), pw);
      storage.forgetNotebookPassword('nb-h1'); // 模拟回锁清口令
      await expectLater(
        keys.sealMedia('nb-h1', plainOf('图片')),
        throwsA(isA<VaultFileLockException>()),
      );
    });

    test('storeImage：加密笔记本缺钥 → 拒绝入库，磁盘零明文残留', () async {
      await storage.encryptAndSave(nb('nb-h1b'), pw);
      storage.forgetNotebookPassword('nb-h1b');
      final src = File('${tempDir.path}/src.png')
        ..writeAsBytesSync(plainOf('PNG'));
      await expectLater(
        storage.storeImage('nb-h1b', src.path, 'pg'),
        throwsA(isA<VaultFileLockException>()),
      );
      final imagesDir = Directory('${tempDir.path}/notebook_images');
      final files = imagesDir.existsSync()
          ? imagesDir.listSync().whereType<File>().toList()
          : <File>[];
      expect(files, isEmpty, reason: '加密笔记本不得有任何明文媒体落盘');
    });

    test('明文笔记本 → sealMedia 返回 null（走兼容分支，不强制加密）', () async {
      await storage.save(nb('nb-plain'));
      expect(await keys.sealMedia('nb-plain', plainOf('x')), isNull);
    });
  });

  group('H-2：三态契约（损坏槽/错密码不懒补）', () {
    test('media 槽损坏 → ensure 抛 FormatException，不注入临时密钥', () async {
      final notebook = nb('nb-h2');
      await storage.encryptAndSave(notebook, pw);
      // 篡改磁盘信封的 media 槽密文（槽存在但损坏）。
      final payload = notebook.encryptedPayload!;
      final map = jsonDecode(payload) as Map<String, dynamic>;
      final slot = (map['slots'] as Map<String, dynamic>)['media']
          as Map<String, dynamic>;
      final wrapped = base64Decode(slot['w'] as String);
      wrapped[0] ^= 0xFF;
      slot['w'] = base64Encode(wrapped);
      notebook.encryptedPayload = jsonEncode(map);
      await storage.save(notebook);
      await expectLater(
        keys.ensure('nb-h2'),
        throwsA(isA<FormatException>()),
        reason: '损坏槽必须 fail-closed——懒补会注入未持久化临时密钥（数据丢失）',
      );
      expect(media.hasKeyFor('nb-h2'), isFalse, reason: '不得注入任何临时密钥');
    });
  });

  group('H-3：并发 ensure 单密钥（per-id 在途去重）', () {
    test('同本并发 ensure → 只生成一把 K_note，信封槽唯一', () async {
      // 手工落无 media 槽的 v5 信封（懒补场景）。
      final notebook = nb('nb-h3');
      final envelope = await enc.encryptWithPasswordV5(
        notebookId: 'nb-h3',
        plaintext: '{"pages":[]}',
        password: pw,
      );
      final map = jsonDecode(envelope) as Map<String, dynamic>;
      (map['slots'] as Map<String, dynamic>).remove('media');
      notebook.encryptedPayload = jsonEncode(map);
      notebook.encrypted = true;
      await storage.save(notebook);
      expect(await storage.verifyNotebookPassword('nb-h3', pw), isTrue);

      // 并发 5 路 ensure——在途去重保证只生成一把密钥。
      await Future.wait([for (var i = 0; i < 5; i++) keys.ensure('nb-h3')]);
      expect(media.hasKeyFor('nb-h3'), isTrue);

      // 落盘信封解包出的密钥 == 驻留密钥加密的媒体可解（同一把）。
      final reloaded = await storage.load('nb-h3');
      final unwrapped = await enc.unwrapNotebookMediaKey(
        notebookId: 'nb-h3',
        encryptedJson: reloaded!.encryptedPayload!,
        password: pw,
      );
      final sealed = await media.encryptFile('nb-h3', plainOf('并发媒体'));
      media.clearNotebookKey('nb-h3');
      media.setNotebookKey('nb-h3', unwrapped!);
      expect(await media.readMediaFile('nb-h3', sealed), plainOf('并发媒体'));
    });

    test('H-3 交错补槽：attach 幂等 no-op → 必须以磁盘槽为准，不注入本地新钥',
        () async {
      // 场景：回锁清 _inflight 后新起的 ensure 与前一条在途任务交错——
      // 本任务 unwrap 时无槽 → 生成 keyB；attach 期间另一路已把 keyA 落盘，
      // attachMediaSlot 对已有槽幂等 no-op（不覆盖也不回传真实钥）。
      // 修复前会把 keyB 注入服务 → 此后密封的媒体磁盘上永久不可解。
      final notebook = nb('nb-h3x');
      final envelope = await enc.encryptWithPasswordV5(
        notebookId: 'nb-h3x',
        plaintext: '{"pages":[]}',
        password: pw,
      );
      final map = jsonDecode(envelope) as Map<String, dynamic>;
      (map['slots'] as Map<String, dynamic>).remove('media');
      notebook.encryptedPayload = jsonEncode(map);
      notebook.encrypted = true;
      await storage.save(notebook);
      expect(await storage.verifyNotebookPassword('nb-h3x', pw), isTrue);

      final port = _RacingPort(storage);
      final racing = NotebookMediaKeys(media: media, envelopes: port);
      await racing.ensure('nb-h3x');

      // 关键观测点：**首次 ensure 注入的那把钥**必须就是磁盘槽里的钥。
      // 此刻服务里驻留的正是刚注入的钥——用它密封，再拿磁盘槽钥去解。
      // 修复前注入的是本地新生成的 keyB，而磁盘槽是 rival 的 keyA → 解不开。
      final sealedByInjected = await media.encryptFile(
        'nb-h3x',
        plainOf('交错媒体'),
      );
      final reloaded = await storage.load('nb-h3x');
      final onDiskKey = await enc.unwrapNotebookMediaKey(
        notebookId: 'nb-h3x',
        encryptedJson: reloaded!.encryptedPayload!,
        password: pw,
      );
      media.clearNotebookKey('nb-h3x');
      media.setNotebookKey('nb-h3x', onDiskKey!);
      expect(
        await media.readMediaFile('nb-h3x', sealedByInjected),
        plainOf('交错媒体'),
        reason: '注入钥必须等于磁盘槽钥，否则此前密封的媒体永久不可解',
      );
    });
  });

  group('M-2：LRU 逐出后自动重解包', () {
    test('openMedia：密钥被逐出 → 经 ensure 重取钥解密成功', () async {
      await storage.encryptAndSave(nb('nb-m2'), pw);
      await keys.ensure('nb-m2');
      final sealed = await media.encryptFile('nb-m2', plainOf('逐出媒体'));
      media.clearNotebookKey('nb-m2'); // 模拟 LRU 逐出
      expect(media.hasKeyFor('nb-m2'), isFalse);
      // openMedia 自动 ensure 重解包——不再抛 StateError 渲染空白。
      expect(await keys.openMedia('nb-m2', sealed), plainOf('逐出媒体'));
      expect(media.hasKeyFor('nb-m2'), isTrue);
    });

    test('openMedia：DAN 缺笔记本上下文 → fail-closed', () async {
      await storage.encryptAndSave(nb('nb-m2b'), pw);
      await keys.ensure('nb-m2b');
      final sealed = await media.encryptFile('nb-m2b', plainOf('x'));
      await expectLater(
        keys.openMedia(null, sealed),
        throwsA(isA<StateError>()),
      );
    });

    test('openMedia：明文媒体原样返回（不触端口）', () async {
      final plain = plainOf('明文图片');
      expect(await keys.openMedia('nb-any', plain), plain);
    });
  });

  group('M-4：会话世代/遗忘世代作废在途注入', () {
    test('forget 后在途 ensure 完成 → 不复活密钥', () async {
      await storage.encryptAndSave(nb('nb-m4'), pw);
      // 发起 ensure（Argon2id 慢操作），在其完成前 forget（页面退出）。
      final inflight = keys.ensure('nb-m4');
      keys.forget('nb-m4'); // 递增遗忘世代
      await expectLater(inflight, throwsA(isA<VaultFileLockException>()));
      expect(media.hasKeyFor('nb-m4'), isFalse, reason: '遗忘后不得复活密钥');
    });

    test('SessionSecrets.clearAll（回锁）→ 在途 ensure 作废 + 清全部驻留', () async {
      await storage.encryptAndSave(nb('nb-m4b'), pw);
      await keys.ensure('nb-m4b');
      expect(media.hasKeyFor('nb-m4b'), isTrue);
      final inflight = keys.ensure('nb-m4b'); // 已驻留→立即完成，另起一路慢的
      media.clearNotebookKey('nb-m4b');
      final slow = keys.ensure('nb-m4b'); // 重新解包（慢）
      SessionSecrets.clearAll(); // 回锁：epoch 翻篇 + 清全部
      await inflight;
      await expectLater(slow, throwsA(isA<VaultFileLockException>()));
      expect(media.hasKeyFor('nb-m4b'), isFalse);
    });
  });

  group('M-5：删除笔记本联动遗忘密钥', () {
    test('delete → 驻留 K_note 清除', () async {
      await storage.encryptAndSave(nb('nb-m5'), pw);
      await keys.ensure('nb-m5');
      expect(media.hasKeyFor('nb-m5'), isTrue);
      await storage.delete('nb-m5');
      expect(media.hasKeyFor('nb-m5'), isFalse, reason: '已删笔记密钥不得驻留');
    });
  });
  group('M-4：懒补槽抛错路径（2026-11-17）', () {
    test('attachMediaSlot 抛错 → 错误上抛且传入密钥被零化；重试后媒体可解', () async {
      // 手工落无 media 槽的 v5 信封（懒补场景，照 H-3 先例）——
      // encryptAndSave 自动生成 media 槽，ensure 走 unwrap 成功路不触发懒补。
      final notebook = nb('nb-m4');
      final envelope = await enc.encryptWithPasswordV5(
        notebookId: 'nb-m4',
        plaintext: '{"pages":[]}',
        password: pw,
      );
      final map = jsonDecode(envelope) as Map<String, dynamic>;
      (map['slots'] as Map<String, dynamic>).remove('media');
      notebook.encryptedPayload = jsonEncode(map);
      notebook.encrypted = true;
      await storage.save(notebook);
      // 会话口令注入（ensure 需要；照生产解锁路径）。
      await storage.verifyNotebookPassword('nb-m4', pw);

      final port = _ThrowingAttachPort(_LatePort(() => storage));
      final failKeys = NotebookMediaKeys(media: media, envelopes: port);

      // 首次 ensure：无槽 → 生成 key → attach 抛错 → key 零化后上抛。
      await expectLater(
        failKeys.ensure('nb-m4'),
        throwsA(isA<VaultFileLockException>()),
      );
      expect(port.capturedKey, isNotNull);
      expect(
        port.capturedKey!.every((b) => b == 0),
        isTrue,
        reason: '补槽抛错后编排器必须零化已生成的独占副本（M-4）',
      );

      // 重试：attach 恢复正常 → 补槽成功 → 媒体密封/开启全链路正确。
      port.throwOnAttach = false;
      final sealed = await failKeys.sealMedia('nb-m4', plainOf('M4 回归'));
      expect(sealed, isNotNull);
      final opened = await failKeys.openMedia('nb-m4', sealed!);
      expect(opened, plainOf('M4 回归'));
    });
  });

}

/// 延迟绑定信封端口（测试装配用）：与生产 app.dart late final 同语义。
// M-4（第二轮审计 2026-11-17）：懒补槽抛错路径密钥零化。
// 零化不可从外部直接观测（Dart 无内存探针）——本组钉「抛错后全链路仍正确」：
// 补槽失败 → 错误上抛 → 重试成功 → 媒体可解。若零化误伤了服务内副本或
// 重试路径，sealMedia/openMedia 会失败。
class _ThrowingAttachPort implements NotebookMediaEnvelopePort {
  _ThrowingAttachPort(this._inner);
  final NotebookMediaEnvelopePort _inner;
  bool throwOnAttach = true;
  List<int>? capturedKey;

  @override
  Future<bool> isEncryptedNotebook(String notebookId) =>
      _inner.isEncryptedNotebook(notebookId);

  @override
  Future<String?> sessionPassword(String notebookId) =>
      _inner.sessionPassword(notebookId);

  @override
  Future<List<int>?> unwrapMediaKey(String notebookId, String password) =>
      _inner.unwrapMediaKey(notebookId, password);

  @override
  Future<void> attachMediaSlot(
    String notebookId,
    String password,
    List<int> mediaKey,
  ) async {
    capturedKey = mediaKey; // 持引用（fillRange 原地零化可见；复制会看不到）
    if (throwOnAttach) throw const VaultFileLockException();
    return _inner.attachMediaSlot(notebookId, password, mediaKey);
  }
}

/// H-3 交错场景端口：attach 真正落盘**之前**，模拟另一路 ensure 已把
/// 自己那把钥补进磁盘槽——于是本次 attach 命中「已有槽」幂等 no-op。
class _RacingPort implements NotebookMediaEnvelopePort {
  _RacingPort(this._inner);
  final NotebookStorage _inner;

  @override
  Future<bool> isEncryptedNotebook(String notebookId) =>
      _inner.isEncryptedNotebook(notebookId);

  @override
  Future<String?> sessionPassword(String notebookId) =>
      _inner.sessionPassword(notebookId);

  @override
  Future<List<int>?> unwrapMediaKey(String notebookId, String password) =>
      _inner.unwrapMediaKey(notebookId, password);

  @override
  Future<void> attachMediaSlot(
    String notebookId,
    String password,
    List<int> mediaKey,
  ) async {
    // 抢先把另一把钥落盘（模拟前一条在途任务先完成补槽）。
    final rival = MediaCryptoService.generateNotebookKey();
    await _inner.attachMediaSlot(notebookId, password, rival);
    // 本次 attach 落到已有槽上：幂等 no-op，不覆盖、不回传真实钥。
    return _inner.attachMediaSlot(notebookId, password, mediaKey);
  }
}

class _LatePort implements NotebookMediaEnvelopePort {
  _LatePort(this._resolve);
  final NotebookStorage Function() _resolve;

  @override
  Future<bool> isEncryptedNotebook(String notebookId) =>
      _resolve().isEncryptedNotebook(notebookId);

  @override
  Future<String?> sessionPassword(String notebookId) =>
      _resolve().sessionPassword(notebookId);

  @override
  Future<List<int>?> unwrapMediaKey(String notebookId, String password) =>
      _resolve().unwrapMediaKey(notebookId, password);

  @override
  Future<void> attachMediaSlot(
    String notebookId,
    String password,
    List<int> mediaKey,
  ) => _resolve().attachMediaSlot(notebookId, password, mediaKey);
}