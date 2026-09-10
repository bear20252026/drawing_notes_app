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

  test('VFS 生命周期：vacuum 保留新版本、删旧物理对象、旧版仍可回溯', () async {
    final vault = EncryptedVault(directory: tempDir, key: key);
    for (final v in ['v1', 'v2', 'v3', 'v4']) {
      await vault.writeObject(
        id: 'doc',
        type: 'note',
        plain: Uint8List.fromList(v.codeUnits),
      );
    }
    expect((await vault.listObjects()).first.version, 4);

    // retention=2：保留版本 3、4，删除版本 1、2。
    final result = await vault.vacuum(retention: 2);
    expect(result.removed, 2);
    expect(result.failed, 0);
    expect(result.retained, 2);

    // 保留版本仍可读（4 最新、3 旧版可回溯）。
    expect(String.fromCharCodes(await vault.readObject('doc')), 'v4');
    expect(
      String.fromCharCodes(await vault.readObject('doc', version: 3)),
      'v3',
    );

    // 物理文件：v1/v2 已删，v3/v4 仍在。
    expect(File('${tempDir.path}/objects/doc.1').existsSync(), isFalse);
    expect(File('${tempDir.path}/objects/doc.2').existsSync(), isFalse);
    expect(File('${tempDir.path}/objects/doc.3').existsSync(), isTrue);
    expect(File('${tempDir.path}/objects/doc.4').existsSync(), isTrue);
  });

  test('VFS 生命周期：被删旧版本读取明确失败（StateError，非静默/回退）', () async {
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
    await vault.writeObject(
      id: 'doc',
      type: 'note',
      plain: Uint8List.fromList('v3'.codeUnits),
    );
    await vault.vacuum(retention: 2); // 删除 v1。
    // 被删版本读取 → 明确失败（对象文件缺失）。
    await expectLater(vault.readObject('doc', version: 1), throwsStateError);
    // 最新版本不受影响。
    expect(String.fromCharCodes(await vault.readObject('doc')), 'v3');
  });

  test('VFS 生命周期：空/非法 retention 拒绝（<1 抛 ArgumentError）', () async {
    final vault = EncryptedVault(directory: tempDir, key: key);
    await vault.writeObject(
      id: 'doc',
      type: 'note',
      plain: Uint8List.fromList('v'.codeUnits),
    );
    for (final bad in [0, -1, -100]) {
      await expectLater(
        vault.vacuum(retention: bad),
        throwsA(isA<ArgumentError>()),
        reason: 'retention=$bad',
      );
    }
    // 拒绝时无副作用——对象文件仍在、最新版可读。
    expect(File('${tempDir.path}/objects/doc.1').existsSync(), isTrue);
    expect(String.fromCharCodes(await vault.readObject('doc')), 'v');
  });

  test('VFS 生命周期：清单更新失败失败安全——中止删除、旧版本保留', () async {
    // 注入"清单提交失败"（抛错），验证不删除任何对象文件。
    final vault = EncryptedVault(
      directory: tempDir,
      key: key,
      vacuumCommitBarrier: () async {
        throw StateError('模拟清单更新失败');
      },
    );
    for (final v in ['v1', 'v2', 'v3']) {
      await vault.writeObject(
        id: 'doc',
        type: 'note',
        plain: Uint8List.fromList(v.codeUnits),
      );
    }
    await expectLater(vault.vacuum(retention: 1), throwsStateError);
    // 失败安全：v1/v2（本应被删）仍存在且可回溯。
    expect(File('${tempDir.path}/objects/doc.1').existsSync(), isTrue);
    expect(File('${tempDir.path}/objects/doc.2').existsSync(), isTrue);
    expect(
      String.fromCharCodes(await vault.readObject('doc', version: 1)),
      'v1',
    );
    expect(
      String.fromCharCodes(await vault.readObject('doc', version: 2)),
      'v2',
    );
  });

  test('VFS 生命周期：孤儿扫描/清理不动合法历史版本，且不自动触发', () async {
    final vault = EncryptedVault(directory: tempDir, key: key);
    // 写对象两次 → doc.1（合法旧版）、doc.2（最新）。
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

    // 手工制造孤儿：无清单条目对象、超出版本的残留、临时文件。
    // 子路径孤儿（media/x.1）需先建子目录。
    await Directory('${tempDir.path}/objects').create(recursive: true);
    await Directory('${tempDir.path}/objects/media').create(recursive: true);
    for (final orphan in ['orphan-a.5', 'media/x.1', 'doc.9']) {
      await File('${tempDir.path}/objects/$orphan').writeAsString('junk');
    }
    await File(
      '${tempDir.path}/objects/doc.1.tmp.123.abc',
    ).writeAsString('junk');

    // 普通 writeObject 路径不触发清理（孤儿仍保留）。
    final orphansBefore = await vault.scanOrphans();
    expect(orphansBefore, containsAll(['orphan-a.5', 'media/x.1', 'doc.9']));
    expect(orphansBefore, contains('doc.1.tmp.123.abc'));
    // 合法历史版本 doc.1 不被判为孤儿。
    expect(orphansBefore, isNot(contains('doc.1')));

    // purgeOrphans 显式删除孤儿；doc.1 保留、可回溯。
    final removed = await vault.purgeOrphans();
    expect(removed, hasLength(orphansBefore.length));
    expect(await vault.scanOrphans(), isEmpty);
    expect(File('${tempDir.path}/objects/doc.1').existsSync(), isTrue);
    expect(
      String.fromCharCodes(await vault.readObject('doc', version: 1)),
      'v1',
    );
    expect(String.fromCharCodes(await vault.readObject('doc')), 'v2');
  });
}
