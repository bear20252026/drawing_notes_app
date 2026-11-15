import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/security/session_secrets.dart';
import 'package:drawing_notes_app/core/storage/vfs/vault_service.dart';
import 'helpers/temp_dir_cleanup.dart';

/// VFS 统一服务单测（专家目标架构 VFS 接入层——2026-08-16）：
/// 对象 CRUD/密钥上下文（未注入拒绝）/跨会话持久化。
void main() {
  late Directory tempDir;
  final key = List<int>.generate(32, (i) => i);

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('vault_service_test');
  });

  tearDown(() => deleteTempDirWithRetry(tempDir));

  test('VaultService：对象 CRUD——写入/读取/清单（usecase key 标识）', () async {
    final service = VaultService(directory: tempDir);
    service.setKey(key);
    final plain = Uint8List.fromList(utf8.encode('机密媒体'));
    await service.putObject('media/note-1', plain: plain, type: 'media');
    expect(await service.getObject('media/note-1'), plain);
    final entries = await service.listObjects();
    expect(entries, hasLength(1));
    expect(entries.first.id, 'media/note-1');
    expect(entries.first.type, 'media');
  });

  test('VaultService：密钥上下文——未注入密钥拒绝（受控下发）', () async {
    final service = VaultService(directory: tempDir);
    // 未注入密钥——读写拒绝（受控密钥下发——掘金密文存储模式）。
    expect(
      () => service.putObject('media/x', plain: Uint8List(4)),
      throwsStateError,
    );
  });

  test('VaultService：跨会话持久化——重新构造后对象仍可读', () async {
    final first = VaultService(directory: tempDir);
    first.setKey(key);
    await first.putObject(
      'index/notes',
      plain: Uint8List.fromList(utf8.encode('清单数据')),
    );
    // 重新构造（模拟新会话——持久化介质不变）。
    final second = VaultService(directory: tempDir);
    second.setKey(key);
    expect(utf8.decode(await second.getObject('index/notes')), '清单数据');
  });

  test('VaultService：clearKey 后拒绝（D-2 内存清零语义）', () async {
    final service = VaultService(directory: tempDir);
    service.setKey(key);
    service.clearKey();
    expect(service.hasKey, isFalse);
    expect(() => service.getObject('media/x'), throwsStateError);
  });

  // M-04（2026-11-14）：VFS 会话密钥是主密钥副本——回锁时随统一清理注册表
  // 一并清零（此前 lock() 只清权威 MK，VFS 副本整会话驻留内存）。
  test('VaultService：注册进 SessionSecrets——clearAll 联动清零（M-04）', () async {
    final service = VaultService(directory: tempDir);
    service.setKey(key);
    expect(service.hasKey, isTrue);
    // 回锁收口（AppLockGate.hidden / 超宽限）调 SessionSecrets.clearAll()。
    SessionSecrets.clearAll();
    expect(service.hasKey, isFalse, reason: 'VFS 副本随回锁清零，不再驻留');
    expect(() => service.getObject('media/x'), throwsStateError);
  });

  test('VaultService：clearAllSessionSecrets 幂等清零（M-04）', () async {
    final service = VaultService(directory: tempDir);
    service.setKey(key);
    service.clearAllSessionSecrets();
    expect(service.hasKey, isFalse);
    // 幂等：再清一次不抛错。
    service.clearAllSessionSecrets();
    expect(service.hasKey, isFalse);
  });
}
