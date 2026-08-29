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
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 把任意路径规范化成 `lib/...` 的相对路径。
String toRel(String p) {
  final fwd = p.replaceAll('\\', '/');
  final idx = fwd.indexOf('lib/');
  return idx >= 0 ? fwd.substring(idx) : fwd;
}

/// 取某文件内所有 `package:drawing_notes_app/...` 的 import 目标。
Set<String> projectImports(String path) {
  final src = File(path).readAsStringSync();
  final re = RegExp("import\\s+['\"](package:drawing_notes_app/[^'\"]+)['\"]");
  return re.allMatches(src).map((m) => m.group(1)!).toSet();
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
    final violators = <String>[];
    for (final entry in importsByFile.entries) {
      if (!entry.key.startsWith('lib/shared/')) continue;
      for (final imp in entry.value) {
        if (imp.startsWith('package:drawing_notes_app/features/')) {
          violators.add('${entry.key} -> $imp');
        }
      }
    }
    expect(violators, isEmpty,
        reason: 'shared 是跨切面层，只能被 feature 依赖，不能反向依赖 feature：\n${violators.join('\n')}');
  });

  test('规则B：core 只允许共享 feature 的 domain 实体', () {
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
    expect(violators, isEmpty,
        reason: 'core 只允许共享 feature 的 domain 实体（文档化双向共享），不得依赖 feature 的 application/infrastructure/presentation：\n${violators.join('\n')}');
  });

}
