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
    // DN-009 口径诚实化（2026-11-13 随文件侧重放实现对齐）：完整性行必须
    // 自带校验范围（内存最近 N 条 + 已解析落盘文件），并如实标注无密钥链的
    // 尾截断/整段删除盲区，不得让「通过」被读成「落盘全量日志完好」。
    expect(
      report,
      contains('审计日志完整性: 通过 —— 校验范围: 本进程内存保留的最近 1 条'),
    );
    expect(report, contains('已解析落盘文件（audit.log.1/audit.log'));
    expect(report, contains('尾截断/整段删除不可检'));
    expect(report, contains('篡改可检测 tamper-evident'));
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
    expect(
      report,
      contains('审计日志完整性: 异常（哈希链断裂） —— 校验范围: 本进程内存保留的最近 0 条'),
    );
    expect(report, contains('(无条目)'));
  });
}
