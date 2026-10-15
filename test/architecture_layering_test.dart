// 层信赖方向守卫（2026-08-29 新增，lead 收口）。
//
// 目的：把「层级分明 / 耦合方向」用纯 Dart 扫描 import 图强制落地，防止未来漂移。
// 与 test/architecture_test.dart（dart_arch_test 九条规则）互补：
//   - 那九条锁定 feature 内部 presentation→application→infrastructure→domain、
//     无环、跨 feature 禁依赖、洋葱、Martin 基线；
//   - 本文件额外锁定 **core/shared 这一共享层与 feature 的方向**：
//     A) shared 是跨切面层，只能被 feature 依赖，绝不能反向 import features；
//     B) core 只允许共享 feature 的 domain 实体（文档化「实体双向共享」），
//        不得依赖 feature 的 application/infrastructure/presentation。
//
// 实现：扫描 lib/ 下每个 .dart 的 `import 'package:drawing_notes_app/...'`，
// 按进出两个命名空间检查方向。不依赖任何第三方 arch 工具，直观可审计。
//
// ── 第四轮审计 TE-TST-04 / TE-TST-05（2026-10-15）：本文件原本是「空集即通过」的形状 ──
// 两条规则都只断言 `expect(violators, isEmpty)`，而让 `violators` 恒空的坏法有好几种，
// 且**每一种都绿**：扫描根目录换了 / 后缀判定坏了 ⇒ `files` 为空；import 正则塌空
// （包名改名、引号写法变化）⇒ 每个文件的 import 集合为空；`lib/shared/` 或 `lib/core/`
// 被整体挪走 ⇒ 对应那条规则的循环面为空。这条门禁守的是全仓的层级法，一旦失明，
// 「shared 反向依赖 feature」这种漂移会悄无声息地合进来。
//
// 修法与同仓 `focus_ring_coverage_test`（V-12）同口径，两件事都要做：
//   ① **分母下限先于结论**（`门禁自证` 那条）：总文件数、**每条规则各自的**循环面、
//      以及「至少抽出一条项目内 import」的文件数各钉下限；塌了直接报「门禁失明」，
//      绝不让「零命中」被读成「零违规」。
//   ② **判据反向锁**（`判据自证` 那条）：把两条判据抽成纯函数，喂一份**人造违规 import
//      图**必须报出来，喂一份合规图必须零违规。只钉①不够——①只证明「扫到了东西」，
//      ②才证明「该报的时候真的报」。
//
// 突变自证（本门禁自身的有效性，实测计数写在 commit message 里）：
//   L1 把规则 A 的 `startsWith('package:drawing_notes_app/features/')` 改成恒 false
//      ⇒ `判据自证` 红（人造图不再报），而真实库那两条规则**照样绿** ⇒ 正是「恒绿门禁」的形状。
//   L2 把 import 正则改成什么都匹配不到
//      ⇒ `门禁自证` 红（有 import 的文件数塌到 0），而不是变成「零违规」的绿。
//   L3 把规则 B 的 `!imp.contains('/domain/')` 去掉
//      ⇒ `判据自证` 的合规图那半边红（合法的 domain 共享被误报）⇒ 反向锁不是「一律报警」。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 把任意路径规范化成 `lib/...` 的相对路径。
String toRel(String p) {
  final fwd = p.replaceAll('\\', '/');
  final idx = fwd.indexOf('lib/');
  return idx >= 0 ? fwd.substring(idx) : fwd;
}

/// 从一段源码里抽出所有 `package:drawing_notes_app/...` 的 import 目标。
///
/// 与 V-12 不同，这里**不做注释遮蔽**：注释里的 `import` 不生效，本判据宁可放过
/// 注释字样（实测没有造成过假红），也不另养一份词法状态机——真要遮蔽就该与
/// `test/helpers/dart_lexical_mask.dart` 共用同一份实现，那是另一件事。
Set<String> projectImportsFromSource(String src) {
  final re = RegExp("import\\s+['\"](package:drawing_notes_app/[^'\"]+)['\"]");
  return re.allMatches(src).map((m) => m.group(1)!).toSet();
}

/// 取某文件内所有 `package:drawing_notes_app/...` 的 import 目标。
Set<String> projectImports(String path) =>
    projectImportsFromSource(File(path).readAsStringSync());

/// 规则 A 的判据：shared 层反向依赖 feature。
///
/// 抽成纯函数是为了**能红**：真实库这张图必须是零违规（合规），而 `test/` 里造的
/// 那张违规图必须被报出来（见 `判据自证`）。
List<String> ruleAViolators(Map<String, Set<String>> importsByFile) {
  final violators = <String>[];
  for (final entry in importsByFile.entries) {
    if (!entry.key.startsWith('lib/shared/')) continue;
    for (final imp in entry.value) {
      if (imp.startsWith('package:drawing_notes_app/features/')) {
        violators.add('${entry.key} -> $imp');
      }
    }
  }
  return violators;
}

/// 规则 B 的判据：core 依赖 feature 的非 domain 层。
List<String> ruleBViolators(Map<String, Set<String>> importsByFile) {
  final violators = <String>[];
  for (final entry in importsByFile.entries) {
    if (!entry.key.startsWith('lib/core/')) continue;
    for (final imp in entry.value) {
      if (imp.startsWith('package:drawing_notes_app/features/') &&
          !imp.contains('/domain/')) {
        violators.add('${entry.key} -> $imp');
      }
    }
  }
  return violators;
}

void main() {
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .map((f) => f.path)
      .where((p) => p.endsWith('.dart'))
      .toList();

  // 读取为字符串，按需解析。
  final importsByFile = <String, Set<String>>{
    for (final f in files) toRel(f): projectImports(f),
  };

  test('规则A：shared 层不得依赖任何 feature 层（feature→shared→core 单向）', () {
    final violators = ruleAViolators(importsByFile);
    expect(
      violators,
      isEmpty,
      reason:
          'shared 是跨切面层，只能被 feature 依赖，不能反向依赖 feature：\n${violators.join('\n')}',
    );
  });

  test('规则B：core 只允许共享 feature 的 domain 实体', () {
    final violators = ruleBViolators(importsByFile);
    expect(
      violators,
      isEmpty,
      reason:
          'core 只允许共享 feature 的 domain 实体（文档化双向共享），不得依赖 feature 的 application/infrastructure/presentation：\n${violators.join('\n')}',
    );
  });

  test('门禁自证：扫描面塌掉 ⇒ 红，不是「零违规」那种绿（TE-TST-04）', () {
    // 下限都按 2026-10-15 实测（总 354 / shared 21 / core 112 / 有 import 211）
    // 放宽一档：只有门禁失明才会跌破，正常删几个文件不会。
    expect(
      files.length,
      greaterThanOrEqualTo(300),
      reason:
          '只扫到 ${files.length} 个 .dart 文件（实测基线 354）。扫描根目录或后缀判定'
          '出问题的时候，两条规则的循环面是空的，`isEmpty` 断言毫无裁决力——'
          '必须修扫描口径，绝不能靠放宽下限变绿。',
    );
    final sharedFiles = importsByFile.keys
        .where((k) => k.startsWith('lib/shared/'))
        .length;
    final coreFiles = importsByFile.keys
        .where((k) => k.startsWith('lib/core/'))
        .length;
    // 分母要落到**每条规则各自的**循环面上：只钉总数等于没钉——
    // `lib/shared/` 整体被挪走时总数仍然够，规则 A 却再也不看任何文件。
    expect(
      sharedFiles,
      greaterThanOrEqualTo(15),
      reason: '规则 A 的循环面只剩 $sharedFiles 个文件（实测基线 21）⇒ 该规则已失明',
    );
    expect(
      coreFiles,
      greaterThanOrEqualTo(80),
      reason: '规则 B 的循环面只剩 $coreFiles 个文件（实测基线 112）⇒ 该规则已失明',
    );
    final withImports = importsByFile.values
        .where((imports) => imports.isNotEmpty)
        .length;
    expect(
      withImports,
      greaterThanOrEqualTo(150),
      reason:
          '扫了 ${files.length} 个文件，却只有 $withImports 个抽出一条项目内 import'
          '（实测基线 211）⇒ import 正则塌空（包名改名或引号写法变化就是这个形状），'
          '此时两条规则的 `violators` 恒空（TE-TST-05）。',
    );
  });

  test('判据自证：人造违规图必须报，合规图必须不报（反向锁 ≠ 一律报警）', () {
    // 违规图：两条规则各命中一处，且各只该被**自己那条**报出来。
    const illegal = <String, Set<String>>{
      'lib/shared/widgets/glass_surface.dart': {
        'package:drawing_notes_app/features/notes/presentation/leak.dart',
      },
      'lib/core/storage/vault_file_codec.dart': {
        'package:drawing_notes_app/features/doc/application/leak.dart',
      },
    };
    expect(
      ruleAViolators(illegal),
      hasLength(1),
      reason: '突变 L1：把规则 A 的判据改成恒 false，这里就空了——'
          '而真实库那两条规则照样绿，正是「恒绿门禁」的形状',
    );
    expect(
      ruleBViolators(illegal),
      hasLength(1),
      reason: 'core 依赖 feature 的 application 层必须被规则 B 报出来',
    );
    // 交叉验证：规则 A 不该管 core 的事，规则 B 不该管 shared 的事。
    expect(
      ruleAViolators(illegal).single,
      contains('glass_surface'),
      reason: '规则 A 报的必须是 shared 那一条——两条判据别混成一份',
    );
    expect(ruleBViolators(illegal).single, contains('vault_file_codec'));

    // 合规图：feature→shared、core→feature 的 domain 实体，都是文档化允许的合法形状。
    const legal = <String, Set<String>>{
      'lib/shared/widgets/glass_surface.dart': {
        'package:drawing_notes_app/core/theme/app_design.dart',
      },
      'lib/core/documents/document.dart': {
        'package:drawing_notes_app/features/doc/domain/note_block.dart',
      },
      'lib/features/notes/presentation/home_page.dart': {
        'package:drawing_notes_app/shared/widgets/glass_surface.dart',
      },
    };
    expect(
      ruleAViolators(legal),
      isEmpty,
      reason: '突变 L3：判据若退化成「一律报警」，合法共享也会被拦，'
          '这条门禁就会天天红而被绕过',
    );
    expect(
      ruleBViolators(legal),
      isEmpty,
      reason: 'core → feature 的 domain 实体是规则 B 明文允许的双向共享',
    );
  });

  test('抽取自证：双引号与带 as 后缀的写法都要抽出（TE-TST-05 的另一半）', () {
    const src = '''
import 'dart:io';
import "package:drawing_notes_app/core/x.dart";
import 'package:drawing_notes_app/features/y/domain/y.dart' as y;
import 'package:other_package/thing.dart';
''';
    final found = projectImportsFromSource(src);
    expect(
      found,
      containsAll(<String>[
        'package:drawing_notes_app/core/x.dart',
        'package:drawing_notes_app/features/y/domain/y.dart',
      ]),
      reason: '双引号、带 `as` 后缀都在真实库里存在；漏抽一条就是判据少看一条边',
    );
    expect(
      found,
      isNot(contains('package:other_package/thing.dart')),
      reason: '别包的 import 不参与本仓层级判定',
    );
    expect(projectImportsFromSource(''), isEmpty);
  });
}
