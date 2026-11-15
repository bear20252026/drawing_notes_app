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
  ///
  /// [externalAnchor] 为 `AuditLogger.exportExternalAnchor()` 的结果（可空）：
  /// 外部追加锚凭据（世代号 + 尾哈希 + 计数，**不含密钥**）。写进报告让用户
  /// 可把它抄到独立介质，事后校验能发现「攻击者同时持有锚密钥与文件写权限」
  /// 时的整链重算——这是 M-05 残余边界的补强出口。
  static String buildReport({
    required String platformInfo,
    required String localeName,
    required bool auditIntegrity,
    required List<String> auditEntries,
    Map<String, Object?>? externalAnchor,
  }) {
    final buffer = StringBuffer()
      ..writeln('=== 绘图笔记 诊断信息（已脱敏） ===')
      ..writeln('生成时间: ${DateTime.now().toIso8601String()}')
      ..writeln('平台: $platformInfo')
      ..writeln('语言: $localeName')
      // 口径诚实化（外部审计 DN-009，2026-10-11；M-05 加固 2026-11-14 后
      // 于 2026-11-15 同步本文案）：链已升级为**带密钥 HMAC-SHA256 + 世代号**，
      // verifyIntegrity() 落盘就绪时以文件链为权威重放 + 世代单调校验。
      // 无锚密钥的攻击者无法整链重算/整段删除/跨段拼接；残余边界是锚密钥与
      // 日志同盘（同时取得两者仍可重算）——故附外部锚凭据供独立介质留存。
      // 「通过」仍不得被读成「落盘审计日志绝对完好」。
      ..writeln(
        '审计日志完整性: ${auditIntegrity ? '通过' : '异常（哈希链断裂）'}'
        ' —— 校验范围: 已解析落盘文件（audit.log.1/audit.log，含跨重启历史）'
        '为权威，未落盘时校验本进程内存最近 ${auditEntries.length} 条；'
        '带密钥 HMAC-SHA256 锚 + 世代单调校验，'
        '保证等级为篡改可检测 tamper-evident；'
        '残余边界: 锚密钥与日志同盘，同时取得两者仍可整链重算'
        '${externalAnchor != null ? '（请用下方凭据留存到独立介质）' : '（本次未落盘，无凭据可导出）'}',
      )
      ..writeln('审计条目数: ${auditEntries.length}');
    if (externalAnchor != null) {
      buffer
        ..writeln()
        ..writeln('=== 外部锚凭据（请抄存到独立介质：另一设备/打印/密码管理器） ===')
        ..writeln('用途: 事后比对可发现整链重算（凭据不含密钥，可安全外传）')
        ..writeln('格式版本: ${externalAnchor['v']}')
        ..writeln('世代号: ${externalAnchor['generation']}')
        ..writeln('条目数: ${externalAnchor['entryCount']}')
        ..writeln('尾哈希: ${externalAnchor['tailHash']}')
        ..writeln('导出时刻: ${externalAnchor['exportedAt']}');
    }
    buffer
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
