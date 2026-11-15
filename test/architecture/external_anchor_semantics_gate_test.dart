/// 外部锚语义门禁（2026-11-15）。
///
/// 一句话：外部锚是**防整链重算的最后一道**，它的价值全在「不谎报」三个字。
/// 一旦有人把「无从判定」改成「通过」、或把凭据里塞进密钥材料，这道防线就
/// 变成了虚假的安全感——比没有更糟。本门禁把三条契约钉死：
///
/// 1. **凭据不含密钥**：导出字段白名单固定，不得出现 key/mac/anchorKey 等。
/// 2. **无从判定必须返回 null**，不得返回 true（前缀丢失/未落盘/锚未加载）。
/// 3. **秘密值比较走恒定时间工具**，不得裸 == 比哈希。
///
/// 附带行为锁：篡改历史后校验必须 false（这道防线的存在意义）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/security/audit_logger.dart';

const String _src = 'lib/core/security/audit_logger.dart';

final RegExp _comment = RegExp(r'^\s*(//|///|\*)');

/// 凭据允许出现的字段（白名单——新增字段须同步本门禁并复核是否含密钥）。
const Set<String> _allowedAnchorFields = {
  'v',
  'generation',
  'tailHash',
  'entryCount',
  'exportedAt',
};

/// 提取 exportExternalAnchor 方法体（到下一个静态方法声明为止）。
String _exportBody() {
  final lines = File(_src).readAsLinesSync();
  final start = lines.indexWhere(
    (l) => l.contains('static Map<String, Object?>? exportExternalAnchor()'),
  );
  expect(start, greaterThanOrEqualTo(0), reason: '找不到导出方法——抽取器失效');
  final buf = StringBuffer();
  for (var i = start; i < lines.length; i++) {
    if (i > start && RegExp(r'^  static ').hasMatch(lines[i])) break;
    buf.writeln(lines[i]);
  }
  return buf.toString();
}

void main() {
  group('门禁：凭据不含密钥材料', () {
    test('导出字段在白名单内（新增字段须复核）', () {
      final body = _exportBody();
      // 抓返回 map 里的 'xxx': 键名。
      final keys = RegExp(r"'([A-Za-z_][A-Za-z0-9_]*)'\s*:")
          .allMatches(body)
          .map((m) => m.group(1)!)
          .toSet();
      expect(keys, isNotEmpty, reason: '扫不到字段说明抽取器失效');
      final extra = keys.difference(_allowedAnchorFields);
      expect(
        extra,
        isEmpty,
        reason: '凭据出现白名单外字段 $extra——须复核是否含密钥材料，'
            '并同步本门禁白名单',
      );
    });

    test('导出方法体内不出现密钥标识符（key/mac/anchorKey）', () {
      final body = _exportBody();
      final codeLines = body
          .split('\n')
          .where((l) => !_comment.hasMatch(l))
          .join('\n');
      // 允许 _anchorKey != null 的存在性判定，禁止把它的值写进凭据。
      expect(
        RegExp(r"'key'\s*:|'mac'\s*:|'anchorKey'\s*:").hasMatch(codeLines),
        isFalse,
        reason: '凭据不得含密钥/MAC 材料——它要能被安全打印外传',
      );
      expect(
        RegExp(r'base64Encode\(_anchorKey').hasMatch(codeLines),
        isFalse,
        reason: '不得把锚密钥编码进凭据',
      );
    });
  });

  group('门禁：无从判定不谎报通过', () {
    test('校验方法保留 null 返回路径（前缀丢失/未就绪）', () {
      final lines = File(_src).readAsLinesSync();
      final start = lines.indexWhere(
        (l) => l.contains('static bool? verifyAgainstExternalAnchor('),
      );
      expect(start, greaterThanOrEqualTo(0));
      final buf = StringBuffer();
      for (var i = start; i < lines.length; i++) {
        if (i > start && RegExp(r'^  static ').hasMatch(lines[i])) break;
        buf.writeln(lines[i]);
      }
      final body = buf.toString();
      expect(
        body.contains('return null'),
        isTrue,
        reason: '「无从判定」必须返回 null，不得改成 true 谎报通过',
      );
      // 返回类型必须是可空 bool（三态：true/false/null）。
      expect(
        lines[start].contains('bool?'),
        isTrue,
        reason: '返回类型须保持 bool?（三态语义），不得收窄成 bool',
      );
    });

    test('哈希比对走恒定时间工具，不裸 ==', () {
      final lines = File(_src).readAsLinesSync();
      final start = lines.indexWhere(
        (l) => l.contains('static bool? verifyAgainstExternalAnchor('),
      );
      final buf = StringBuffer();
      for (var i = start; i < lines.length; i++) {
        if (i > start && RegExp(r'^  static ').hasMatch(lines[i])) break;
        buf.writeln(lines[i]);
      }
      final body = buf.toString();
      expect(
        body.contains('ct.constantTimeEquals'),
        isTrue,
        reason: '凭据尾哈希是秘密值，比较必须走恒定时间工具',
      );
    });
  });

  group('行为锁：这道防线真的有效', () {
    late Directory tempDir;
    late File sinkFile;

    setUp(() async {
      AuditLogger.clear();
      AuditLogger.resetSinkForTest();
      tempDir = await Directory.systemTemp.createTemp('anchor_gate_');
      sinkFile = File('${tempDir.path}${Platform.pathSeparator}audit.log');
      AuditLogger.sinkOverrideForTest = sinkFile;
    });

    tearDown(() async {
      await AuditLogger.flushForTest();
      AuditLogger.clear();
      AuditLogger.resetSinkForTest();
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    test('未落盘时导出 null（不伪造凭据）', () {
      expect(AuditLogger.exportExternalAnchor(), isNull);
    });

    test('凭据字段恰为白名单五项', () async {
      AuditLogger.log('gate.op');
      await AuditLogger.flushForTest();
      final anchor = AuditLogger.exportExternalAnchor()!;
      expect(anchor.keys.toSet(), _allowedAnchorFields);
    });

    test('篡改历史 → 校验 false（防线存在意义）', () async {
      AuditLogger.log('gate.op', detail: 'orig');
      await AuditLogger.flushForTest();
      final anchor = AuditLogger.exportExternalAnchor()!;
      final lines = sinkFile.readAsLinesSync();
      final forged = lines.map((l) {
        final m = l.contains('gate.op')
            ? l.replaceAll('"hash":"', '"hash":"deadbeef')
            : l;
        return m;
      }).join('\n');
      sinkFile.writeAsStringSync('$forged\n');
      expect(AuditLogger.verifyAgainstExternalAnchor(anchor), isFalse);
    });
  });
}