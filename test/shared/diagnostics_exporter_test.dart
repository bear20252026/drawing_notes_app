// DiagnosticsExporter 单测（2026-09-27 增量）：报告结构 + 完整性声明 + 空条目。
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/security/audit_logger.dart';
import 'package:drawing_notes_app/shared/application/diagnostics_exporter.dart';

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
    expect(report, contains('审计日志完整性: 通过'));
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
    expect(report, contains('(无条目)'));
  });
}
