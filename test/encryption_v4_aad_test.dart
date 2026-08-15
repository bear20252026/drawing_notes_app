import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/storage/encryption_service.dart';

/// H-06 修复（专家审计 2026-08-15）：AAD v4 上下文绑定——
/// NIST SP 800-38D 附加认证数据绑定笔记 ID/用途/版本，
/// 使跨笔记/跨用途密文交换在认证时失败。
void main() {
  const service = EncryptionService();
  final key = List<int>.generate(32, (i) => i);

  test('v4 AAD：往返解密（正确 notebookId）', () async {
    final enc = await service.encryptNotebookPayload(
      notebookId: 'nb-1',
      plaintext: '机密内容',
      key: key,
    );
    final dec = await service.decryptNotebookPayload(
      notebookId: 'nb-1',
      encryptedJson: enc,
      key: key,
    );
    expect(dec, '机密内容');
  });

  test('v4 AAD：交换 notebookId 认证失败（上下文绑定）', () async {
    final enc = await service.encryptNotebookPayload(
      notebookId: 'nb-1',
      plaintext: '机密内容',
      key: key,
    );
    expect(
      () => service.decryptNotebookPayload(
        notebookId: 'nb-2',
        encryptedJson: enc,
        key: key,
      ),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });

  test('v4 AAD：错误密钥认证失败', () async {
    final enc = await service.encryptNotebookPayload(
      notebookId: 'nb-1',
      plaintext: '机密内容',
      key: key,
    );
    final wrongKey = List<int>.generate(32, (i) => i + 1);
    expect(
      () => service.decryptNotebookPayload(
        notebookId: 'nb-1',
        encryptedJson: enc,
        key: wrongKey,
      ),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });
}
