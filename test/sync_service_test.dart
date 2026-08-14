import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/engine/sync_path_cipher.dart';
import 'package:drawing_notes_app/engine/sync_service.dart';

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
      await cipher.decryptPathWithCandidates(
        encrypted,
        other,
        const ['机密.json'],
      ),
      isNull,
    );
    // 篡改一个字符后同样失败。
    final tampered = encrypted.replaceFirst(
      encrypted[3],
      encrypted[3] == 'a' ? 'b' : 'a',
    );
    expect(
      await cipher.decryptPathWithCandidates(
        tampered,
        key,
        const ['机密.json'],
      ),
      isNull,
    );
  });

  test('SyncFile 模型：等价性与 copyWith', () {
    const a = SyncFile(localPath: 'a.json', remotePath: 'x.sbe');
    const b = SyncFile(localPath: 'a.json', remotePath: 'x.sbe');
    const c = SyncFile(localPath: 'b.json', remotePath: 'x.sbe');
    expect(a, b);
    expect(a == c, isFalse);
    expect(a.copyWith(localPath: 'b.json').localPath, 'b.json');
  });

  test('同步抽象层：三件套接口可被测试桩实现（不绑定协议）', () async {
    final stub = _StubSyncService();
    final localChanges = await stub.findLocalChanges();
    expect(localChanges, hasLength(1));
    final remoteChanges = await stub.findRemoteChanges();
    expect(remoteChanges, hasLength(1));
    final best = await stub.getBestFile(
      localChanges.first,
      preferLocal: true,
    );
    expect(best.localPath, 'local.json');
  });
}

class _StubSyncService implements SyncService {
  @override
  Future<List<SyncFile>> findLocalChanges() async =>
      const [SyncFile(localPath: 'local.json', remotePath: 'l.sbe')];

  @override
  Future<List<SyncFile>> findRemoteChanges() async =>
      const [SyncFile(localPath: 'remote.json', remotePath: 'r.sbe')];

  @override
  Future<SyncFile> getBestFile(SyncFile file, {required bool preferLocal}) async =>
      file.copyWith(localPath: preferLocal ? 'local.json' : 'remote.json');

  @override
  Future<void> upload(SyncFile file, Uint8List bytes) async {}

  @override
  Future<Uint8List?> download(SyncFile file) async => null;
}
