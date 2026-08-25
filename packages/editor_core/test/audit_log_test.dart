import 'package:test/test.dart';

import 'package:editor_core/editor_core.dart';

/// tamper-evident 借鉴——AuditLog 哈希链测试（纯逻辑——不搞崩）。
void main() {
  test('初始状态：空日志', () {
    const log = AuditLog();
    expect(log.count, 0);
    expect(log.lastHash, '0'); // 链头。
    expect(log.verify('secret'), true); // 空日志验证通过。
  });

  test('append：追加条目（哈希链）', () {
    const log = AuditLog();
    final withEntry = log.append(
      type: 'SAVE', actor: 'user1', data: 'doc1', secret: 'secret-key',
    );
    expect(withEntry.count, 1);
    expect(withEntry.lastHash, isNot('0')); // 哈希已生成。
    expect(withEntry.entries.first.prevHash, '0'); // 第一条 prevHash = '0'。
    expect(withEntry.verify('secret-key'), true); // 链完整。
  });

  test('append：多条条目（链式链接）', () {
    const log = AuditLog();
    var current = log;
    for (var i = 0; i < 3; i++) {
      current = current.append(
        type: 'OP$i', actor: 'user', data: 'data$i', secret: 'secret-key',
      );
    }
    expect(current.count, 3);
    // 每条 prevHash 指向前一条 hash。
    expect(current.entries[1].prevHash, current.entries[0].hash);
    expect(current.entries[2].prevHash, current.entries[1].hash);
    expect(current.verify('secret-key'), true);
  });

  test('verify：篡改检测（修改条目——链断裂）', () {
    var log = const AuditLog();
    log = log.append(type: 'A', actor: 'u', data: 'd1', secret: 'secret-key');
    log = log.append(type: 'B', actor: 'u', data: 'd2', secret: 'secret-key');

    // 篡改第一条 data。
    final tampered = AuditLog(entries: [
      AuditEntry(
        type: log.entries[0].type,
        timestamp: log.entries[0].timestamp,
        actor: log.entries[0].actor,
        data: 'TAMPERED', // 修改了。
        prevHash: log.entries[0].prevHash,
        hash: log.entries[0].hash, // 哈希未更新（攻击者无法重算）。
      ),
      ...log.entries.sublist(1),
    ]);
    expect(tampered.verify('secret-key'), false); // 篡改检测。
  });

  test('tamperedIndices：返回被篡改的条目索引', () {
    var log = const AuditLog();
    log = log.append(type: 'A', actor: 'u', data: 'd1', secret: 'secret-key');
    log = log.append(type: 'B', actor: 'u', data: 'd2', secret: 'secret-key');

    final tampered = AuditLog(entries: [
      AuditEntry(
        type: log.entries[0].type,
        timestamp: log.entries[0].timestamp,
        actor: log.entries[0].actor,
        data: 'MODIFIED',
        prevHash: log.entries[0].prevHash,
        hash: log.entries[0].hash,
      ),
      ...log.entries.sublist(1),
    ]);
    final indices = tampered.tamperedIndices('secret-key');
    expect(indices, isNotEmpty); // 至少第 0 条被篡改。
    expect(indices.first, 0);
  });

  test('replay：事件溯源重放', () {
    var log = const AuditLog();
    log = log.append(type: 'CREATE', actor: 'u', data: 'doc1', secret: 'k');
    log = log.append(type: 'EDIT', actor: 'u', data: 'doc2', secret: 'k');
    log = log.append(type: 'SAVE', actor: 'u', data: 'doc3', secret: 'k');
    final events = log.replay();
    expect(events, ['doc1', 'doc2', 'doc3']);
  });

  test('AuditEntry：相等性（按 hash）', () {
    final ts = DateTime(2026, 8, 22);
    final a = AuditEntry(
      type: 'A', timestamp: ts, actor: '', data: '', prevHash: '0', hash: 'abc',
    );
    final b = AuditEntry(
      type: 'B', timestamp: ts, actor: '', data: '', prevHash: '0', hash: 'abc',
    );
    expect(a, b); // 按 hash 相等。
  });
}
