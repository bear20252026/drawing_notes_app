import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/infrastructure/storage/vfs/vault_service.dart';

/// VFS 统一服务单测（专家目标架构 VFS 接入层——2026-08-16）：
/// 对象 CRUD/密钥上下文（未注入拒绝）/跨会话持久化。
void main() {
  late Directory tempDir;
  final key = List<int>.generate(32, (i) => i);

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('vault_service_test');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } on Exception catch (_) {/* 忽略清理失败 */}
  });

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
    expect(
      utf8.decode(await second.getObject('index/notes')),
      '清单数据',
    );
  });

  test('VaultService：clearKey 后拒绝（D-2 内存清零语义）', () async {
    final service = VaultService(directory: tempDir);
    service.setKey(key);
    service.clearKey();
    expect(service.hasKey, isFalse);
    expect(
      () => service.getObject('media/x'),
      throwsStateError,
    );
  });
}
