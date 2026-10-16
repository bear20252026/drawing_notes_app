// 专家第一周更正期 V-004~V-006（2026-08-16）：V2 依赖方向边界测试——
// V-004 纯度 / V-005 V2 不 import Legacy / V-006 UI 不直接访问文件·密钥·具体存储。
// （专家 C-003 要求的 v2_dependency_boundaries_test——加入 pr-architecture。）
//
// ── 第四轮审计 TE-TST-04 / R10（2026-10-16）：这三条原本全是「空集即通过」 ──
// 三条的形状都是 `for (final f in files) { for (final line in _importsOf(f)) { expect(...) } }`
// ——**循环体一次都不执行就是绿**。而 `_dartFiles` 对不存在的目录返回 `const []`，
// 于是「扫描根没了」与「扫描根里没有违规」共用同一个空列表。实测到 2026-10-16：
//   · `lib/features/editor_v2` **根本不存在** ⇒ V-005 的第三条腿、V-006 的第二条腿恒空；
//   · V-004 有 `isNotEmpty` 兜了一下（那是三条里唯一有下限的地方），V-005/V-006 什么都没有。
// 另外 `_importsOf` 原来只认 `import '`（单引号紧跟一个空格），而
// `import "dart:io";` 与 `import\t'dart:io';` 都是合法 Dart——**一条双引号写法就能整体
// 绕过这三条门禁**。实测两个根今天共 70 行 import/export，全是单引号，所以把抽取口径
// 放宽到今天不会新增任何违规；放宽之后再由 canary 钉住「双引号也要抽到」。
//
// 补齐三件事（与 R8 层级门禁、R9 l10n 门禁同口径）：
//   ① 扫描根台账：每个根**存在与否**单独断言（不存在的根必须写明它不存在，并且说明
//      它哪天回来时该做什么），别让缺席静默成空集；
//   ② 分母下限：每个根的文件数与本测试认出的 import 行数各钉一档；
//   ③ 判据抽成三个 RegExp 常量 + `_importsOf`，再喂人造行做正反两控。
//
// 突变自证（实测计数写进 commit message）：
//   M-V1 `_dartFiles` 换成恒空             ⇒ 台账与下限两条红，而 V-004~V-006 三条**照样绿**；
//   M-V2 `_importsOf` 退回只认单引号       ⇒ `判据自证` 红（双引号那行抽不到）；
//   M-V3 V-005 的 legacy 正则去掉 `editor_page` ⇒ `判据自证` 红（那条形状不再被拦），
//          真实库仍绿（今天两个包里没有这种 import）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// V-004：`packages/editor_core`、`packages/notebook_domain` 不许出现的东西。
final RegExp _impureImportRe = RegExp(
  r'package:flutter|dart:io|dart:ui|file_selector|path_provider|shared_preferences',
);

/// V-005：V2 不许 import 的 Legacy 形状。
final RegExp _legacyImportRe = RegExp(
  'features/drawing|features/notes|drawing_controller|editor_page|legacy/',
);

/// V-006：UI（组合根与 V2）不许直接摸到的文件/密钥/具体存储。
final RegExp _uiSecretsImportRe = RegExp(
  r'dart:io|VaultService|MediaCryptoService|NotebookStorage',
);

/// import/export 语句行（引号两种都认，关键字与 URI 之间空白不限形态）。
final RegExp _importStmtRe = RegExp('''^\\s*(?:import|export)\\s+["']''');

const List<String> _v2PackageRoots = [
  'packages/editor_core/lib',
  'packages/notebook_domain/lib',
];
const List<String> _uiRoots = ['lib/app'];

/// V2 特性目录：2026-10-16 实测**不存在**。它存在时是 V-005 第三条腿与 V-006 第二条腿的
/// 扫描根，所以单独列出来，由「扫描根台账」那条用例钉住它的现状——见该用例的 reason。
const String _v2FeatureRoot = 'lib/features/editor_v2';

void main() {
  final packageFiles = [for (final r in _v2PackageRoots) ..._dartFiles(r)];
  final uiFiles = [for (final r in _uiRoots) ..._dartFiles(r)];
  final v2FeatureFiles = _dartFiles(_v2FeatureRoot);

  test('V-004：editor_core/notebook_domain 纯 Dart（无 Flutter/dart:io/dart:ui/平台包）', () {
    expect(packageFiles, isNotEmpty, reason: 'V2 包目录应存在');
    for (final f in packageFiles) {
      for (final line in _importsOf(f)) {
        expect(_impureImportRe.hasMatch(line), isFalse, reason: 'V-004 $f: $line');
      }
    }
  });

  test('V-005：V2 不得 import Legacy（features/drawing|notes|drawing_controller|editor_page|legacy/）', () {
    final files = [...packageFiles, ...v2FeatureFiles];
    for (final f in files) {
      for (final line in _importsOf(f)) {
        expect(_legacyImportRe.hasMatch(line), isFalse, reason: 'V-005 $f: $line');
      }
    }
  });

  test('V-006：UI（app）不得直接访问文件/密钥/具体存储', () {
    final files = [...uiFiles, ...v2FeatureFiles];
    for (final f in files) {
      for (final line in _importsOf(f)) {
        expect(
          _uiSecretsImportRe.hasMatch(line),
          isFalse,
          reason: 'V-006 $f: $line',
        );
      }
    }
  });

  test('扫描根台账：每个根的存在与否都得说出来，别把缺席当成合规', () {
    // 三条 V-* 判据全部是「循环体不执行就是绿」的形状，所以**根的现状必须单独断言**。
    expect(
      Directory(_v2PackageRoots[0]).existsSync(),
      isTrue,
      reason: '$_v2PackageRoots[0] 不见了 ⇒ V-004/V-005 的扫描面会静默缩小。'
          '包若改名或迁走，本测试必须跟着改，而不是安静地变绿。',
    );
    expect(Directory(_v2PackageRoots[1]).existsSync(), isTrue, reason: '同上');
    expect(Directory(_uiRoots[0]).existsSync(), isTrue, reason: 'lib/app 不在 ⇒ V-006 恒绿');
    expect(
      Directory(_v2FeatureRoot).existsSync(),
      isFalse,
      reason:
          '$_v2FeatureRoot 在 2026-10-16 实测**不存在**，所以 V-005 的第三条腿与 V-006 的'
          '第二条腿现在扫不到任何文件。这一格红**不是故障**，是在提醒：V2 特性目录一旦落地，'
          '这两条判据的扫描面会凭空变大而没人复核——那时要做的是把下面的文件数下限一起抬高，'
          '并重新确认 V-005/V-006 对新目录仍然成立。宁可红一次让人来改基线，也不要空着没人知道。',
    );
  });

  test('分母下限：认出的文件数与 import 行数塌掉 ⇒ 红（TE-TST-04）', () {
    expect(
      packageFiles.length,
      greaterThanOrEqualTo(5),
      reason: 'V2 两包只读到 ${packageFiles.length} 个 .dart（实测基线 5：3 + 2）',
    );
    expect(
      uiFiles.length,
      greaterThanOrEqualTo(5),
      reason: 'lib/app 只读到 ${uiFiles.length} 个 .dart（实测基线 5）',
    );
    final stmtLines = [...packageFiles, ...uiFiles].fold<int>(
      0,
      (sum, f) => sum + _importsOf(f).length,
    );
    expect(
      stmtLines,
      greaterThanOrEqualTo(60),
      reason:
          '读了 ${packageFiles.length + uiFiles.length} 个文件却只认出 $stmtLines 行 '
          'import/export（实测基线 70）⇒ 抽取口径坏了（`_importStmtRe` 被改窄、引号形态'
          '变化、`part`/`deferred` 写法漂移都会走到这一格）。抽取塌了就等于三条判据同时失明。',
    );
  });

  test('判据自证：该拦的行必须拦，合法的行不许误拦，两种引号都得抽到', () {
    // ① 抽取面：双引号与制表符分隔都在真实 Dart 里合法。
    expect(
      _extract('import "dart:io";'),
      hasLength(1),
      reason: '突变 M-V2：`_importsOf` 退回只认单引号时，这一行抽不到——'
          '于是 `import "dart:io";` 一句就能整体绕过 V-004/V-006',
    );
    expect(_extract("import\t'package:flutter/material.dart';"), hasLength(1));
    expect(_extract("// import 'dart:io'; 这是注释"), isEmpty, reason: '注释行不算语句');
    expect(_extract('final x = 1;'), isEmpty);

    // ② 三条判据各自的正例（必须被拦）。
    expect(
      _impureImportRe.hasMatch("import 'dart:io';"),
      isTrue,
      reason: 'V-004 纯度：dart:io 必须被拦',
    );
    expect(
      _legacyImportRe.hasMatch(
        "import 'package:drawing_notes_app/features/drawing/rendering/x.dart';",
      ),
      isTrue,
      reason: 'V-005 Legacy：features/drawing 必须被拦',
    );
    expect(
      _legacyImportRe.hasMatch("import '../editor_page.dart';"),
      isTrue,
      reason: '突变 M-V3：legacy 正则若去掉 `editor_page`，这条相对写法就溜过去了',
    );
    expect(
      _uiSecretsImportRe.hasMatch(
        "import 'package:drawing_notes_app/core/security/vault_service.dart' show VaultService;",
      ),
      isTrue,
      reason: 'V-006：`show VaultService` 这类带子句的写法也必须拦（所以判据看整行而非只取 URI）',
    );

    // ③ 反例：合法形状不许误拦（否则这三条门禁会被绕过式地天天红）。
    expect(
      _impureImportRe.hasMatch("import 'package:meta/meta.dart';"),
      isFalse,
      reason: 'V2 包允许 meta 这类纯 Dart 包',
    );
    expect(
      _legacyImportRe.hasMatch(
        "import 'package:drawing_notes_app/core/documents/note_block.dart';",
      ),
      isFalse,
      reason: 'V2 → core 是向内依赖，合法',
    );
    expect(
      _uiSecretsImportRe.hasMatch(
        "import 'package:drawing_notes_app/app/app_shell.dart';",
      ),
      isFalse,
    );
  });
}

/// 递归收集目录下全部 .dart 文件。
///
/// 目录不存在时仍返回空（**但本文件不再依赖这个返回值做裁决**——根的现状与扫描面
/// 分别由「扫描根台账」「分母下限」两条用例钉住，见文件头 TE-TST-04 段）。
List<String> _dartFiles(String dir) {
  if (!Directory(dir).existsSync()) return const [];
  final result = <String>[];
  for (final e in Directory(dir).listSync(recursive: true)) {
    if (e is File && e.path.endsWith('.dart')) result.add(e.path);
  }
  return result;
}

/// 提取 import/export 语句（行首锚定——排除注释与字符串；单双引号都认）。
List<String> _importsOf(String file) => _extract(File(file).readAsLinesSync());

/// 从行集合（或单行文本）里认出 import/export 语句行。判据与真实扫描共用这一份实现。
List<String> _extract(Object linesOrText) {
  final lines = linesOrText is List<String>
      ? linesOrText
      : (linesOrText as String).split('\n');
  return [
    for (final l in lines)
      if (_importStmtRe.hasMatch(l)) l,
  ];
}
