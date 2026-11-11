// M4 架构门禁（2026-11）：测试专用弱 KDF 开关（KekSessionCache.bypassIsolateForTests）
// 的**写点**只允许出现在 test/**；生产代码（lib/）只允许读取该开关。
//
// 背景：`bypassIsolateForTests` 可把 Argon2id/PBKDF2 降级为 500 轮 SHA-256 链
// （`_testOnlyKdf`），该开关编译进 release 包，仅靠 `@visibleForTesting` 约定
// 保护——任何生产代码写 `= true` 都会把用户密钥派生降级为可 GPU 爆破的快哈希。
// 本门禁把「写点只在测试」钉成机器事实：新增生产写点即红。
//
// 判据（两条）：
//   ① `lib/**` 内不得出现 `bypassIsolateForTests = true|false` 赋值（只读可以）。
//   ② `_testOnlyKdf` 的调用点必须位于定义它的生产文件内（kek_session_cache.dart），
//      即「唯一调用点在本文件」这条既有注释成为机器事实；新增外部调用即红。
//
// 分母与反向锁见文件末用例（防空集即绿 / 防正则失明）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 生产代码赋值形状：`bypassIsolateForTests = <非 `=` 的值>`（读判据）。
///
/// 用否定前瞻排除 `==`（比较）与 `=>`（箭头）——本开关是 bool 字段，
/// 合法读取如 `if (bypassIsolateForTests)` 与 `bypassIsolateForTests == x`
/// 都不该被误判成写点。
final RegExp _bypassWriteRe = RegExp(
  r'\bbypassIsolateForTests\s*=(?!=|>)\s*',
);

/// `_testOnlyKdf` 调用形状（生产调用点审计）。
final RegExp _testOnlyKdfCallRe = RegExp(r'\b_testOnlyKdf\s*\(');

/// 生产文件里定义 `_testOnlyKdf` 的唯一合法文件。
const String _testOnlyKdfHome = 'lib/core/security/kek_session_cache.dart';

void main() {
  test('M4-①：lib/** 不得写 bypassIsolateForTests（只读合法）', () {
    final offenders = <String>[];
    var scannedFiles = 0;
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      scannedFiles++;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        // 跳过纯注释行（// 开头）——注释里写「bypassIsolateForTests = true」
        // 是既有裁决注释的常见形状，不算写点。
        if (line.trimLeft().startsWith('//')) continue;
        // 跳过字段声明（`static bool bypassIsolateForTests = false;`）——
        // 那是定义，不是运行时写点。
        if (line.contains('static bool bypassIsolateForTests')) continue;
        if (_bypassWriteRe.hasMatch(line)) {
          offenders.add('${entity.path}:${i + 1}: $line');
        }
      }
    }

    expect(
      scannedFiles,
      greaterThanOrEqualTo(50),
      reason: 'lib/** 只扫到 $scannedFiles 个 .dart（实测 ≫50）⇒ 扫描口径坏了'
          '（目录名/后缀/递归），此时「零命中」是失明而非合规。',
    );
    expect(
      offenders,
      isEmpty,
      reason: 'M4-① 生产代码写 bypassIsolateForTests（会把 Argon2id/PBKDF2\n'
          '降级为 500 轮 SHA-256 链，release 包可被 GPU 爆破）：\n'
          '${offenders.join('\n')}\n'
          '该开关的写点只允许出现在 test/**（setUp/tearDown）。',
    );
  });

  test('M4-②：_testOnlyKdf 只允许在其定义文件内被调用', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      // 归一化成 posix 再比：Windows 上 entity.path 是 `lib\\core\\...`，
      // 与正斜杠常量 _testOnlyKdfHome 直接 == 会失配，把定义文件**自己**的
      // 调用误判成「定义文件之外的调用」（2026-11-11 CI `e6509815` 实测踩中，
      // macOS/Linux 不复现）。口径同 `architecture_boundary_ratchet_test.dart`。
      if (entity.path.replaceAll('\\', '/') == _testOnlyKdfHome) {
        continue; // 定义文件内的调用合法
      }
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (_testOnlyKdfCallRe.hasMatch(lines[i])) {
          offenders.add(
            '${entity.path.replaceAll('\\', '/')}:${i + 1}: ${lines[i]}',
          );
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'M4-② _testOnlyKdf 被定义文件之外的代码调用：\n'
          '${offenders.join('\n')}\n'
          '测试专用弱 KDF 不得被生产路径触达；唯一调用点必须在 '
          '$_testOnlyKdfHome 内且由 bypassIsolateForTests 门控。',
    );
  });

  test('M4-③：生产开关存在且默认 false（release 不降级）', () {
    final home = File(_testOnlyKdfHome);
    expect(home.existsSync(), isTrue, reason: '$_testOnlyKdfHome 不见了');
    final code = home.readAsStringSync();
    expect(
      RegExp(r'static bool bypassIsolateForTests = false').hasMatch(code),
      isTrue,
      reason: 'bypassIsolateForTests 默认值必须是 false（release 恒走真 KDF）。',
    );
    expect(
      _testOnlyKdfCallRe.hasMatch(code),
      isTrue,
      reason: '_testOnlyKdf 必须存在于定义文件（否则门禁 ② 失去参照）。',
    );
  });

  test('M4-④：反向锁——判定链路能抓到生产写点与外部调用', () {
    expect(
      _bypassWriteRe.hasMatch('  KekSessionCache.bypassIsolateForTests = true;'),
      isTrue,
      reason: '生产写点样本必须被拦',
    );
    expect(
      _bypassWriteRe.hasMatch('  if (bypassIsolateForTests) {'),
      isFalse,
      reason: '纯读取（if 判空）不许误拦',
    );
    expect(
      _bypassWriteRe.hasMatch('  expect(bypassIsolateForTests == true, isTrue);'),
      isFalse,
      reason: '比较（==）不许误拦成写点',
    );
    expect(
      _bypassWriteRe.hasMatch('  final f = () => bypassIsolateForTests;'),
      isFalse,
      reason: '箭头读取（=>）不许误拦成写点',
    );
    expect(
      _testOnlyKdfCallRe.hasMatch('  final k = _testOnlyKdf(p, s, params);'),
      isTrue,
      reason: '外部调用样本必须被拦',
    );
  });

  test('M4-⑤：test/** 里确有写点（证明判据① 的分母不是空集）', () {
    var writePoints = 0;
    for (final entity in Directory('test').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      for (final line in entity.readAsLinesSync()) {
        if (line.trimLeft().startsWith('//')) continue;
        if (_bypassWriteRe.hasMatch(line)) writePoints++;
      }
    }
    expect(
      writePoints,
      greaterThanOrEqualTo(5),
      reason: 'test/** 只找到 $writePoints 处 bypassIsolateForTests 写点'
          '（实测 10+ 文件 setUp/tearDown）⇒ 抽取口径坏了，或测试侧清理过度。',
    );
  });
}
