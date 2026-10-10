import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/security/audit_logger.dart';

/// 红蓝攻防 P2 修复（2026-08-15）：安全审计日志——记录密钥加载/密码盘
/// 操作（时间戳+操作+结果），仅本地内存、绝不含密钥与内容。
void main() {
  late Directory tempDir;
  File? sinkFile;

  setUp(AuditLogger.clear);
  tearDown(() async {
    AuditLogger.resetSinkForTest();
    sinkFile = null;
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  test('审计日志：记录操作/时间/结果', () {
    AuditLogger.log('password_disk.unlock');
    AuditLogger.log('password_disk.read_key', success: false);
    final snap = AuditLogger.snapshot();
    expect(snap.length, 2);
    expect(snap[0], contains('password_disk.unlock'));
    expect(snap[0], contains('OK'));
    expect(snap[1], contains('FAIL'));
    expect(snap[0], startsWith('['), reason: '时间戳前缀');
  });

  test('审计日志：clear 清空（测试隔离）', () {
    AuditLogger.log('x');
    expect(AuditLogger.snapshot(), hasLength(1));
    AuditLogger.clear();
    expect(AuditLogger.snapshot(), isEmpty);
  });

  test('哈希链：日志链完整——verifyIntegrity 通过', () {
    AuditLogger.clear();
    AuditLogger.log('policy.note.import.pdf');
    AuditLogger.log('password_disk.read_key', success: false);
    AuditLogger.log('media.encrypt', detail: 'note-a');
    expect(AuditLogger.verifyIntegrity(), isTrue);
    expect(AuditLogger.snapshot(), hasLength(3));
  });

  test('哈希链：clear 重置后链重新开始', () {
    AuditLogger.log('x');
    AuditLogger.clear();
    expect(AuditLogger.verifyIntegrity(), isTrue, reason: '空链验证通过');
    AuditLogger.log('y');
    expect(AuditLogger.verifyIntegrity(), isTrue);
  });

  test('哈希链：连续日志哈希推进（链完整）', () {
    AuditLogger.clear();
    AuditLogger.log('a');
    AuditLogger.log('b');
    expect(AuditLogger.snapshot(), hasLength(2));
    expect(AuditLogger.verifyIntegrity(), isTrue);
  });

  // 修复 1（审计 2026-10-04）：滚动裁剪后 verifyIntegrity 从链真实起点
  // （checkpoint 锚点）重放，不再因「被删头部仍是新首条 prevHash」恒报篡改。
  test('哈希链：滚动裁剪超上限后 verifyIntegrity 仍为 true（锚点重放）', () {
    for (var i = 0; i < 1010; i++) {
      AuditLogger.log('session.op.$i');
    }
    expect(AuditLogger.snapshot(), hasLength(1000));
    expect(AuditLogger.droppedCountForTest, 10);
    expect(
      AuditLogger.verifyIntegrity(),
      isTrue,
      reason: '裁剪后应从链真实起点重放，不得把正常长会话日志判成被篡改',
    );
  });

  test('哈希链：裁剪后篡改中间某条仍断链（断链能力未回退）', () {
    for (var i = 0; i < 1010; i++) {
      AuditLogger.log('session.op.$i');
    }
    expect(AuditLogger.verifyIntegrity(), isTrue);
    AuditLogger.tamperEntryForTest(500); // 改 detail 留旧 hash。
    expect(
      AuditLogger.verifyIntegrity(),
      isFalse,
      reason: '锚点从中间起 replay 后逐条重算，被改条目哈希必不匹配',
    );
  });

  test('哈希链：clear 归零 checkpoint——新链独立而非伪造历史连续', () {
    for (var i = 0; i < 1010; i++) {
      AuditLogger.log('old.$i');
    }
    expect(AuditLogger.droppedCountForTest, greaterThan(0));
    AuditLogger.clear();
    expect(AuditLogger.droppedCountForTest, 0);
    expect(AuditLogger.snapshot(), isEmpty);
    // clear 后是一条全新独立链（首条 prevHash 回到 genesis），不复用旧锚点。
    AuditLogger.log('new.0');
    expect(AuditLogger.verifyIntegrity(), isTrue);
  });

  group('落盘（2026-10-10，挂账轻项）', () {
    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('audit_sink_');
      sinkFile = File(
        '${tempDir.path}${Platform.pathSeparator}security'
        '${Platform.pathSeparator}audit.log',
      );
      AuditLogger.sinkOverrideForTest = sinkFile;
    });

    test('log 后异步追加 JSONL：字段含链字段，重放可验证', () async {
      AuditLogger.log('password_disk.unlock');
      AuditLogger.log(
        'policy.note.import.pdf',
        success: false,
        detail: 'too_large',
      );
      await AuditLogger.flushForTest();

      expect(sinkFile!.existsSync(), isTrue);
      final lines = sinkFile!.readAsLinesSync();
      expect(lines, hasLength(2));
      final first = jsonDecode(lines[0]) as Map<String, dynamic>;
      expect(first['operation'], 'password_disk.unlock');
      expect(first['success'], isTrue);
      expect(first['prevHash'], hasLength(64));
      expect(first['hash'], hasLength(64));
      final second = jsonDecode(lines[1]) as Map<String, dynamic>;
      // 文件侧链连续：第二条 prevHash = 第一条 hash。
      expect(second['prevHash'], first['hash']);
      expect(second['success'], isFalse);
      expect(second['detail'], 'too_large');
    });

    test('轮转：超过 1MiB 上限 → audit.log 转为 audit.log.1，续写新文件', () async {
      // ~600B/条 ⇒ 约 2500 条 ≈ 1.5MiB，必然跨过轮转线（生产口径 1MiB）。
      for (var i = 0; i < 2500; i++) {
        AuditLogger.log('fill.$i', detail: 'x' * 500);
      }
      await AuditLogger.flushForTest();
      final rotated = File('${sinkFile!.path}.1');
      expect(rotated.existsSync(), isTrue, reason: '1.5MiB 已跨 1MiB 轮转线');
      expect(rotated.lengthSync(), greaterThan(1 << 20), reason: '轮转文件承载超限前全量');
      expect(sinkFile!.existsSync(), isTrue, reason: '轮转后继续在新文件追加');
      final tailCount = sinkFile!.readAsLinesSync().length;
      expect(tailCount, greaterThan(0), reason: '轮转后有续写');
      expect(tailCount, lessThan(2500), reason: '轮转把大部分历史挪进了 .1');
    });

    test('sink 抛错不阻断业务：内存链照常、文件缺失', () async {
      final badSink = File(
        '${tempDir.path}${Platform.pathSeparator}no_dir'
        '${Platform.pathSeparator}sub${Platform.pathSeparator}audit.log',
      );
      // 父路径造成**文件**——对其 create(recursive:true) 必失败。
      File('${tempDir.path}${Platform.pathSeparator}no_dir')
          .writeAsStringSync('x');
      AuditLogger.sinkOverrideForTest = badSink;
      AuditLogger.log('should.not.throw');
      await AuditLogger.flushForTest();
      expect(AuditLogger.snapshot(), hasLength(1), reason: '内存链不受落盘失败影响');
      expect(badSink.existsSync(), isFalse);
      expect(AuditLogger.verifyIntegrity(), isTrue);
    });
  });
}
