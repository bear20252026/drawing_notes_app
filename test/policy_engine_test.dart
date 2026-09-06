import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/security/audit_logger.dart';
import 'package:drawing_notes_app/core/security/policy_engine.dart';

/// 策略执行引擎单测（专家审计最优先④——2026-08-16）：
/// 操作白名单默认拒绝 + enforce 模式抛异常 + 审计完整性。
void main() {
  setUp(AuditLogger.clear);

  test('默认拒绝：白名单操作允许，未列入操作拒绝', () {
    const engine = PolicyEngine();
    expect(engine.check('note.import.pdf').isAllowed, isTrue);
    expect(engine.check('note.save').isAllowed, isTrue);
    expect(engine.check('note.delete').isAllowed, isTrue);
    // 未列入操作——默认拒绝。
    expect(engine.check('note.export.unknown').isAllowed, isFalse);
    expect(engine.check('system.exec').isAllowed, isFalse);
    expect(engine.check('ai.write_memory').isAllowed, isFalse);
  });

  test('enforce 模式：deny 抛 PolicyDeniedException（fail-closed）', () {
    const engine = PolicyEngine();
    expect(
      () => engine.enforceCheck('system.exec'),
      throwsA(isA<PolicyDeniedException>()),
    );
    // 白名单操作不抛。
    expect(engine.enforceCheck('note.save').isAllowed, isTrue);
  });

  test('monitor 模式：deny 仅审计不阻断（策略调优期）', () {
    const engine = PolicyEngine(mode: PolicyMode.monitor);
    final result = engine.enforceCheck('system.exec');
    expect(result.isAllowed, isFalse);
  });

  test('审计完整性：deny/allow 都写入审计日志', () {
    const engine = PolicyEngine();
    engine.check('note.import.pdf');
    engine.check('system.exec');
    final snap = AuditLogger.snapshot();
    expect(
      snap.any((e) => e.contains('policy.note.import.pdf') && e.contains('OK')),
      isTrue,
    );
    expect(
      snap.any((e) => e.contains('policy.system.exec') && e.contains('FAIL')),
      isTrue,
    );
  });
}
