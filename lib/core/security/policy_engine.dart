import 'package:drawing_notes_app/core/security/audit_logger.dart';

/// 策略执行引擎（专家审计最优先行动④——SessionGuard + PolicyEngine +
/// Capability，2026-08-16 落地）。
///
/// 默认拒绝策略层：操作白名单——未列入的操作一律拒绝（fail-closed，
/// hessra-cap/typesec 模式 + 掘金 Agent 工具安全框架 Policy Gate +
/// Flutter 官方 Capability/Policy 类）。代码内置规则为兜底（规则数据化
/// 失败不影响安全规则生效——掘金"保留代码层面的内置规则作为兜底"）。
/// deny/allow 都写审计（OpenClaw after-tool-call 审计完整性）。
enum PolicyMode { enforce, monitor }

/// 策略判定结果。
enum PolicyDecision { allow, deny }

/// 策略判定结果（含原因——供调用方提示/审计）。
class PolicyResult {
  const PolicyResult(this.decision, this.reason);

  final PolicyDecision decision;
  final String reason;

  bool get isAllowed => decision == PolicyDecision.allow;
}

/// 默认拒绝策略引擎：操作白名单 + 审计。
///
/// 导入/导出/删除等外部边界操作均须经 [check] 判定——deny 时调用方
/// 拒绝执行（enforce 模式）或仅记录（monitor 模式——策略调优期）。
class PolicyEngine {
  const PolicyEngine({this.mode = PolicyMode.enforce});

  final PolicyMode mode;

  /// 操作白名单（默认拒绝——未列入一律 deny）。
  /// 命名：`域.动作.子类型`——便于审计与按域扩展。
  static const Set<String> allowlistedOperations = {
    // 导入（低权限解析隔离器——PDF/文本/图片预检后入库）。
    'note.import.pdf',
    'note.import.text',
    'note.import.image',
    // 导出（范围预览 + 加密 + 用户确认）。
    'note.export.png',
    'note.export.pdf',
    'note.export.svg',
    'note.export.json',
    'note.export.rtf',
    // 删除（回收站——可恢复）。
    'note.delete',
    // 恢复（回收站恢复——误删可撤销）。
    'note.restore',
    // 保存（原子写入——崩溃可恢复）。
    'note.save',
  };

  /// 判定操作是否允许（白名单 + 审计——deny/allow 都记录）。
  PolicyResult check(String operation, {String? target}) {
    final allowed = allowlistedOperations.contains(operation);
    final reason = allowed ? 'allowlisted' : 'operation_not_allowlisted';
    AuditLogger.log(
      'policy.$operation',
      success: allowed,
      detail: target,
    );
    return PolicyResult(
      allowed ? PolicyDecision.allow : PolicyDecision.deny,
      reason,
    );
  }

  /// enforce 模式便捷判定：deny 时抛 [PolicyDeniedException]（调用方
  /// 捕获后拒绝执行——fail-closed）；monitor 模式仅审计不阻断。
  PolicyResult enforceCheck(String operation, {String? target}) {
    final result = check(operation, target: target);
    if (mode == PolicyMode.enforce && result.isAllowed == false) {
      throw PolicyDeniedException(operation, result.reason);
    }
    return result;
  }
}

/// 策略拒绝异常（enforce 模式 deny 时抛出——调用方捕获并拒绝执行）。
class PolicyDeniedException implements Exception {
  const PolicyDeniedException(this.operation, this.reason);

  final String operation;
  final String reason;

  @override
  String toString() => 'PolicyDeniedException($operation: $reason)';
}
