/// N2：笔记（NoteBlockDoc）文件密码 v5 信封——EncryptionService scope
/// 感知泛化（bd）层回归测试。
///
/// 覆盖：bd v5 设密/解锁往返、错密码拒绝、AAD scope 隔离（nb/bd 信封
/// 互不可解）、改密（payload 密文与 USB 槽原样保留）、重置盘重置
/// （错盘/未绑定 fail-closed）、事后绑定（重复绑定拒绝）、会话 DEK
/// 快速路径（decryptBlockDocPayloadWithDek 零 PBKDF2）、rewrap 续写
/// （payload 重生成、槽位组原样保留）。
///
/// 注：批B 起新槽位默认 Argon2id（64MiB t2 p2 ≈348ms）——测试注入
/// 轻量参数（KdfParams.testLight）避免拖慢套件，槽位格式与生产一致；
/// 高并发下仍放宽到 3 分钟。
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';

import 'package:drawing_notes_app/core/security/kdf_params.dart';
import 'package:drawing_notes_app/core/storage/encryption_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 批B：注入测试轻量 KDF（新槽位 Argon2id 8MiB≈几十 ms；生产默认
  // 64MiB t2 p2）。槽位 JSON 格式与生产完全一致，仅参数不同。
  KdfParams.newSlotDefault = KdfParams.testLight;
  group('EncryptionService blockdoc v5（scope=bd）', () {
    const svc = EncryptionService();
    const id = 'bd_v5_e1';
    const pw = 'abc12345';

    test('v5 加密 → decryptBlockDocPassword 往返；错密码抛 FormatException', () async {
      final envelope = await svc.encryptBlockDocPasswordV5(
        docId: id,
        plaintext: '{"id":"$id","title":"机密笔记"}',
        password: pw,
      );
      expect(EncryptionService.isDualProtectorEnvelope(envelope), isTrue);
      expect(EncryptionService.hasUsbSlotV5(envelope), isFalse);
      final clear = await svc.decryptBlockDocPassword(
        docId: id,
        encryptedJson: envelope,
        password: pw,
      );
      expect(clear, '{"id":"$id","title":"机密笔记"}');
      expect(
        () => svc.decryptBlockDocPassword(
          docId: id,
          encryptedJson: envelope,
          password: 'wrong-pin',
        ),
        throwsFormatException,
      );
    });

    test('AAD scope 隔离：bd 信封放 nb scope 必失败，反之亦然', () async {
      final bdEnvelope = await svc.encryptBlockDocPasswordV5(
        docId: id,
        plaintext: 'bd-secret',
        password: pw,
      );
      // 同 id 同密码，但 pw 槽 AAD 绑定 bd:——nb scope 解包必失败。
      expect(
        () => svc.decryptWithPasswordAad(
          notebookId: id,
          encryptedJson: bdEnvelope,
          password: pw,
        ),
        throwsFormatException,
      );
      final nbEnvelope = await svc.encryptWithPasswordV5(
        notebookId: id,
        plaintext: 'nb-secret',
        password: pw,
      );
      // nb 信封放 bd scope 同理。
      expect(
        () => svc.decryptBlockDocPassword(
          docId: id,
          encryptedJson: nbEnvelope,
          password: pw,
        ),
        throwsFormatException,
      );
    });

    test('会话 DEK 快速路径：decryptBlockDocPayloadWithDek 零 PBKDF2 往返', () async {
      final envelope = await svc.encryptBlockDocPasswordV5(
        docId: id,
        plaintext: 'fast-path-content',
        password: pw,
      );
      final dek = await svc.unwrapBlockDocPasswordSlotForRewrap(
        docId: id,
        encryptedJson: envelope,
        password: pw,
      );
      expect(dek, isNotNull);
      expect(
        await svc.decryptBlockDocPayloadWithDek(
          docId: id,
          encryptedJson: envelope,
          dek: dek!,
        ),
        'fast-path-content',
      );
      // 错 DEK（AEAD 认证失败）→ FormatException。
      expect(
        () => svc.decryptBlockDocPayloadWithDek(
          docId: id,
          encryptedJson: envelope,
          dek: List<int>.filled(32, 7),
        ),
        throwsFormatException,
      );
    });

    test('改密：payload 密文与 USB 槽原样保留；旧密码失效', () async {
      final usbKey = List<int>.generate(32, (i) => i + 1);
      var envelope = await svc.encryptBlockDocPasswordV5(
        docId: id,
        plaintext: 'bd-plain',
        password: pw,
        usbKey: usbKey,
      );
      final oldPayloadC =
          (jsonDecode(envelope) as Map)['payload']['c'] as String;
      final oldUsbW =
          (jsonDecode(envelope) as Map)['slots']['usb']['w'] as String;

      envelope = await svc.changeBlockDocPasswordV5(
        docId: id,
        encryptedJson: envelope,
        oldPassword: pw,
        newPassword: 'new-bd-pin',
      );
      final map = jsonDecode(envelope) as Map<String, dynamic>;
      expect((map['payload'] as Map)['c'], oldPayloadC); // 载荷密文不动
      expect((map['slots']['usb'] as Map)['w'], oldUsbW); // USB 槽保留
      expect(
        await svc.decryptBlockDocPassword(
          docId: id,
          encryptedJson: envelope,
          password: 'new-bd-pin',
        ),
        'bd-plain',
      );
      expect(
        () => svc.decryptBlockDocPassword(
          docId: id,
          encryptedJson: envelope,
          password: pw,
        ),
        throwsFormatException,
      );
    });

    test('重置盘重置：错盘/未绑定 fail-closed；成功后 payload 不动', () async {
      final usbKey = List<int>.generate(32, (i) => i * 2 % 256);
      var envelope = await svc.encryptBlockDocPasswordV5(
        docId: id,
        plaintext: 'bd-secret-plain',
        password: pw,
        usbKey: usbKey,
      );
      final oldPayloadC =
          (jsonDecode(envelope) as Map)['payload']['c'] as String;

      // 错盘 → null。
      final wrongKey = List<int>.generate(32, (i) => 255 - i);
      expect(
        await svc.resetBlockDocPasswordWithUsbV5(
          docId: id,
          encryptedJson: envelope,
          usbKey: wrongKey,
          newPassword: 'reset-pw-1',
        ),
        isNull,
      );
      // 未绑定（另一信封）→ null。
      final noUsb = await svc.encryptBlockDocPasswordV5(
        docId: id,
        plaintext: 'x',
        password: pw,
      );
      expect(
        await svc.resetBlockDocPasswordWithUsbV5(
          docId: id,
          encryptedJson: noUsb,
          usbKey: usbKey,
          newPassword: 'reset-pw-1',
        ),
        isNull,
      );
      // 正确盘 → 重置成功，新密码可解，payload 密文不动。
      envelope = (await svc.resetBlockDocPasswordWithUsbV5(
        docId: id,
        encryptedJson: envelope,
        usbKey: usbKey,
        newPassword: 'reset-pw-1',
      ))!;
      expect(
        (jsonDecode(envelope) as Map)['payload']['c'],
        oldPayloadC,
      );
      expect(
        await svc.decryptBlockDocPassword(
          docId: id,
          encryptedJson: envelope,
          password: 'reset-pw-1',
        ),
        'bd-secret-plain',
      );
    });

    test('事后绑定：追加 USB 槽；重复绑定拒绝', () async {
      var envelope = await svc.encryptBlockDocPasswordV5(
        docId: id,
        plaintext: 'bind-bd',
        password: pw,
      );
      expect(EncryptionService.hasUsbSlotV5(envelope), isFalse);
      envelope = await svc.bindBlockDocUsbSlotV5(
        docId: id,
        encryptedJson: envelope,
        password: pw,
        usbKey: List<int>.generate(32, (i) => i),
      );
      expect(EncryptionService.hasUsbSlotV5(envelope), isTrue);
      expect(
        () => svc.bindBlockDocUsbSlotV5(
          docId: id,
          encryptedJson: envelope,
          password: pw,
          usbKey: List<int>.generate(32, (i) => i),
        ),
        throwsFormatException,
      );
    });

    test('rewrap 续写：payload 重生成、密码与 USB 槽位仍有效', () async {
      final usbKey = List<int>.generate(32, (i) => i ^ 0xBD);
      final envelope = await svc.encryptBlockDocPasswordV5(
        docId: id,
        plaintext: 'old-body',
        password: pw,
        usbKey: usbKey,
      );
      final map = jsonDecode(envelope) as Map<String, dynamic>;
      final dek = await svc.unwrapBlockDocPasswordSlotForRewrap(
        docId: id,
        encryptedJson: envelope,
        password: pw,
      );
      final rewrapped = await svc.rewrapBlockDocPayloadV5(
        docId: id,
        map: map,
        dek: dek!,
        plaintext: 'new-body-edited',
      );
      // 槽位组原样保留（LUKS 语义）。
      final rMap = jsonDecode(rewrapped) as Map<String, dynamic>;
      expect((rMap['slots'] as Map).containsKey('usb'), isTrue);
      // 新密码可解出新明文；错 DEK 内容不再可还原（payload 已重生成）。
      expect(
        await svc.decryptBlockDocPassword(
          docId: id,
          encryptedJson: rewrapped,
          password: pw,
        ),
        'new-body-edited',
      );
      // 重置盘仍可用（usb 槽 AAD 未变、DEK 未变）。
      final reset = await svc.resetBlockDocPasswordWithUsbV5(
        docId: id,
        encryptedJson: rewrapped,
        usbKey: usbKey,
        newPassword: 'reset-bd-1',
      );
      expect(reset, isNotNull);
      expect(
        await svc.decryptBlockDocPassword(
          docId: id,
          encryptedJson: reset!,
          password: 'reset-bd-1',
        ),
        'new-body-edited',
      );
    });
  });
}
