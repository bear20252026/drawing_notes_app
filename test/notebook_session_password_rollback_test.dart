/// P1 回归锁（会话口令缓存的失败回滚，2026-10-04）：分页画布（笔记本）
/// 设密/改密/USB 重置三类入口，`_cacheNotebookPassword` 在密封/写盘之前调用——
/// 若紧随的落盘抛错（文件被删 / 保险库回锁），会话缓存会残留**新**口令，而磁盘
/// 信封仍是**旧**口令；下一次 `load + decryptNotebook` 抛 FormatException，
/// 调用方 fail-closed（不丢稿，但用户被多问一次口令）。
///
/// 对齐既有裁决先例 `StorageFilePasswordManager._setFilePasswordLocked` /
/// `_changeFilePasswordLocked`（lib/core/storage/storage_file_password_manager.dart
/// :139-153、:196-233）：先缓存会话口令，密封失败即回滚——失败前无口令 → forget，
/// 失败前有旧口令 → 恢复旧值。本文件锁同一纪律在笔记本域落地：
/// - 改密落盘失败：会话回滚到旧口令（恢复旧值分支），不残留新口令；
/// - 会话本无口令时改密/重置落盘失败：回滚即 forget（不残留新口令）；
/// - 断言抛出的仍是原异常（回滚 catch 只 rethrow，绝吞成其它类型）。
///
/// 落盘失败用「保险库回锁」复现：keyProvider 在读载荷那一次返回主密钥、
/// 在写回那一次返回 null → `_patchEncryptedPayloadInsideExclusive` 对 DNV
/// 字节解码失败抛 FormatException（正是失败窗口，且发生在缓存新口令之后）。
///
/// 批B 起新槽位默认 Argon2id——注入轻量参数（[KdfParams.testLight]），
/// 格式与生产一致、无真 KDF 耗时（口径同 `notebook_password_queue_test.dart`）。
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';


import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/security/kdf_params.dart';
import 'package:drawing_notes_app/core/security/vault_key_service.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/notebook_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/temp_dir_cleanup.dart';

void main() {
  KdfParams.newSlotDefault = KdfParams.testLight;

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('nb_pw_rollback_');
  });

  tearDown(() async {
    try {
      await deleteTempDirWithRetry(tempDir);
    } on FileSystemException {
      // Windows 句柄延迟释放——尽力清理（同队列套件口径）。
    }
  });

  Notebook nbWithText(String id, String text) =>
      Notebook(id: id, title: '机密分页画布')
        ..pages.add(
          NotebookPage(
            id: 'pg_$id',
            title: '页一',
            document: DrawingDocument(
              id: 'd_$id',
              title: '页',
              width: 100,
              height: 100,
            ),
          )..textItems.add(PageTextItem(id: 't_$id', x: 1, y: 1, text: text)),
        );

  group('分页画布会话口令写盘失败回滚', () {
    test('改密落盘失败：会话回滚到旧口令、不残留新口令、原异常不被吞', () async {
      const id = 'rb_change_restore';
      final key = VaultKeyService.randomBytes(32);
      var calls = 0;
      var flipAfter = -1; // -1 = 恒解锁；否则第 flipAfter 次之后模拟保险库回锁
      final storage = NotebookStorage(
        directoryProvider: () async => tempDir,
        keyProvider: () async {
          calls++;
          return (flipAfter >= 0 && calls > flipAfter) ? null : key;
        },
      );

      await storage.encryptAndSave(nbWithText(id, '旧正文'), 'old-pass-1');
      // 设密成功即入会话（失败前的旧口令）。
      expect(storage.notebookPasswordFor(id), 'old-pass-1');

      calls = 0;
      flipAfter = 1; // 读载荷(第 1 次)取到钥、写回(第 2 次)掉锁 → patch 抛错
      await expectLater(
        storage.changeNotebookPassword(id, 'old-pass-1', 'new-pass-2'),
        throwsFormatException, // 原异常（回锁→载荷解码）不被回滚 catch 吞掉
      );

      // 失败前有旧口令 → 恢复旧值：会话里绝不再残留新口令。
      expect(storage.notebookPasswordFor(id), 'old-pass-1');
      expect(storage.notebookPasswordFor(id), isNot('new-pass-2'));

      // 磁盘信封未变（patch 在读阶段即抛）：旧口令仍可校验，新口令无效。
      flipAfter = -1;
      expect(await storage.verifyNotebookPassword(id, 'old-pass-1'), isTrue);
      expect(await storage.verifyNotebookPassword(id, 'new-pass-2'), isFalse);
    });

    test('会话本无口令时改密落盘失败：回滚即 forget（不残留新口令）', () async {
      const id = 'rb_change_forget';
      final key = VaultKeyService.randomBytes(32);
      var calls = 0;
      var flipAfter = -1;
      final storage = NotebookStorage(
        directoryProvider: () async => tempDir,
        keyProvider: () async {
          calls++;
          return (flipAfter >= 0 && calls > flipAfter) ? null : key;
        },
      );

      await storage.encryptAndSave(nbWithText(id, '旧正文'), 'old-pass-1');
      // 模拟冷启动/切后台清会话后，本会话尚未解出旧口令（改密仅凭显式入参）。
      storage.clearAllSessionSecrets();
      expect(storage.notebookPasswordFor(id), isNull);

      calls = 0;
      flipAfter = 1;
      await expectLater(
        storage.changeNotebookPassword(id, 'old-pass-1', 'new-pass-2'),
        throwsFormatException,
      );

      // 失败前无口令 → forget：会话仍为空，绝不残留新口令。
      expect(storage.notebookPasswordFor(id), isNull);

      flipAfter = -1;
      expect(await storage.verifyNotebookPassword(id, 'old-pass-1'), isTrue);
      expect(await storage.verifyNotebookPassword(id, 'new-pass-2'), isFalse);
    });

    test('USB 重置落盘失败：回滚 forget、旧密码仍有效、新密码未生效', () async {
      const id = 'rb_reset_forget';
      final key = VaultKeyService.randomBytes(32);
      var calls = 0;
      var flipAfter = -1;
      final storage = NotebookStorage(
        directoryProvider: () async => tempDir,
        keyProvider: () async {
          calls++;
          return (flipAfter >= 0 && calls > flipAfter) ? null : key;
        },
      );

      final usbKey = List<int>.generate(32, (i) => i + 7);
      await storage.encryptAndSave(
        nbWithText(id, '旧正文'),
        'old-pass-1',
        usbKey: usbKey,
      );
      // 失败前无口令（forget 分支）。
      storage.clearAllSessionSecrets();
      expect(storage.notebookPasswordFor(id), isNull);

      calls = 0;
      flipAfter = 1; // 重置读载荷取钥、写回掉锁 → patch 抛错（缓存新口令之后）
      await expectLater(
        storage.resetNotebookPasswordWithUsb(id, usbKey, 'reset-pass-9'),
        throwsFormatException, // 原异常不被吞
      );

      expect(storage.notebookPasswordFor(id), isNull);

      flipAfter = -1;
      expect(await storage.verifyNotebookPassword(id, 'old-pass-1'), isTrue);
      expect(await storage.verifyNotebookPassword(id, 'reset-pass-9'), isFalse);
    });
  });
}
