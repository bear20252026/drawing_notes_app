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
  /// [localeName] 当前生效语言；[auditIntegrity] 为
  /// `AuditLogger.verifyIntegrity()` 的结果——**语义仅限本进程内存保留的最近
  /// ≤1000 条无密钥哈希链**（该方法不读任何文件，落盘 `audit.log` /
  /// 轮转出的 `audit.log.1` 与跨重启历史不在校验范围内），报告文案已按此限定；
  /// [auditEntries] 为 AuditLogger.snapshot()（已按设计脱敏，且与上面校验的是
  /// 同一列表，故其长度即校验覆盖条数）。
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
      // 口径诚实化（外部审计 DN-009，2026-10-11）：AuditLogger.verifyIntegrity()
      // 只重放**本进程内存中保留的最近 ≤1000 条**、一个文件都不读，且链是
      // **无密钥** SHA-256（能改文件的攻击者可整链重算）。旧文案只写「通过」，
      // 会让用户把「内存近期链自洽」读成「落盘审计日志全量完好」。范围随状态值
      // 一并打印，条数直接取传入快照长度（与 verifyIntegrity 遍历的是同一列表）。
      ..writeln(
        '审计日志完整性: ${auditIntegrity ? '通过' : '异常（哈希链断裂）'}'
        ' —— 校验范围: 本进程内存保留的最近 ${auditEntries.length} 条无密钥哈希链，'
        '仅证明这段内存链自洽（不读落盘文件、不跨重启）；'
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
