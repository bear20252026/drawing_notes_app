// DiagnosticsExporter —— 诊断信息导出（2026-09-27 增量新增）。
//
// 本地优先应用的用户遇到问题时，需要一个「自助取现场」的出口：把
// 应用环境 + 脱敏审计日志整理成纯文本，用户可自行检查后发送给开发者。
// 敏感纪律与 AuditLogger 一致：内容为错误类型/库名级别（无路径、无
// 正文、无密钥材料）；本导出器不做任何额外脱敏——它只信任输入方
// （调用方保证传入的 entries 来自 AuditLogger.snapshot()）。
library;

import 'dart:io' show Platform;

/// 诊断报告纯文本构建器（设置页「导出诊断信息」的数据面）。
abstract final class DiagnosticsExporter {
  /// 平台摘要行（OS/Dart 版本）。
  ///
  /// H1 架构修复（2026-11）：平台信息组装收在本 application 层——
  /// presentation 不再 `import 'dart:io'` 取 `Platform.*`，只消费字符串。
  static String platformSummary() =>
      '${Platform.operatingSystem} ${Platform.operatingSystemVersion} · '
      'Dart ${Platform.version.split(' ').first}';

  /// 构建诊断报告。
  ///
  /// [platformInfo] 为平台摘要行（OS/Dart 版本，由调用方用
  /// `Platform.operatingSystem` / `Platform.version` 组装）；
  /// [localeName] 当前生效语言；[auditIntegrity] 为
  /// `AuditLogger.verifyIntegrity()` 的结果——语义为**内存链（本进程最近
  /// ≤1000 条）+ 已解析落盘 sink 后写出的 audit.log.1/audit.log 双段重放**
  /// （2026-11-10 起含跨重启历史；全新进程首次 log 前文件侧跳过）。链为
  /// 无密钥 SHA-256，保证等级 tamper-evident；尾截断/整段删除/跨段拼接
  /// 不可检（见 SECURITY.md「审计链的保证边界」），报告文案已按此限定；
  /// [auditEntries] 为 AuditLogger.snapshot()（已按设计脱敏，内存链视图，
  /// 其长度即内存侧校验覆盖条数）。
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
      // 口径诚实化（外部审计 DN-009，2026-10-11；2026-11-13 全面审计随
      // 文件侧重放实现对齐）：verifyIntegrity() 重放内存链（最近 ≤1000 条）
      // 与已解析落盘文件（audit.log.1 + audit.log，含跨重启历史）；链是
      // **无密钥** SHA-256（能改文件的攻击者可整链重算），尾截断/整段删除/
      // 跨段拼接不可检。「通过」不得被读成「落盘审计日志全量完好」。
      ..writeln(
        '审计日志完整性: ${auditIntegrity ? '通过' : '异常（哈希链断裂）'}'
        ' —— 校验范围: 本进程内存保留的最近 ${auditEntries.length} 条'
        ' + 已解析落盘文件（audit.log.1/audit.log，含跨重启历史；首次 log 前文件侧跳过）；'
        '无密钥哈希链，尾截断/整段删除不可检，'
        '保证等级为篡改可检测 tamper-evident',
      )
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
