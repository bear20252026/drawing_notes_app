// 门禁：吃了真 KDF 却没交代清楚走哪条腿的测试文件（R36，第四轮台账 §24）。
//
// 起因不是「偶发慢」：CI run 39029634857 里 `home_refresh_fix_test` 的
// `encryptAndSave` 那条腿在满并发的 Windows runner 上撞了 30 秒默认超时。本仓
// `--exclude-tags kdf`（串行分片）与主套件的划分**全靠每个文件自己声明**，
// 于是任何一个没声明的文件都能把生产 Argon2id（64MiB t2 p2）混进并行主套件——
// 而这条划分本身没有任何机器校验。按 R8~R14 的口径，这就是「空集即通过」那一族
// 的新成员：判据存在，但没人保证它被执行。
//
// 判据（两条都承认，因为它们是两个不同的目的）：
//  · `KdfParams.testLight` —— 批B 口径：槽位/信封格式与生产一致，只换工作因子。
//    适合「我验的是回调响没响 / 内容丢没丢」这类与密钥成本无关的命题。
//  · `@Tags(['kdf'])`      —— 命题本身就要测生产成本或真实信封，进串行分片跑。
// 两者都没有 ⇒ 红。
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 触发词在运行期拼出来：本文件自己的注释与判据里都要提到这些词，
/// 写成字面量会把门禁自己判成违规。扫描型门禁的自指问题宁可这样解决，
/// 也不要「按文件名排除自己」那种特判（它很快会变成第二个漏洞）。
///
/// 2026-11-20 扩展（#87 同类漏网）：原先只有 `encryptAndSave` 一条腿，
/// 覆盖不到 `encryptWithPasswordV3` / `encryptWithPasswordV5` /
/// `unlockWithPasswordV3` / `rewrapPasswordSlotV3` 等入口——vault_file_password
/// 正是这么把生产 Argon2id 混进主套件的。触发词一律取「会执行 KDF 派生的
/// 方法名 + 左括号」，不取类名（用了类不一定派生）。
final List<String> _kdfTriggers = [
  ['encryptAndSave', '('].join(),
  ['encryptWithPasswordV3', '('].join(),
  ['encryptWithPasswordV5', '('].join(),
  ['unlockWithPasswordV3', '('].join(),
  ['rewrapPasswordSlotV3', '('].join(),
];

final List<String> _cheapMarks = const [
  'KdfParams.testLight',
  "@Tags(['kdf'])",
  '@Tags(["kdf"])', // L-6（第二轮审计）：双引号标签同口径（6 文件在用）
];

/// 涉真 KDF 但两条腿都没交代 ⇒ 返回该文件；合规返回 null。
String? findUndeclaredKdfUsage(String path, String source) {
  String? hit;
  for (final t in _kdfTriggers) {
    if (source.contains(t)) {
      hit = t;
      break;
    }
  }
  if (hit == null) return null;
  final declared = _cheapMarks.any((mark) => source.contains(mark));
  if (declared) return null;
  return '$path 调了 $hit，但既没注入 ${_cheapMarks[0]}、也没声明 '
      '${_cheapMarks[1]}：它会吃生产 KDF，把主套件的默认超时赌上';
}

void main() {
  List<File> allTestDart() =>
      Directory('test')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();

  test('分母下限：扫描面与认出的涉密文件数都不许塌掉（TE-TST-04 同族）', () {
    final files = allTestDart();
    expect(
      files.length,
      greaterThanOrEqualTo(300),
      reason:
          'test/ 下真实有三百多个 dart 文件；读出个位数说明扫描根错了，'
          '那时下面那条判据会「空集通过」——这正是要防的失效形状',
    );
    final hits = files
        .where(
          (f) => _kdfTriggers.any(
            (t) => f.readAsStringSync().contains(t),
          ),
        )
        .toList();
    expect(
      hits.length,
      greaterThanOrEqualTo(18),
      reason: '今天实测 18 个文件调真 KDF 入口；认出 0 个说明触发词抽取失效',
    );
  });

  test('判据：涉 KDF 的测试文件必须交代它走哪条腿', () {
    final violations = <String>[];
    for (final f in allTestDart()) {
      final v = findUndeclaredKdfUsage(f.path, f.readAsStringSync());
      if (v != null) violations.add(v);
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('判据自证：每种触发词 × 四种形状各判对，别让门禁自己空转', () {
    // ① 该报的：调了但什么都没写（逐触发词，防「只判了第一条腿」）。
    for (final t in _kdfTriggers) {
      expect(
        findUndeclaredKdfUsage(
          'a_test.dart',
          '  void x() => ${t}nb, p);',
        ),
        isNotNull,
        reason: t,
      );
    }
    // ② 注入轻量参数的：不报。
    expect(
      findUndeclaredKdfUsage(
        'b_test.dart',
        'KdfParams.newSlotDefault = KdfParams.testLight;\n'
            '  void x() => ${_kdfTriggers.first}nb, p);',
      ),
      isNull,
    );
    // ③ 声明进 kdf 串行分片的：不报。
    expect(
      findUndeclaredKdfUsage(
        'c_test.dart',
        "@Tags(['kdf'])\nlibrary;\n"
            '  void x() => ${_kdfTriggers.first}nb, p);',
      ),
      isNull,
    );
    // ④ 根本没碰密钥的：不报（不许把无关文件拖进来）。
    expect(
      findUndeclaredKdfUsage('d_test.dart', '  void x() => save(nb);'),
      isNull,
    );
  });
}
