import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/storage/vfs/encrypted_vault.dart';

/// VFS 加密对象仓库单测（专家目标架构 VFS——2026-08-16）：
/// 对象读写往返/版本递增/篡改检测（错误密钥 AAD 不符）/原子提交/缺失。
void main() {
  late Directory tempDir;
  final key = List<int>.generate(32, (i) => i);

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('vault_test');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {
      /* 忽略清理失败 */
    }
  });

  test('VFS：对象写入读取往返（明文一致）', () async {
    final vault = EncryptedVault(directory: tempDir, key: key);
    final plain = Uint8List.fromList('机密媒体字节'.codeUnits);
    await vault.writeObject(id: 'media-1', type: 'media', plain: plain);
    final read = await vault.readObject('media-1');
    expect(read, plain);
    // 清单记录存在。
    final entries = await vault.listObjects();
    expect(entries, hasLength(1));
    expect(entries.first.id, 'media-1');
    expect(entries.first.type, 'media');
  });

  test('VFS：版本递增——重复写同 id 版本 1→2', () async {
    final vault = EncryptedVault(directory: tempDir, key: key);
    await vault.writeObject(
      id: 'note-a',
      type: 'index',
      plain: Uint8List.fromList('v1'.codeUnits),
    );
    await vault.writeObject(
      id: 'note-a',
      type: 'index',
      plain: Uint8List.fromList('v2'.codeUnits),
    );
    final entries = await vault.listObjects();
    expect(entries.first.version, 2);
    // 最新版本读取 v2；旧版本（1）仍可回溯。
    expect(String.fromCharCodes(await vault.readObject('note-a')), 'v2');
    expect(
      String.fromCharCodes(await vault.readObject('note-a', version: 1)),
      'v1',
    );
  });

  test('VFS：篡改检测——错误密钥解密认证失败（AAD 不符）', () async {
    final vault = EncryptedVault(directory: tempDir, key: key);
    await vault.writeObject(
      id: 'secret',
      type: 'note',
      plain: Uint8List.fromList('机密'.codeUnits),
    );
    // 错误密钥必 fail-closed：清单 HMAC 门（StateError）与
    // AAD/解密认证（SecretBoxAuthenticationError）双保险——任一拦截
    // 即安全。HMAC 门的确定性证明见下方的回滚测试（同钥改 manifest
    // 必撞门）；此处不断言具体哪一道先开（两道都关着门）。
    final wrongKey = List<int>.generate(32, (i) => i + 1);
    final wrongVault = EncryptedVault(directory: tempDir, key: wrongKey);
    await expectLater(
      wrongVault.readObject('secret'),
      throwsA(anyOf(isA<StateError>(), isA<SecretBoxAuthenticationError>())),
    );
    await File('${tempDir.path}/manifest.hmac').delete();
    await expectLater(
      wrongVault.readObject('secret'),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });

  test('VFS：对象不存在抛 StateError', () async {
    final vault = EncryptedVault(directory: tempDir, key: key);
    expect(() => vault.readObject('missing'), throwsStateError);
  });

  test('VFS：原子提交——manifest 与对象文件均落盘（结构完整）', () async {
    final vault = EncryptedVault(directory: tempDir, key: key);
    await vault.writeObject(
      id: 'obj-1',
      type: 'media',
      plain: Uint8List.fromList('data'.codeUnits),
    );
    expect(File('${tempDir.path}/manifest.json').existsSync(), isTrue);
    expect(File('${tempDir.path}/objects/obj-1.1').existsSync(), isTrue);
    // 无 .tmp 残留（原子写入孤儿清理）。
    final leftovers = tempDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.contains('.tmp'));
    expect(leftovers, isEmpty);
  });

  test('P1：id 路径穿越拒绝（../ 逃逸 objects/）', () async {
    final vault = EncryptedVault(directory: tempDir, key: key);
    for (final evil in [
      '../../vault.key.json',
      '..',
      'a/../../b',
      'a//b',
      '/abs/path',
      'a\\b',
      '',
    ]) {
      await expectLater(
        vault.writeObject(
          id: evil,
          type: 'media',
          plain: Uint8List.fromList('x'.codeUnits),
        ),
        throwsStateError,
        reason: evil,
      );
    }
    // 子路径用例保留：media/note-1 正常写入。
    await vault.writeObject(
      id: 'media/note-1',
      type: 'media',
      plain: Uint8List.fromList('ok'.codeUnits),
    );
    expect(String.fromCharCodes(await vault.readObject('media/note-1')), 'ok');
  });

  test('P1：清单 version 回滚被 HMAC 拦截', () async {
    final vault = EncryptedVault(directory: tempDir, key: key);
    await vault.writeObject(
      id: 'doc',
      type: 'note',
      plain: Uint8List.fromList('v1'.codeUnits),
    );
    await vault.writeObject(
      id: 'doc',
      type: 'note',
      plain: Uint8List.fromList('v2'.codeUnits),
    );
    // 攻击者把 manifest 改回 version 1（旧对象文件仍在）。
    final manifestFile = File('${tempDir.path}/manifest.json');
    final tampered = (await manifestFile.readAsString()).replaceAll(
      '"version":2',
      '"version":1',
    );
    expect(tampered, isNot(contains('"version":2')));
    await manifestFile.writeAsString(tampered);
    // 侧车未同步 → 读取 fail-closed。
    expect(() => vault.readObject('doc'), throwsStateError);
    expect(() => vault.listObjects(), throwsStateError);
  });

  test('P1：截断对象文件抛 StateError（非 RangeError 崩溃）', () async {
    final vault = EncryptedVault(directory: tempDir, key: key);
    await vault.writeObject(
      id: 'tiny',
      type: 'media',
      plain: Uint8List.fromList('data'.codeUnits),
    );
    final obj = File('${tempDir.path}/objects/tiny.1');
    await obj.writeAsBytes(Uint8List.fromList([1, 2, 3]));
    expect(() => vault.readObject('tiny'), throwsStateError);
  });

  test('P1：非 32 字节密钥 fail-closed（debug 断言/release 运行时检查）', () async {
    // debug/test 下构造期 assert 先开火（AssertionError）；release 下
    // assert 被剥离，改由 _requireKey 抛 StateError——两种模式都关门。
    await expectLater(
      () => EncryptedVault(directory: tempDir, key: List<int>.filled(16, 1)),
      throwsA(anyOf(isA<AssertionError>(), isA<StateError>())),
    );
  });
}
