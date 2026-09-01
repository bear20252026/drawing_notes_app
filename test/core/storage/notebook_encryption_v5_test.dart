/// N4 批 3：分页画布密码 v5 双保护器载荷（EncryptionService + NotebookStorage）
/// 回归测试。
///
/// 覆盖：v5 设密/解锁往返、错密码拒绝、DEK 续写不失效重置盘槽位
/// （LUKS 槽位语义——续写仅重生成 payload，槽位原样保留）、改密（payload
/// 密文不动 + USB 槽保留）、重置盘重置（错盘 fail-closed）、事后绑定、
/// v4 旧载荷兼容解密与改密自动升级、会话密码缓存语义。
///
/// 注：走生产默认 600k PBKDF2，全量套件高并发下会超出默认 30s 单测超时
/// ——放宽到 3 分钟。
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/storage/encryption_service.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/notebook_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('nb_v5_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      try {
        await tempDir.delete(recursive: true);
      } on FileSystemException {
        // Windows 句柄延迟释放——尽力清理。
      }
    }
  });

  NotebookStorage storageWith() => NotebookStorage(
        directoryProvider: () async => tempDir,
      );

  Notebook nbWithPage(String id) => Notebook(id: id, title: '机密分页画布')
    ..pages.add(
      NotebookPage(
        id: 'pg1',
        title: '页一',
        document: DrawingDocument(
          id: 'd1',
          title: '页',
          width: 100,
          height: 100,
        ),
      )..textItems.add(PageTextItem(id: 't1', x: 1, y: 1, text: '绝密正文')),
    );

  group('EncryptionService v5 编解码层', () {
    const svc = EncryptionService();
    const id = 'nb_v5_e1';
    const pw = 'abc12345';

    test('v5 加密 → decryptWithPasswordAad 往返；错密码抛 FormatException', () async {
      final envelope = await svc.encryptWithPasswordV5(
        notebookId: id,
        plaintext: '{"pages":[]}',
        password: pw,
        usbKey: null,
      );
      expect(EncryptionService.isDualProtectorEnvelope(envelope), isTrue);
      expect(EncryptionService.hasUsbSlotV5(envelope), isFalse);
      final clear = await svc.decryptWithPasswordAad(
        notebookId: id,
        encryptedJson: envelope,
        password: pw,
      );
      expect(clear, '{"pages":[]}');
      expect(
        () => svc.decryptWithPasswordAad(
          notebookId: id,
          encryptedJson: envelope,
          password: 'wrong-pin',
        ),
        throwsFormatException,
      );
    });

    test('改密：payload 密文与 USB 槽原样保留；旧密码失效', () async {
      final usbKey = List<int>.generate(32, (i) => i + 1);
      var envelope = await svc.encryptWithPasswordV5(
        notebookId: id,
        plaintext: 'payload-plain',
        password: pw,
        usbKey: usbKey,
      );
      final oldPayloadC =
          (jsonDecode(envelope) as Map)['payload']['c'] as String;
      final oldUsbW =
          (jsonDecode(envelope) as Map)['slots']['usb']['w'] as String;

      envelope = await svc.changeNotebookPasswordV5(
        notebookId: id,
        encryptedJson: envelope,
        oldPassword: pw,
        newPassword: 'new-pin-99',
      );
      final map = jsonDecode(envelope) as Map<String, dynamic>;
      expect((map['payload'] as Map)['c'], oldPayloadC); // 载荷密文不动
      expect((map['slots']['usb'] as Map)['w'], oldUsbW); // USB 槽保留
      expect(EncryptionService.hasUsbSlotV5(envelope), isTrue);
      // 新密码可解；旧密码失效。
      expect(
        await svc.decryptWithPasswordAad(
          notebookId: id,
          encryptedJson: envelope,
          password: 'new-pin-99',
        ),
        'payload-plain',
      );
      expect(
        () => svc.decryptWithPasswordAad(
          notebookId: id,
          encryptedJson: envelope,
          password: pw,
        ),
        throwsFormatException,
      );
    });

    test('重置盘重置：错盘/未绑定 fail-closed；成功后 payload 不动', () async {
      final usbKey = List<int>.generate(32, (i) => i * 2 % 256);
      var envelope = await svc.encryptWithPasswordV5(
        notebookId: id,
        plaintext: 'secret-plain',
        password: pw,
        usbKey: usbKey,
      );
      final oldPayloadC =
          (jsonDecode(envelope) as Map)['payload']['c'] as String;

      // 错盘 → null。
      final wrongKey = List<int>.generate(32, (i) => 255 - i);
      expect(
        await svc.resetNotebookPasswordWithUsbV5(
          notebookId: id,
          encryptedJson: envelope,
          usbKey: wrongKey,
          newPassword: 'reset-pw-1',
        ),
        isNull,
      );
      // 未绑定（另一信封）→ null。
      final noUsb = await svc.encryptWithPasswordV5(
        notebookId: id,
        plaintext: 'x',
        password: pw,
      );
      expect(
        await svc.resetNotebookPasswordWithUsbV5(
          notebookId: id,
          encryptedJson: noUsb,
          usbKey: usbKey,
          newPassword: 'reset-pw-1',
        ),
        isNull,
      );
      // 正确盘 → 重置成功，新密码可解，payload 密文不动。
      envelope = (await svc.resetNotebookPasswordWithUsbV5(
        notebookId: id,
        encryptedJson: envelope,
        usbKey: usbKey,
        newPassword: 'reset-pw-1',
      ))!;
      expect(
        (jsonDecode(envelope) as Map)['payload']['c'],
        oldPayloadC,
      );
      expect(
        await svc.decryptWithPasswordAad(
          notebookId: id,
          encryptedJson: envelope,
          password: 'reset-pw-1',
        ),
        'secret-plain',
      );
    });

    test('事后绑定：追加 USB 槽；重复绑定拒绝', () async {
      var envelope = await svc.encryptWithPasswordV5(
        notebookId: id,
        plaintext: 'bind-me',
        password: pw,
      );
      expect(EncryptionService.hasUsbSlotV5(envelope), isFalse);
      envelope = await svc.bindNotebookUsbSlotV5(
        notebookId: id,
        encryptedJson: envelope,
        password: pw,
        usbKey: List<int>.generate(32, (i) => i),
      );
      expect(EncryptionService.hasUsbSlotV5(envelope), isTrue);
      expect(
        () => svc.bindNotebookUsbSlotV5(
          notebookId: id,
          encryptedJson: envelope,
          password: pw,
          usbKey: List<int>.generate(32, (i) => i),
        ),
        throwsFormatException,
      );
    });

    test('v4 旧载荷兼容解密（旧格式仅读）', () async {
      final legacy = await svc.encryptWithPasswordAad(
        notebookId: id,
        plaintext: 'legacy-v4-content',
        password: pw,
      );
      expect(EncryptionService.isDualProtectorEnvelope(legacy), isFalse);
      expect(
        await svc.decryptWithPasswordAad(
          notebookId: id,
          encryptedJson: legacy,
          password: pw,
        ),
        'legacy-v4-content',
      );
    });
  });

  group('NotebookStorage v5 存储层', () {
    const id = 'nb_v5_s1';

    test('encryptAndSave → 解锁往返；二次保存续写不失效重置盘槽位', () async {
      final storage = storageWith();
      final usbKey = List<int>.generate(32, (i) => i ^ 0x5A);
      final nb = nbWithPage(id);
      await storage.encryptAndSave(nb, 'pass-1111', usbKey: usbKey);
      expect(EncryptionService.hasUsbSlotV5(nb.encryptedPayload!), isTrue);

      // 锁定语义：重启后 pages 为空、payload 仍在。
      final locked = (await storage.load(id))!;
      expect(locked.encrypted, isTrue);
      expect(locked.pages, isEmpty);

      // 解锁。
      final unlocked = (await storage.load(id))!;
      expect(await storage.decryptNotebook(unlocked, 'pass-1111'), isTrue);
      expect(unlocked.pages.single.textItems.single.text, '绝密正文');

      // 续写（编辑保存）：DEK 复用 → USB 槽仍有效。
      unlocked.title = '续写后的标题';
      await storage.encryptAndSave(unlocked, 'pass-1111');
      final reloaded = (await storage.load(id))!;
      expect(EncryptionService.hasUsbSlotV5(reloaded.encryptedPayload!), isTrue);
      expect(
        await storage.resetNotebookPasswordWithUsb(
          id,
          usbKey,
          'reset-2222',
        ),
        isTrue,
      );
      // 旧密码失效（decryptNotebook 契约：密码错误抛 FormatException）、
      // 新密码解锁。
      final afterReset = (await storage.load(id))!;
      expect(
        () => storage.decryptNotebook(afterReset, 'pass-1111'),
        throwsFormatException,
      );
      final reopened = (await storage.load(id))!;
      expect(await storage.decryptNotebook(reopened, 'reset-2222'), isTrue);
      expect(reopened.pages.single.textItems.single.text, '绝密正文');
    });

    test('改密（v5）：仅重绕密码槽；会话密码缓存随改密更新', () async {
      final storage = storageWith();
      await storage.encryptAndSave(nbWithPage(id), 'old-pass-1');
      await storage.changeNotebookPassword(id, 'old-pass-1', 'new-pass-2');
      expect(await storage.verifyNotebookPassword(id, 'new-pass-2'), isTrue);
      expect(await storage.verifyNotebookPassword(id, 'old-pass-1'), isFalse);
      // 会话缓存：改密后新密码已入会话。
      expect(storage.notebookPasswordFor(id), 'new-pass-2');
    });

    test('改密（v4 旧载荷）：自动升级 v5 并可事后绑定重置盘', () async {
      final storage = storageWith();
      const svc = EncryptionService();
      // 手工落一个 v4 旧信封（模拟 v1.5.x 数据）。
      final nb = nbWithPage(id);
      final payloadJson = jsonEncode({
        'pages': nb.pages.map((p) => p.toJson()).toList(),
      });
      nb.encryptedPayload = await svc.encryptWithPasswordAad(
        notebookId: id,
        plaintext: payloadJson,
        password: 'legacy-pass',
      );
      nb.encrypted = true;
      // save 守卫拒绝「encrypted 且 pages 非空」——页面内容已在 payload 内。
      nb.pages.clear();
      await storage.save(nb);

      // 旧格式改密 → 升级 v5 + 顺带绑定重置盘。
      final usbKey = List<int>.generate(32, (i) => i + 7);
      await storage.changeNotebookPassword(
        id,
        'legacy-pass',
        'upgraded-pass',
        usbKey: usbKey,
      );
      final upgraded = (await storage.load(id))!;
      expect(
        EncryptionService.isDualProtectorEnvelope(upgraded.encryptedPayload!),
        isTrue,
      );
      expect(
        await storage.resetNotebookPasswordWithUsb(id, usbKey, 'reset-3333'),
        isTrue,
      );
      final afterReset = (await storage.load(id))!;
      expect(await storage.decryptNotebook(afterReset, 'reset-3333'), isTrue);
      expect(afterReset.pages.single.textItems.single.text, '绝密正文');
    });

    test('事后绑定：须验证文件密码；重复绑定拒绝', () async {
      final storage = storageWith();
      await storage.encryptAndSave(nbWithPage(id), 'bind-pass-1');
      expect(await storage.hasNotebookUsbSlot(id), isFalse);
      final usbKey = List<int>.generate(32, (i) => i + 3);
      // 错密码拒绝。
      expect(
        () => storage.bindNotebookUsbSlot(
          id,
          'wrong-pass',
          usbKey,
        ),
        throwsFormatException,
      );
      await storage.bindNotebookUsbSlot(id, 'bind-pass-1', usbKey);
      expect(await storage.hasNotebookUsbSlot(id), isTrue);
      expect(
        () => storage.bindNotebookUsbSlot(id, 'bind-pass-1', usbKey),
        throwsFormatException,
      );
    });

    test('会话密码缓存：解锁/删除生命周期', () async {
      final storage = storageWith();
      expect(storage.notebookPasswordFor(id), isNull);
      await storage.encryptAndSave(nbWithPage(id), 'cache-pass-1');
      expect(storage.notebookPasswordFor(id), 'cache-pass-1');
      await storage.delete(id);
      expect(storage.notebookPasswordFor(id), isNull);
    });
  });
}
