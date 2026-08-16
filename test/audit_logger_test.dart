import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/security/audit_logger.dart';

/// 红蓝攻防 P2 修复（2026-08-15）：安全审计日志——记录密钥加载/密码盘
/// 操作（时间戳+操作+结果），仅本地内存、绝不含密钥与内容。
void main() {
  setUp(AuditLogger.clear);

  test('审计日志：记录操作/时间/结果', () {
    AuditLogger.log('password_disk.unlock');
    AuditLogger.log('password_disk.read_key', success: false);
    final snap = AuditLogger.snapshot();
    expect(snap.length, 2);
    expect(snap[0], contains('password_disk.unlock'));
    expect(snap[0], contains('OK'));
    expect(snap[1], contains('FAIL'));
    expect(snap[0], startsWith('['), reason: '时间戳前缀');
  });

  test('审计日志：clear 清空（测试隔离）', () {
    AuditLogger.log('x');
    expect(AuditLogger.snapshot(), hasLength(1));
    AuditLogger.clear();
    expect(AuditLogger.snapshot(), isEmpty);
  });

  test('哈希链：日志链完整——verifyIntegrity 通过', () {
    AuditLogger.clear();
    AuditLogger.log('policy.note.import.pdf');
    AuditLogger.log('password_disk.read_key', success: false);
    AuditLogger.log('media.encrypt', detail: 'note-a');
    expect(AuditLogger.verifyIntegrity(), isTrue);
    expect(AuditLogger.snapshot(), hasLength(3));
  });

  test('哈希链：clear 重置后链重新开始', () {
    AuditLogger.log('x');
    AuditLogger.clear();
    expect(AuditLogger.verifyIntegrity(), isTrue, reason: '空链验证通过');
    AuditLogger.log('y');
    expect(AuditLogger.verifyIntegrity(), isTrue);
  });

  test('哈希链：连续日志哈希推进（链完整）', () {
    AuditLogger.clear();
    AuditLogger.log('a');
    AuditLogger.log('b');
    expect(AuditLogger.snapshot(), hasLength(2));
    expect(AuditLogger.verifyIntegrity(), isTrue);
  });
}
