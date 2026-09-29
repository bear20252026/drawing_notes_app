import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

// C-11（审计 2026-09-27）：原 sync_service_test.dart——文件头曾同时覆盖
// 已删除的死三件套 SyncFile/SyncService（features/drawing/infrastructure，
// 零实现零消费）与存活的 SyncPathCipher；死部分随模块删除，本文件
// 更名对齐实际覆盖面（路径加密）。
import 'package:drawing_notes_app/features/drawing/infrastructure/sync_path_cipher.dart';

void main() {
  const cipher = SyncPathCipher();

  Future<List<int>> masterKey() async {
    final key = await AesGcm.with256bits().newSecretKey();
    return key.extractBytes();
  }

  test('路径加密：往返还原（确定性 nonce + 候选明文解密）', () async {
    final key = await masterKey();
    final encrypted = await cipher.encryptPath('会议纪要.json', key);
    expect(encrypted.endsWith(SyncPathCipher.encryptedExtension), isTrue);
    // 不泄露明文：密文中不含原标题字样。
    expect(encrypted.contains('会议纪要'), isFalse);

    final restored = await cipher.decryptPathWithCandidates(
      encrypted,
      key,
      const ['其他文件.json', '会议纪要.json', 'todo.txt'],
    );
    expect(restored, '会议纪要.json');
  });

  test('路径加密：确定性——同主密钥同文件名产生相同密文', () async {
    final key = await masterKey();
    final a = await cipher.encryptPath('笔记.sbn', key);
    final b = await cipher.encryptPath('笔记.sbn', key);
    expect(a, b);
  });

  test('路径加密：错误密钥/篡改密文解密失败返回 null（不抛异常）', () async {
    final key = await masterKey();
    final other = await masterKey();
    final encrypted = await cipher.encryptPath('机密.json', key);
    expect(
      await cipher.decryptPathWithCandidates(encrypted, other, const [
        '机密.json',
      ]),
      isNull,
    );
    // 篡改一个字符后同样失败。
    final tampered = encrypted.replaceFirst(
      encrypted[3],
      encrypted[3] == 'a' ? 'b' : 'a',
    );
    expect(
      await cipher.decryptPathWithCandidates(tampered, key, const ['机密.json']),
      isNull,
    );
  });
}

