// DiagnosticsExporter —— 诊断信息导出（2026-09-27 增量新增）。
//
// 本地优先应用的用户遇到问题时，需要一个「自助取现场」的出口：把
// 应用环境 + 脱敏审计日志整理成纯文本，用户可自行检查后发送给开发者。
// 敏感纪律与 AuditLogger 一致：内容为错误类型/库名级别（无路径、无
// 正文、无密钥材料）；本导出器不做任何额外脱敏——它只信任输入方
// （调用方保证传入的 entries 来自 AuditLogger.snapshot()）。
library;

/// 诊断报告纯文本构建器（设置页「导出诊断信息」的数据面）。
abstract final class DiagnosticsExporter {
  /// 构建诊断报告。
  ///
  /// [platformInfo] 为平台摘要行（OS/Dart 版本，由调用方用
  /// `Platform.operatingSystem` / `Platform.version` 组装）；
  /// [localeName] 当前生效语言；[auditIntegrity] 为审计哈希链校验结果；
  /// [auditEntries] 为 AuditLogger.snapshot()（已按设计脱敏）。
  static String buildReport({
    required String platformInfo,
    required String localeName,
    required bool auditIntegrity,
    required List<String> auditEntries,
  }) {
    final buffer = StringBuffer()
      ..writeln('=== 绘图笔记 诊断信息（已脱敏） ===')
      ..writeln('生成时间: ${DateTime.now().toIso8601String()}')
      ..writeln('平台: $platformInfo')
      ..writeln('语言: $localeName')
      ..writeln('审计日志完整性: ${auditIntegrity ? '通过' : '异常（哈希链断裂）'}')
      ..writeln('审计条目数: ${auditEntries.length}')
      ..writeln()
      ..writeln('=== 审计日志（近 ${auditEntries.length} 条，仅错误类型级别） ===');
    if (auditEntries.isEmpty) {
      buffer.writeln('(无条目)');
    } else {
      for (final entry in auditEntries) {
        buffer.writeln(entry);
      }
    }
    return buffer.toString();
  }
}
