// SYN-D1（第四轮全仓审计 2026-10-15）：块文档「受密状态」必须是**三态**。
//
// 旧形状是 `String? _readEnvelopeJson`：「不存在 / 主密钥信封 / 明文 / 损坏」与
// 「这一刻读不出来（errno 32 句柄被占用、权限抖动、瞬时 IO 错误）」被压成**同一个 null**，
// 而 `saveDocument` 正是拿这个 null 走「未受密 ⇒ 可以落盘」那一支。后果不是报错，是
// **一次读抖动就把 v5 文件密码信封整份盖成明文（或主密钥信封）**——原密文连同那份 DEK
// 一起没了，用户之后再怎么输密码也开不了这篇笔记。
//
// 同族的「读不出来被答成没有」在本仓是**头号复发形态**（DN-107 / vaultConfigured 已修过
// 三次），所以这一格的钉法与同族一致：确定性地造出「文件在、内容读不出」，不靠调度碰运气。
//
// 突变自证（改完只让对应的用例变红，实跑记录写在 commit message 里）：
//  S1 `save` 里去掉 `unreadable ⇒ 拒写` 那一支     ⇒ （读不出来 ⇒ 信封字节原样在盘上）
//  S2 `isBlockDocPasswordProtected` 退回两态        ⇒ （读不出来 ⇒ 答「受密」）
// 反向锁（第三条用例）：三态**不许**退化成「一律拒写」——文件不存在、明文、主密钥信封
// 三种读得出的一概照常落盘，否则没建库的用户直接存不了东西（app.dart:71-77 那条 P0 的教训）。
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/documents/note_block.dart';
import 'package:drawing_notes_app/core/documents/note_block_doc.dart';
import 'package:drawing_notes_app/core/documents/note_block_doc_store.dart';
import 'package:drawing_notes_app/core/security/audit_logger.dart';
import 'package:drawing_notes_app/core/security/kdf_params.dart';
import 'package:drawing_notes_app/core/storage/encryption_service.dart';
import 'package:drawing_notes_app/core/storage/vault_file_codec.dart';

import '../../helpers/temp_dir_cleanup.dart';

void main() {
  // 与 n2 同口径：测试槽位用轻量 KDF，格式与生产一致，只为把整套流程跑起来。
  KdfParams.newSlotDefault = KdfParams.testLight;

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('synd1_tristate_');
    AuditLogger.clear();
  });

  tearDown(() async {
    await deleteTempDirWithRetry(tempDir);
  });

  String docPath(String id) =>
      '${tempDir.path}${Platform.pathSeparator}blockdocs'
      '${Platform.pathSeparator}$id.json';

  NoteBlockDocStore storageWith({Future<Uint8List?> Function()? keyProvider}) =>
      NoteBlockDocStore(
        directoryProvider: () async => tempDir,
        keyProvider: keyProvider,
      );

  NoteBlockDoc doc(String id, {String title = '机密笔记'}) => NoteBlockDoc(
    id: id,
    title: title,
    body: [NoteBlock.textBlock('${id}_b1', text: '只有这一份副本')],
    createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
  );

  /// 造出「文件在、这一刻读不出内容」那一格。抛的是真形态异常（句柄被别的进程占用），
  /// 不是自定义类型——判据要按「任何读失败」成立，而不是按某一种异常成立。
  void makeReadFail(NoteBlockDocStore store) {
    store.readBarrierForTest = (_) async {
      throw FileSystemException(
        '另一个进程正在使用这个文件',
        '',
        OSError('另一个程序正占用此文件', 32),
      );
    };
  }

  group('SYN-D1 受密状态三态', () {
    test('读不出来 ⇒ saveDocument 拒写，盘上那份 v5 信封一字未动', () async {
      const id = 'bd_tri_pwd';
      final store = storageWith();
      await store.encryptAndSave(doc(id), 'pass-1111');

      final before = File(docPath(id)).readAsBytesSync();
      expect(
        EncryptionService.isDualProtectorEnvelope(utf8.decode(before)),
        isTrue,
        reason: '前置条件：盘上这份确实是 v5 文件密码信封',
      );

      // 冷实例：会话里没有 DEK，且读那一格被钉成「读不出来」。
      final cold = storageWith();
      makeReadFail(cold);
      await expectLater(
        cold.saveDocument(doc(id, title: '抖动期间的一次自动保存')),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('读不出来'),
          ),
        ),
        reason: '必须按「读不出来」拒写；按「未受密」落盘就是把信封盖掉',
      );

      final after = File(docPath(id)).readAsBytesSync();
      expect(
        after,
        before,
        reason: '突变 S1：去掉 unreadable ⇒ 拒写 那一支，这里会被明文整份盖掉',
      );
      expect(
        AuditLogger.snapshot().any((l) => l.contains('blockdoc.save.readUnknown')),
        isTrue,
        reason: '拒写要可见——否则用户只看到「保存失败」，查不到为什么',
      );
    });

    test('读不出来 ⇒ isBlockDocPasswordProtected 答「受密」（保守方向只有一个）', () async {
      const id = 'bd_tri_bool';
      final store = storageWith();
      await store.encryptAndSave(doc(id), 'pass-1111');

      final cold = storageWith();
      makeReadFail(cold);
      expect(
        await cold.isBlockDocPasswordProtected(id),
        isTrue,
        reason: '突变 S2：退回两态会答 false，而调用点的形状一律是「未受密 ⇒ 直接放行」'
            '（删/移动/导出都不再问密码），那就是拿一次读抖动去赌这份文件的生死',
      );

      // 同一实例把屏障撤掉 ⇒ 读得出时仍按真实状态答，不能变成恒 true。
      cold.readBarrierForTest = null;
      expect(await cold.isBlockDocPasswordProtected(id), isTrue);
    });

    test('反向锁：读得出的三种形状一律照常落盘（三态不等于一律拒写）', () async {
      // ① 文件不存在 —— 新建笔记的必经之路。
      final plain = storageWith();
      await plain.saveDocument(doc('bd_tri_new'));
      expect(File(docPath('bd_tri_new')).existsSync(), isTrue);

      // ② 盘上是明文（没建库的用户）—— 必须能继续存下去。
      await plain.saveDocument(doc('bd_tri_new', title: '第二次保存'));
      final plainBytes = File(docPath('bd_tri_new')).readAsBytesSync();
      expect(
        EncryptionService.isDualProtectorEnvelope(utf8.decode(plainBytes)),
        isFalse,
        reason: '没建库就是明文，这条产品设计不能被三态改动碰坏',
      );

      // ③ 盘上是主密钥信封（非文件密码）—— 读得出来，走正常加密腿。
      final key = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));
      final vaulted = storageWith(keyProvider: () async => key);
      await vaulted.saveDocument(doc('bd_tri_vault'));
      final sealedBytes = File(docPath('bd_tri_vault')).readAsBytesSync();
      expect(
        VaultFileCodec.isEncrypted(sealedBytes),
        isTrue,
        reason: '有主密钥时正文应以信封形式落盘',
      );
      // 再存一次：这一次读到的就是刚写进去的主密钥信封 ⇒ 仍属「读得出来、未受文件密码」。
      await vaulted.saveDocument(doc('bd_tri_vault', title: '信封之上再存一次'));
      final loaded = await vaulted.loadDocument('bd_tri_vault');
      expect(loaded?.title, '信封之上再存一次');
    });
  });
}
