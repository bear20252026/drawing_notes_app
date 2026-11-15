// DiagnosticsExporter 单测（2026-09-27 增量）：报告结构 + 完整性声明 + 空条目。
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/security/audit_logger.dart';
import 'package:drawing_notes_app/features/notes/application/diagnostics_exporter.dart';

void main() {
  setUp(AuditLogger.clear);

  test('报告包含平台/语言/完整性声明与审计条目', () {
    AuditLogger.log('editor.crop.save_failed', success: false, detail: 'FormatException');

    final report = DiagnosticsExporter.buildReport(
      platformInfo: 'windows 10.0 · Dart 3.12.2',
      localeName: 'zh',
      auditIntegrity: true,
      auditEntries: AuditLogger.snapshot(),
    );

    expect(report, contains('=== 绘图笔记 诊断信息'));
    expect(report, contains('平台: windows 10.0 · Dart 3.12.2'));
    expect(report, contains('语言: zh'));
    // DN-009 口径诚实化（M-05 加固后 2026-11-15 同步）：完整性行必须自带
    // 校验范围（落盘为权威、未落盘时内存最近 N 条），如实标注带密钥锚的
    // 能力与**残余边界**（锚与日志同盘），不得让「通过」被读成「绝对完好」。
    expect(report, contains('审计日志完整性: 通过 —— 校验范围: 已解析落盘文件'));
    expect(report, contains('未落盘时校验本进程内存最近 1 条'));
    expect(report, contains('audit.log.1/audit.log'));
    expect(report, contains('带密钥 HMAC-SHA256 锚 + 世代单调校验'));
    expect(report, contains('篡改可检测 tamper-evident'));
    expect(report, contains('残余边界: 锚密钥与日志同盘'));
    expect(report, contains('审计条目数: 1'));
    expect(report, contains('editor.crop.save_failed'));
  });

  test('完整性异常时明确标出哈希链断裂', () {
    final report = DiagnosticsExporter.buildReport(
      platformInfo: 'windows',
      localeName: 'en',
      auditIntegrity: false,
      auditEntries: const [],
    );
    expect(report, contains('审计日志完整性: 异常（哈希链断裂）'));
    expect(report, contains('未落盘时校验本进程内存最近 0 条'));
    expect(report, contains('(无条目)'));
  });

  // 外部锚凭据（M-05 残余边界补强，2026-11-15）：报告须给出可抄存到独立
  // 介质的凭据，且凭据不含密钥材料。
  test('外部锚凭据：给出世代/计数/尾哈希与留存指引，不含密钥', () {
    final report = DiagnosticsExporter.buildReport(
      platformInfo: 'windows',
      localeName: 'zh',
      auditIntegrity: true,
      auditEntries: const ['op-a'],
      externalAnchor: {
        'v': 1,
        'generation': 3,
        'entryCount': 42,
        'tailHash': 'a' * 64,
        'exportedAt': '2026-11-15T00:00:00Z',
      },
    );
    expect(report, contains('外部锚凭据'));
    expect(report, contains('独立介质'));
    expect(report, contains('凭据不含密钥'));
    expect(report, contains('世代号: 3'));
    expect(report, contains('条目数: 42'));
    expect(report, contains('尾哈希: ${'a' * 64}'));
    expect(report, contains('导出时刻: 2026-11-15T00:00:00Z'));
  });

  test('无外部锚（未落盘/锚未加载）：不输出凭据段，不伪造', () {
    final report = DiagnosticsExporter.buildReport(
      platformInfo: 'windows',
      localeName: 'zh',
      auditIntegrity: true,
      auditEntries: const [],
    );
    expect(report, isNot(contains('外部锚凭据')));
    expect(report, isNot(contains('尾哈希:')));
  });
}
