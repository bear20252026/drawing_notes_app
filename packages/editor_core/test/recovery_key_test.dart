import 'package:test/test.dart';

import 'package:editor_core/editor_core.dart';

/// 用户需求——RecoveryKeyService 恢复密钥测试（纯逻辑——不搞崩）。
void main() {
  test('generate：生成恢复密钥（8 组 × 4 字符——可一键复制）', () {
    const service = RecoveryKeyService();
    final key = service.generate();
    expect(key.key.length, 32);
    expect(key.groups.length, 8);
    expect(key.groups.every((g) => g.length == 4), true);
    expect(key.formatted.split(' ').length, 8); // 空格分隔——可一键复制。
  });

  test('generate：随机性（两次生成不同）', () {
    const service = RecoveryKeyService();
    final k1 = service.generate();
    final k2 = service.generate();
    expect(k1.key, isNot(equals(k2.key)));
  });

  test('generate：排除易混淆字符（0/O/1/l/I）', () {
    const service = RecoveryKeyService();
    final key = service.generate();
    // 字符集不含 0/O/1/l/I。
    expect(key.key.contains('0'), false);
    expect(key.key.contains('O'), false);
    expect(key.key.contains('1'), false);
    expect(key.key.contains('l'), false);
    expect(key.key.contains('I'), false);
  });

  test('formatForCopy：一键复制文本（分组显示）', () {
    const service = RecoveryKeyService();
    final key = service.generate();
    final copy = service.formatForCopy(key);
    expect(copy, key.formatted);
    expect(copy.split(' ').length, 8);
  });

  test('validate：校验恢复密钥（大小写不敏感——去空格）', () {
    const service = RecoveryKeyService();
    final key = service.generate();
    // 正确输入（带空格——大写）。
    expect(service.validate(key.formatted.toUpperCase(), key), true);
    // 去掉空格。
    expect(service.validate(key.key, key), true);
    // 错误输入。
    expect(service.validate('wrong-input', key), false);
  });

  test('normalizeInput：规范化输入（去空格/统一小写）', () {
    const service = RecoveryKeyService();
    expect(service.normalizeInput('AB CD EF'), 'abcdef');
    expect(service.normalizeInput('A-B-C'), 'abc');
    expect(service.normalizeInput('  Hello  World  '), 'helloworld');
  });

  test('RecoveryKey：formatted/copyText + 相等性', () {
    const key = RecoveryKey(key: 'abcd', groups: ['abcd']);
    expect(key.formatted, 'abcd');
    expect(key.copyText, 'abcd');
    const other = RecoveryKey(key: 'abcd', groups: ['abcd']);
    expect(key, other);
  });
}
