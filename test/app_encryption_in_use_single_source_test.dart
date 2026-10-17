// 组合根「加密是否在用」只允许有一处定义（审计 2026-10-16，STO-001 连带）。
//
// 形状：`app.dart` 把 `vaultConfigured` 注进三条写腿（画布 StorageService、
// 笔记本媒体 NotebookStorage、块文档 NoteBlockStore）。改之前那是**三行逐字相同的
// 闭包** `() => _vaultKeyService.isConfigured()`——本仓头号复发形态「一份判据 N 份
// 副本」的正例：R28 让「拒绝补建」成为一种稳态之后，主文件可以缺席而盘上仍有
// `.bak` 信封，此时三行都必须同时改口径，漏任何一行就是**静默把密文降级成明文**
// （AW8 那条 P0 的反方向）。
//
// 所以这里钉的不是业务行为（行为由 AW8 的 store 用例钉），而是**装配面只有一处**：
// ① 三处注入全部指向同一个私有判据；② 该判据同时看主文件与孤儿 `.bak`；
// ③ 分母先于结论（找不到三处注入就直接红，不许「零违规」式绿）。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('lib/app.dart').readAsStringSync();
  final lines = source.split(RegExp(r'\r?\n'));

  /// 形如 `vaultConfigured: <表达式>` 的注入行（不含声明与注释）。
  List<String> injectionLines() => lines
      .map((l) => l.trim())
      .where((l) => l.startsWith('vaultConfigured:'))
      .toList();

  test('分母：三条写腿各注入一次，少一条说明这条门禁已经看不见现场', () {
    final found = injectionLines();
    expect(
      found.length,
      3,
      reason: '画布 / 笔记本媒体 / 块文档三条写腿都必须拿到口径；'
          '数量掉到 0 或 1 通常是本文件被改名，而不是判据被收敛',
    );
    expect(source.contains('class _DrawingNotesAppState'), isTrue);
  });

  test('三处注入指向同一个私有判据，不许再出现就地复制的第二份', () {
    for (final line in injectionLines()) {
      expect(
        line,
        'vaultConfigured: _encryptionInUse,',
        reason: '判据复制第二遍的地方就是降级发生的地方：$line',
      );
    }
    // 反向锁：文件里不该再有「直接拿 isConfigured 当 vaultConfigured」的旧形状。
    expect(
      source.contains('vaultConfigured: () => _vaultKeyService.isConfigured()'),
      isFalse,
    );
  });

  test('判据本体：主文件与孤儿 `.bak` 两半都在，且全文件只定义一次', () {
    final definitions = lines
        .map((l) => l.trim())
        .where((l) => l.startsWith('Future<bool> _encryptionInUse()'))
        .toList();
    expect(definitions, hasLength(1), reason: '判据本身也只许一份');

    final body = source.substring(source.indexOf('Future<bool> _encryptionInUse()'));
    final until = body.indexOf(';');
    final expression = body.substring(0, until);
    expect(
      expression,
      contains('isConfigured()'),
      reason: '常规稳态仍由主文件判据决定',
    );
    expect(
      expression,
      contains('hasOrphanBackupOnDisk()'),
      reason: '拒绝补建后的稳态：主文件不在但盘上仍有信封 ⇒ 必须算「已建库」，'
          '否则写路径会把加密世代降级成明文',
    );
  });
}
