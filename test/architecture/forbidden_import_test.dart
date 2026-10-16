// 专家 I-006（2026-08-16——批次 A）：V2 架构边界测试——
// editor_core / notebook_domain 纯 Dart（R-02：无 Flutter/dart:io——禁依赖）
// + V2 绝不 import legacy（R-02）。
//
// ── 第四轮审计 TE-TST-04 / R11（2026-10-16）：四条判据全是「循环体不执行就是绿」 ──
// 每条的形状都是 `for (final f in _dartFiles(dir)) { for (final line in _importsOf(f)) { expect } }`。
// 让那两个循环都不执行有两条路，**两条都绿**：目录空 ⇒ 文件表空；抽取器认不出某种写法 ⇒ 行表空。
// 后一条尤其真实：`_importsOf` 原来只认 `import '` / `export '`（单引号紧跟一个空格），
// 而 `import "dart:io";` 与 `import\t'dart:io';` 都是合法 Dart；`dart:io` 那一格判据本身也是
// `line.contains("import 'dart:io'")` **字面量比对** ⇒ 换一种引号就整体绕过这两条 R-02 规则。
// 实测两个根今天的 import/export 语句**一共只有 4 行**（5 个 .dart 文件），全是单引号写法
// ⇒ 放宽抽取与判据口径不会新增任何违规；放宽之后再由 canary 钉住「双引号也要抽到、也要拦」。
//
// ⚠ 顺带记一条如实的观察：这两个包的裁决面本来就极薄（5 个文件、4 行 import），
// 所以下面的文件数/行数下限只能取「非零但很松」的值（3 / 2 / ≥3 行）——它抓得住
// 「扫描塌成空集」这一类致命塌法，抓不住「少读了一个文件」这种小漂移。
// 换句话说：这四条 R-02 判据目前守的是一个还很小的面。别把它当成 V2 的边界已经稳固。
//
// ⚠ 与 `test/architecture/v2_dependency_boundaries_test.dart` **覆盖同一组规则**（同两个包、
// 同「纯 Dart / 不 import legacy」两条线），这是审计 §4 第 2 条「一份判据 N 份副本」在本仓的
// 一处实证。本批**只做自证加固，没有合并两者**——合并属删改，需业主点头。两份各钉各的，
// 至少不再各自静默；哪一份该留下、该并成一份，请随 §5 的等价重构一起裁决。
//
// 突变自证（实测计数写进 commit message）：
//   P-1 `_importStmtRe` 退回只认单引号 ⇒ `抽取与判据自证` 红（双引号那行抽不到），
//       而四条真实判据与 `分母下限` **全绿**（今天语料里没有双引号写法 ⇒ 这个洞完全不可见）；
//   P-2 `dart:io` 判据退回 `line.contains("import 'dart:io'")` 字面量比对 ⇒ 同一格红；
//   P-3 `_dartFiles` 恒空 ⇒ 四条真实判据**照样绿**，只有 `分母下限` 红 ⇒ 与 R10 的 M-V1 同格。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// import/export 语句行：行首锚定（注释与字符串里的同形文本不算），两种引号、任意空白都认。
final RegExp _importStmtRe = RegExp('''^\\s*(?:import|export)\\s+["']''');

/// `dart:io` 的引入写法（单双引号都认）。原来这里是一处
/// `line.contains("import 'dart:io'")` 字面量比对，双引号写法直接绕过。
final RegExp _dartIoRe = RegExp('''import\\s+["']dart:io["']''');


const List<String> _packageRoots = [
  'packages/editor_core/lib',
  'packages/notebook_domain/lib',
];

void main() {
  final editorCore = _dartFiles(_packageRoots[0]);
  final notebookDomain = _dartFiles(_packageRoots[1]);

  test('editor_core 纯 Dart：无 Flutter 依赖（R-02）', () {
    for (final f in editorCore) {
      for (final line in _importsOf(f)) {
        expect(line.contains('package:flutter'), isFalse, reason: '$f: $line');
      }
    }
  });

  test('editor_core 纯 Dart：无 dart:io（R-02）', () {
    for (final f in editorCore) {
      for (final line in _importsOf(f)) {
        expect(_dartIoRe.hasMatch(line), isFalse, reason: '$f: $line');
      }
    }
  });

  test('notebook_domain 纯 Dart：无 Flutter/dart:io（R-02）', () {
    for (final f in notebookDomain) {
      for (final line in _importsOf(f)) {
        expect(line.contains('package:flutter'), isFalse, reason: '$f: $line');
        expect(_dartIoRe.hasMatch(line), isFalse, reason: '$f: $line');
      }
    }
  });

  test('V2 绝不 import legacy（R-02——无 legacy 依赖）', () {
    for (final f in [...editorCore, ...notebookDomain]) {
      for (final line in _importsOf(f)) {
        expect(line.contains('legacy'), isFalse, reason: '$f: $line');
      }
    }
  });

  test('分母下限：读到的文件数与认出的 import 行数塌掉 ⇒ 红（TE-TST-04）', () {
    // 实测基线 2026-10-16：editor_core 3 个 .dart、notebook_domain 2 个，
    // 两包合计认出 **4** 行 import/export（面本来就这么小，见文件头那条如实观察）。
    // 下限只用于抓塌空，留正常增删的余量。
    expect(
      editorCore.length,
      greaterThanOrEqualTo(3),
      reason:
          'editor_core 只读到 ${editorCore.length} 个 .dart（基线 3）⇒ 前两条判据的循环面空了，'
          '`expect(isFalse)` 一次都不执行也照样绿。',
    );
    expect(
      notebookDomain.length,
      greaterThanOrEqualTo(2),
      reason: 'notebook_domain 只读到 ${notebookDomain.length} 个 .dart（基线 2）',
    );
    final stmtLines = [...editorCore, ...notebookDomain].fold<int>(
      0,
      (sum, f) => sum + _importsOf(f).length,
    );
    expect(
      stmtLines,
      greaterThanOrEqualTo(3),
      reason:
          '读了 ${editorCore.length + notebookDomain.length} 个文件却只认出 $stmtLines 行 '
          'import/export（基线 4）⇒ 抽取口径坏了，四条判据同时失明（见文件头）。',
    );
  });

  test('抽取与判据自证：两种引号都要抽到，注释行不算，换引号的违规也必须拦', () {
    // 抽取面（突变 P-1 的落点）。
    expect(
      _extract('import "dart:io";'),
      hasLength(1),
      reason: '双引号是合法 Dart 写法；抽不到就等于这条 R-02 判据对整类写法不存在',
    );
    expect(_extract("import\t'package:flutter/material.dart';"), hasLength(1));
    expect(_extract("export 'legacy/x.dart';"), hasLength(1));
    expect(_extract("// import 'dart:io';"), isEmpty, reason: '注释行不算语句');
    expect(_extract('final s = 1;'), isEmpty);

    // `dart:io` 那一格判据（突变 P-2 的落点：字面量比对会被换引号绕过）。
    expect(_dartIoRe.hasMatch("import 'dart:io';"), isTrue);
    expect(
      _dartIoRe.hasMatch('import "dart:io";'),
      isTrue,
      reason: '同一句违规只是换了引号——判据不许因为写法变化而漏',
    );
    expect(
      _dartIoRe.hasMatch("import 'dart:async';"),
      isFalse,
      reason: '反向锁：判据不是恒 true，否则这条门禁就成了「一律报警」',
    );
  });
}

/// 递归收集目录下全部 .dart 文件。目录不存在时 `listSync` 抛错 ⇒ 用例红（fail-closed，
/// 与 `v2_dependency_boundaries_test` 里那个「返回空表」的版本不同——那一版靠台账用例兜住）。
List<String> _dartFiles(String dir) {
  final result = <String>[];
  for (final e in Directory(dir).listSync(recursive: true)) {
    if (e is File && e.path.endsWith('.dart')) result.add(e.path);
  }
  return result;
}

/// 提取 import/export 语句（行首锚定——排除注释与字符串；两种引号都认）。
List<String> _importsOf(String file) => _extract(File(file).readAsLinesSync());

/// 从行集合（或单行文本）里认出 import/export 语句行——真实扫描与 canary 共用这一份实现。
List<String> _extract(Object linesOrText) {
  final lines = linesOrText is List<String>
      ? linesOrText
      : (linesOrText as String).split('\n');
  return [for (final l in lines) if (_importStmtRe.hasMatch(l)) l];
}
