import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/security/audit_logger.dart';

/// 红蓝攻防 P2 修复（2026-08-15）：安全审计日志——记录密钥加载/密码盘
/// 操作（时间戳+操作+结果），仅本地内存、绝不含密钥与内容。
void main() {
  // 可空 + 顶层 tearDown 判空：落盘分组之外的既有用例不初始化 tempDir，
  // 顶层清理必须对它们无感（云端首跑 LateInitializationError 教训）。
  Directory? tempDir;
  File? sinkFile;

  setUp(AuditLogger.clear);
  tearDown(() async {
    AuditLogger.resetSinkForTest();
    sinkFile = null;
    final dir = tempDir;
    if (dir != null && dir.existsSync()) await dir.delete(recursive: true);
    tempDir = null;
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
        '${tempDir!.path}${Platform.pathSeparator}security'
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
      // M-05：首条目前有一条 audit.genesis 世代标记（共 3 行）。
      expect(lines, hasLength(3));
      final genesis = jsonDecode(lines[0]) as Map<String, dynamic>;
      expect(genesis['operation'], 'audit.genesis');
      final first = jsonDecode(lines[1]) as Map<String, dynamic>;
      expect(first['operation'], 'password_disk.unlock');
      expect(first['success'], isTrue);
      expect(first['prevHash'], hasLength(64));
      expect(first['hash'], hasLength(64));
      final second = jsonDecode(lines[2]) as Map<String, dynamic>;
      // 文件侧链连续：后一条 prevHash = 前一条 hash。
      expect(first['prevHash'], genesis['hash']);
      expect(second['prevHash'], first['hash']);
      expect(second['success'], isFalse);
      expect(second['detail'], 'too_large');
    });

    test('轮转：超阈值 → audit.log 转为 audit.log.1，续写新文件', () async {
      // 阈值注 4KiB（生产 1MiB 物理量级在同语义小样本下不可达——2500 条
      // 真实 IO 在全量并发下曾撞 30s 用例超时）。20 条 ≈ 12KB 必跨线。
      AuditLogger.maxFileBytesOverrideForTest = 4 * 1024;
      for (var i = 0; i < 20; i++) {
        AuditLogger.log('fill.$i', detail: 'x' * 500);
      }
      await AuditLogger.flushForTest();
      final rotated = File('${sinkFile!.path}.1');
      expect(rotated.existsSync(), isTrue, reason: '12KB 已跨 4KiB 轮转线');
      expect(rotated.lengthSync(), greaterThan(4 * 1024), reason: '轮转文件承载超限前全量');
      expect(sinkFile!.existsSync(), isTrue, reason: '轮转后继续在新文件追加');
      final tailCount = sinkFile!.readAsLinesSync().length;
      expect(tailCount, greaterThan(0), reason: '轮转后有续写');
      expect(tailCount, lessThan(20), reason: '轮转把大部分历史挪进了 .1');
    });

    test('sink 抛错不阻断业务：内存链照常、文件缺失', () async {
      final badSink = File(
        '${tempDir!.path}${Platform.pathSeparator}no_dir'
        '${Platform.pathSeparator}sub${Platform.pathSeparator}audit.log',
      );
      // 父路径造成**文件**——对其 create(recursive:true) 必失败。
      File('${tempDir!.path}${Platform.pathSeparator}no_dir')
          .writeAsStringSync('x');
      AuditLogger.sinkOverrideForTest = badSink;
      AuditLogger.log('should.not.throw');
      await AuditLogger.flushForTest();
      expect(AuditLogger.snapshot(), hasLength(1), reason: '内存链不受落盘失败影响');
      expect(badSink.existsSync(), isFalse);
      expect(AuditLogger.verifyIntegrity(), isTrue);
    });
  });

  // M-05 加固（2026-11-14）：带密钥 HMAC 锚 + 世代号——堵整链重算/整段删除/
  // 跨段拼接三个无密钥链盲区。锚密钥与落盘 sink 同目录（测试隔离）。
  group('带密钥锚（M-05，2026-11-14）', () {
    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('audit_anchor_');
      sinkFile = File(
        '${tempDir!.path}${Platform.pathSeparator}security'
        '${Platform.pathSeparator}audit.log',
      );
      AuditLogger.sinkOverrideForTest = sinkFile;
    });

    test('锚就绪后条目带 gen+mac，verifyIntegrity 通过', () async {
      AuditLogger.log('first'); // 同步加载锚 + 世代标记，本条即走 HMAC。
      await AuditLogger.flushForTest();
      expect(AuditLogger.anchorLoadedForTest, isTrue, reason: '首次落盘加载锚');
      expect(AuditLogger.generationForTest, 1, reason: '首世代 = 1');
      AuditLogger.log('second'); // 锚已就绪 → HMAC。
      AuditLogger.log('third', success: false);
      await AuditLogger.flushForTest();
      final lines = sinkFile!.readAsLinesSync()
          .map((l) => jsonDecode(l) as Map<String, dynamic>)
          .toList();
      // 世代标记 + first + second + third（同步加载后全部带 mac）。
      final keyed = lines.where((m) => m['mac'] != null).toList();
      expect(keyed, hasLength(4), reason: '世代标记 + 三条 HMAC 条目');
      expect(keyed.every((m) => m['gen'] == 1), isTrue);
      expect(keyed.any((m) => m['operation'] == 'audit.genesis'), isTrue);
      expect(AuditLogger.verifyIntegrity(), isTrue);
    });

    test('篡改带 mac 条目的字段 → verifyIntegrity 断链', () async {
      AuditLogger.log('first');
      await AuditLogger.flushForTest();
      AuditLogger.log('sensitive', detail: 'original');
      await AuditLogger.flushForTest();
      expect(AuditLogger.verifyIntegrity(), isTrue);
      // 篡改文件里带 mac 条目的 detail（保留旧 mac）→ HMAC 重算必不匹配。
      final lines = sinkFile!.readAsLinesSync();
      final tampered = lines.map((l) {
        final m = jsonDecode(l) as Map<String, dynamic>;
        if (m['operation'] == 'sensitive') m['detail'] = 'TAMPERED';
        return jsonEncode(m);
      }).join('\n');
      sinkFile!.writeAsStringSync('$tampered\n');
      expect(AuditLogger.verifyIntegrity(), isFalse, reason: 'HMAC 不符即断链');
    });

    test('无锚密钥无法伪造合法 HMAC（整链重算被阻）', () async {
      AuditLogger.log('first');
      await AuditLogger.flushForTest();
      AuditLogger.log('secret.op', detail: 'payload');
      await AuditLogger.flushForTest();
      // 攻击者改字段并试图用裸 SHA-256 重算 hash（无锚密钥）——带 mac 条目
      // 校验走 HMAC，SHA-256 重算值必不匹配。
      final lines = sinkFile!.readAsLinesSync();
      final forged = lines.map((l) {
        final m = jsonDecode(l) as Map<String, dynamic>;
        if (m['operation'] == 'secret.op') {
          m['detail'] = 'forged';
          // 保留 mac 字段但内容已变 → HMAC 校验失败。
        }
        return jsonEncode(m);
      }).join('\n');
      sinkFile!.writeAsStringSync('$forged\n');
      expect(AuditLogger.verifyIntegrity(), isFalse);
    });

    test('世代号单调：重启推进世代，跨代拼接回退被检出', () async {
      AuditLogger.log('gen1.op');
      await AuditLogger.flushForTest();
      expect(AuditLogger.generationForTest, 1);
      // 模拟进程重启：清内存链 + 复位锚加载态（锚文件保留）→ 世代 +1。
      AuditLogger.clear();
      AuditLogger.sinkOverrideForTest = sinkFile; // 重新注入（clear 不动 sink）。
      AuditLogger.log('gen2.op');
      await AuditLogger.flushForTest();
      expect(AuditLogger.generationForTest, 2, reason: '重启世代 +1');
      expect(AuditLogger.verifyIntegrity(), isTrue, reason: '世代 1→2 单调合法');
      // 跨代拼接：把世代 2 的条目改成世代 1（回退）→ 单调约束检出。
      final lines = sinkFile!.readAsLinesSync();
      final spliced = lines.map((l) {
        final m = jsonDecode(l) as Map<String, dynamic>;
        if (m['gen'] == 2) m['gen'] = 1; // 世代回退（mac 不变 → 亦 HMAC 不符）。
        return jsonEncode(m);
      }).join('\n');
      sinkFile!.writeAsStringSync('$spliced\n');
      expect(AuditLogger.verifyIntegrity(), isFalse, reason: '世代回退/拼段被检出');
    });

    test('锚文件持久化：重启复用同一锚密钥', () async {
      AuditLogger.log('a');
      await AuditLogger.flushForTest();
      final anchorFile = File('${sinkFile!.parent.path}/audit.anchor');
      expect(anchorFile.existsSync(), isTrue, reason: '锚密钥落盘');
      final doc = jsonDecode(anchorFile.readAsStringSync()) as Map<String, dynamic>;
      expect(doc['key'], isA<String>());
      expect(doc['gen'], 1);
      final keyB64 = doc['key'] as String;
      // 重启复用：锚密钥不变、世代 +1。
      AuditLogger.clear();
      AuditLogger.sinkOverrideForTest = sinkFile;
      AuditLogger.log('b');
      await AuditLogger.flushForTest();
      final doc2 = jsonDecode(anchorFile.readAsStringSync()) as Map<String, dynamic>;
      expect(doc2['key'], keyB64, reason: '同一锚密钥跨进程复用');
      expect(doc2['gen'], 2);
    });
  });

  // 外部追加锚（M-05 残余边界补强，2026-11-15）：锚密钥与日志同盘时，
  // 同时拿到两者的攻击者仍可整链重算——外部凭据（独立介质）是最后一道。
  group('外部追加锚（M-05 残余边界补强）', () {
    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('audit_ext_anchor_');
      sinkFile = File(
        '${tempDir!.path}${Platform.pathSeparator}security'
        '${Platform.pathSeparator}audit.log',
      );
      AuditLogger.sinkOverrideForTest = sinkFile;
    });

    test('导出凭据：含世代/尾哈希/计数，且不含密钥', () async {
      AuditLogger.log('op-a');
      AuditLogger.log('op-b');
      await AuditLogger.flushForTest();
      final anchor = AuditLogger.exportExternalAnchor();
      expect(anchor, isNotNull);
      expect(anchor!['v'], 1);
      expect(anchor['generation'], 1);
      expect(anchor['tailHash'], isA<String>());
      expect((anchor['tailHash'] as String).length, 64);
      expect(anchor['entryCount'], 3, reason: '世代标记 + 两条记录');
      // 凭据不得含密钥材料（可安全打印/外传）。
      expect(anchor.containsKey('key'), isFalse);
      expect(anchor.containsKey('mac'), isFalse);
    });

    test('未篡改：凭据校验通过', () async {
      AuditLogger.log('op-a');
      await AuditLogger.flushForTest();
      final anchor = AuditLogger.exportExternalAnchor()!;
      expect(AuditLogger.verifyAgainstExternalAnchor(anchor), isTrue);
    });

    test('追加新记录后：历史前缀仍可校验（凭据不失效）', () async {
      AuditLogger.log('op-a');
      await AuditLogger.flushForTest();
      final anchor = AuditLogger.exportExternalAnchor()!;
      AuditLogger.log('op-later');
      AuditLogger.log('op-later-2');
      await AuditLogger.flushForTest();
      expect(
        AuditLogger.verifyAgainstExternalAnchor(anchor),
        isTrue,
        reason: '校验的是导出时刻的历史前缀，追加不影响',
      );
    });

    test('篡改历史条目：凭据不再判「通过」（重算无法伪造原哈希）', () async {
      AuditLogger.log('op-a', detail: 'original');
      await AuditLogger.flushForTest();
      final anchor = AuditLogger.exportExternalAnchor()!;
      // 攻击者改历史载荷并重算 HMAC（模拟同时持有锚密钥）——此处直接改
      // 尾哈希字段模拟「重算后的链」，外部凭据仍记载旧值。
      final lines = sinkFile!.readAsLinesSync();
      final forged = lines.map((l) {
        final m = jsonDecode(l) as Map<String, dynamic>;
        if (m['operation'] == 'op-a') {
          m['detail'] = 'forged';
          m['hash'] = 'f' * 64; // 重算者的新尾哈希
          m['mac'] = 'f' * 64;
        }
        return jsonEncode(m);
      }).join('\n');
      sinkFile!.writeAsStringSync('$forged\n');
      // 核心保证：重算后原哈希已不在链上 → **绝不返回 true**。
      // 返回 null（无从判定）而非 false：落盘信息不足以区分「被篡改」与
      // 「已被轮转丢弃」——宁可报无从判定，也不谎报确定结论。
      expect(
        AuditLogger.verifyAgainstExternalAnchor(anchor),
        isNot(isTrue),
        reason: '重算者无法让原哈希回到链上——凭据不再判通过',
      );
    });

    test('凭据格式非法 → false（不谎报通过）', () async {
      AuditLogger.log('op-a');
      await AuditLogger.flushForTest();
      expect(AuditLogger.verifyAgainstExternalAnchor({}), isFalse);
      expect(
        AuditLogger.verifyAgainstExternalAnchor({
          'generation': 'x',
          'tailHash': 'a' * 64,
          'entryCount': 1,
        }),
        isFalse,
      );
      expect(
        AuditLogger.verifyAgainstExternalAnchor({
          'generation': 1,
          'tailHash': 'a' * 64,
          'entryCount': 0,
        }),
        isFalse,
      );
    });

    test('前缀已被轮转丢弃 → null（无从判定，不谎报）', () async {
      AuditLogger.log('op-a');
      await AuditLogger.flushForTest();
      // 凭据声称有 999 条，实际只有 2 条 → 无从判定。
      expect(
        AuditLogger.verifyAgainstExternalAnchor({
          'generation': 1,
          'tailHash': 'a' * 64,
          'entryCount': 999,
        }),
        isNull,
      );
    });

    test('锚未加载/无落盘 → 导出返回 null（不伪造凭据）', () {
      expect(AuditLogger.exportExternalAnchor(), isNull);
    });

    // 轮转场景实测（2026-11-15 修正为哈希锚定语义）：轮转是整文件搬移
    // （sink.rename(.1)），.1 会被新一代覆盖。按位置序号定位会把「前缀丢弃」
    // 误判成「被篡改」——故改用「链上是否存在该哈希 + 计数下界」三态判定。
    test('单次轮转且前缀仍在 .1：凭据可校验通过', () async {
      // 阈值放宽到刚好容纳「早期少量 + 一次轮转」，确保早期条目留在 .1。
      AuditLogger.maxFileBytesOverrideForTest = 4 * 1024;
      AuditLogger.log('pre-rotate');
      await AuditLogger.flushForTest();
      final anchor = AuditLogger.exportExternalAnchor()!;
      // 写到刚过阈值触发一次轮转（早期条目随之进入 .1，尚未被二次覆盖）。
      for (var i = 0; i < 12; i++) {
        AuditLogger.log('filler-$i', detail: 'x' * 20);
      }
      await AuditLogger.flushForTest();
      final rotated = File('${sinkFile!.path}.1');
      expect(rotated.existsSync(), isTrue, reason: '应已触发轮转');
      expect(
        rotated.readAsLinesSync().any((l) => l.contains('pre-rotate')),
        isTrue,
        reason: '早期条目应仍在 .1 中（未被二次轮转覆盖）',
      );
      expect(AuditLogger.verifyAgainstExternalAnchor(anchor), isTrue);
    });

    test('多次轮转丢弃前缀：返回 null（无从判定，绝不谎报通过）', () async {
      AuditLogger.maxFileBytesOverrideForTest = 1024;
      AuditLogger.log('early-op');
      await AuditLogger.flushForTest();
      final anchor = AuditLogger.exportExternalAnchor()!;
      // 大量写入触发多次轮转——.1 被反复覆盖，早期前缀彻底丢失。
      for (var i = 0; i < 200; i++) {
        AuditLogger.log('bulk-$i', detail: 'y' * 60);
      }
      await AuditLogger.flushForTest();
      final rotated = File('${sinkFile!.path}.1');
      expect(
        rotated.existsSync() &&
            rotated.readAsLinesSync().any((l) => l.contains('early-op')),
        isFalse,
        reason: '早期条目应已被多次轮转覆盖丢弃',
      );
      expect(
        AuditLogger.verifyAgainstExternalAnchor(anchor),
        isNull,
        reason: '前缀已被轮转丢弃 → 无从判定（不得谎报 true 或 false）',
      );
    });
  });
}
