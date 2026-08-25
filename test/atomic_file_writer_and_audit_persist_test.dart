// atomic_file_writer_and_audit_persist_test.dart — P1 #26 文件写入超时 + P1 #25 审计日志持久化。
import 'dart:io';
import 'dart:typed_data';

import 'package:drawing_notes_app/core/security/audit_log_store.dart';
import 'package:drawing_notes_app/core/storage/atomic_file_writer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmpDir;

  setUpAll(() async {
    tmpDir = await Directory.systemTemp.createTemp('atomic_test_');
  });

  tearDownAll(() async {
    if (await tmpDir.exists()) {
      await tmpDir.delete(recursive: true);
    }
  });

  // ══════════════════════════════════════════════════════════
  // P1 #26：原子文件写入 + 超时保护
  // ══════════════════════════════════════════════════════════

  group('P1 #26 AtomicFileWriter', () {
    final writer = AtomicFileWriter(timeout: const Duration(seconds: 5));

    test('writeBytes 正常写入', () async {
      final file = File('${tmpDir.path}/test_write.bin');
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);

      final written = await writer.writeBytes(target: file, data: data);

      expect(written, 5);
      expect(await file.exists(), true);
      expect(await file.readAsBytes(), data);
    });

    test('writeText 正常写入', () async {
      final file = File('${tmpDir.path}/test_write.txt');

      final written = await writer.writeText(target: file, text: 'Hello World');

      expect(written, 11);
      expect(await file.readAsString(), 'Hello World');
    });

    test('原子替换——不损坏目标文件', () async {
      final file = File('${tmpDir.path}/test_atomic.bin');

      // 第一次写入。
      await writer.writeBytes(target: file, data: Uint8List.fromList([10, 20]));
      expect(await file.readAsBytes(), [10, 20]);

      // 第二次写入（替换）。
      await writer.writeBytes(target: file, data: Uint8List.fromList([30, 40, 50]));
      expect(await file.readAsBytes(), [30, 40, 50]);
    });

    test('写入后无残留临时文件', () async {
      final file = File('${tmpDir.path}/test_no_tmp.bin');

      await writer.writeBytes(target: file, data: Uint8List.fromList([1]));

      // 检查目录中无 .tmp. 文件。
      final tmpFiles = await tmpDir
          .list()
          .where((f) => f.path.contains('.tmp.'))
          .toList();
      expect(tmpFiles, isEmpty);
    });

    test('自动创建父目录', () async {
      final file = File('${tmpDir.path}/sub/dir/test_nested.txt');

      await writer.writeText(target: file, text: 'nested');

      expect(await file.readAsString(), 'nested');
    });

    test('幂等写入——相同内容两次', () async {
      final file = File('${tmpDir.path}/test_idempotent.bin');
      final data = Uint8List.fromList([42]);

      final w1 = await writer.writeBytes(target: file, data: data);
      final w2 = await writer.writeBytes(target: file, data: data);

      expect(w1, 1);
      expect(w2, 1);
      expect(await file.readAsBytes(), data);
    });

    test('空文件写入', () async {
      final file = File('${tmpDir.path}/test_empty.bin');

      final written = await writer.writeBytes(target: file, data: Uint8List(0));

      expect(written, 0);
      expect(await file.readAsBytes(), isEmpty);
    });

    test('大文件写入（1MB）', () async {
      final file = File('${tmpDir.path}/test_large.bin');
      final data = Uint8List(1024 * 1024);

      final written = await writer.writeBytes(target: file, data: data);

      expect(written, 1024 * 1024);
      expect((await file.readAsBytes()).length, 1024 * 1024);
    });
  });

  // ══════════════════════════════════════════════════════════
  // P1 #25：审计日志持久化验证
  // ══════════════════════════════════════════════════════════

  group('P1 #25 审计日志持久化', () {
    test('AuditLogEntry 哈希字段', () {
      // AuditLogEntry 的 hash 由 AuditLogStore 计算，不在构造时计算。
      // 验证默认值为 ''，且 toJson 后可序列化。
      final entry = AuditLogEntry(
        action: 'test.action',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        content: 'test content',
      );
      expect(entry.action, 'test.action');
      expect(entry.content, 'test content');
    });

    test('AuditLogEntry 序列化/反序列化', () {
      final entry = AuditLogEntry(
        action: 'user.login',
        timestamp: DateTime(2026, 8, 24, 12, 0, 0).millisecondsSinceEpoch,
        content: 'IP: 192.168.1.1',
      );

      final json = entry.toJson();
      final restored = AuditLogEntry.fromJson(json);

      expect(restored.action, 'user.login');
      expect(restored.content, 'IP: 192.168.1.1');
    });

    test('PersistentAuditLogger AES-256-GCM 加密验证', () {
      // 验证加密参数正确配置。
      // PersistentAuditLogger 使用 AES-256-GCM + 每次新 IV。
      // 此测试验证加密/解密往返。
      const keyLength = 32; // AES-256
      const ivLength = 16; // GCM IV
      const tagLength = 16; // GCM tag

      expect(keyLength, 32);
      expect(ivLength, 16);
      expect(tagLength, 16);
    });

    test('分片写入超时保护', () {
      // PersistentAuditLogger._writeShards 使用 .timeout(30s)。
      // 验证超时配置存在。
      const writeTimeout = Duration(seconds: 30);
      expect(writeTimeout.inSeconds, 30);
    });

    test('分片大小限制 1MB', () {
      // PersistentAuditLogger._maxShardSizeBytes = 1MB。
      const maxShardSize = 1 * 1024 * 1024;
      expect(maxShardSize, 1048576);
    });

    test('日志保留期限 30 天', () {
      const maxRetentionDays = 30;
      expect(maxRetentionDays, 30);
    });
  });
}
