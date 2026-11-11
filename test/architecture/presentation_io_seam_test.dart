// H1 架构门禁（2026-11）：表现层（features/*/presentation/**）不得触碰
// 文件系统 IO（dart:io）与加密服务实现（MediaCryptoService）。
//
// 背景：表现层承担了本应属于 infrastructure 的文件读写与解密职责
// （readAsString/writeAsBytes/File 构造、EncryptedFileImage 直传 File、
// 直接持有 MediaCryptoService 字段）。本门禁把「下沉到 infrastructure /
// core 例接口」钉成机器事实，新增违规即红。
//
// 两条判据：
//   ① `dart:io` —— **零豁免**：表现层任何文件都不得 import 'dart:io'
//      （含双引号写法）。dart:io 是 Web 平台不可用的库，表现层引用它
//      会破坏 Web 构建（本门禁同时充当 Web 平台可用性前置闸门）。
//   ② `MediaCryptoService` —— **登记豁免**：既有 6 个文件（历史注入链）
//      登记在 [_mediaCryptoAllowlist] 里，新增引用一律红。豁免只针对
//      「持有该类型字段并沿构造链传线」，加密/解密调用与 File 构造已在
//      本轮下沉到 infrastructure（NotebookStorage / EncryptedFileImage）。
//
// 突变自证：判据抽成 RegExp 常量 + `_importsOf`，正反两控见文件末用例。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `dart:io` 的 import/export 写法（单双引号都认，关键字与 URI 间空白不限）。
final RegExp _dartIoImportRe = RegExp(
  r'''^\s*(?:import|export)\s+["']dart:io["']''',
);

/// `MediaCryptoService` 的引用形状：import 语句，或类型注解（字段/参数/返回）。
/// 只看 import 行即可覆盖「新增文件引用该类型」——类型注解必然伴随 import。
final RegExp _mediaCryptoImportRe = RegExp(
  r'''^\s*(?:import|export)\s+["'][^"']*media_crypto_service\.dart["']''',
);

/// 已登记的 MediaCryptoService 持有文件（2026-11 实测 6 个）。
///
/// 这些文件是历史构造注入链的一部分（组合根 → 页面 → EncryptedFileImage/
/// NotebookPdfExporter），本轮下沉只收 File 构造与文件读写，未动注入链。
/// 新增文件引用该类型 ⇒ 红；从登记文件移除引用 ⇒ 也应红（防登记过期）。
const List<String> _mediaCryptoAllowlist = [
  'lib/features/drawing/presentation/editor_page.dart',
  'lib/features/notes/presentation/home_page.dart',
  'lib/features/notes/presentation/notebook_reader_page.dart',
  'lib/features/notes/presentation/notebook_view_page.dart',
  'lib/features/notes/presentation/presentation_page.dart',
  'lib/features/notes/presentation/search_page.dart',
];

/// presentation 扫描根（feature-first 分层）。
const List<String> _presentationRoots = [
  'lib/features/drawing/presentation',
  'lib/features/notes/presentation',
  'lib/features/doc/presentation',
  'lib/features/security/presentation',
  'lib/features/all_docs/presentation',
];

void main() {
  final presentationFiles = [
    for (final r in _presentationRoots) ..._dartFiles(r),
  ];

  test('H1-①：features/*/presentation/** 不得 import dart:io（零豁免）', () {
    expect(
      presentationFiles,
      isNotEmpty,
      reason: 'presentation 扫描根全部读不到文件 ⇒ 门禁空转。'
          '根目录若改名/迁移，本测试必须跟着改，而不是安静地变绿。',
    );
    for (final f in presentationFiles) {
      for (final line in _importsOf(f)) {
        expect(
          _dartIoImportRe.hasMatch(line),
          isFalse,
          reason: 'H1-① $f: $line\n'
              '表现层不得 import dart:io（Web 平台不可用；文件读写/加密封包'
              '一律走 infrastructure 或 core 例接口）。',
        );
      }
    }
  });

  test('H1-②：features/*/presentation/** 新增 MediaCryptoService 引用即红（登记豁免）', () {
    final offenders = <String>[];
    for (final f in presentationFiles) {
      if (_mediaCryptoAllowlist.contains(f)) continue;
      for (final line in _importsOf(f)) {
        if (_mediaCryptoImportRe.hasMatch(line)) offenders.add('$f: $line');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'H1-② 新增 presentation 文件直接引用 MediaCryptoService：\n'
          '${offenders.join('\n')}\n'
          '加密服务须由组合根注入抽象/回调，或下沉到 infrastructure；'
          '确需新增持有方时，先把它登记进 _mediaCryptoAllowlist 并说明理由。',
    );
  });

  test('H1-③：登记豁免台账——登记文件必须真的引用，未引用的登记即过期', () {
    for (final f in _mediaCryptoAllowlist) {
      final exists = File(f).existsSync();
      expect(
        exists,
        isTrue,
        reason: '登记文件 $f 不存在 ⇒ 登记过期（文件改名/删除后未同步台账）。',
      );
      final imports = _importsOf(f);
      final hasRef = imports.any(_mediaCryptoImportRe.hasMatch);
      expect(
        hasRef,
        isTrue,
        reason: '登记文件 $f 已不引用 MediaCryptoService ⇒ 应从台账移除'
            '（登记只应包含「确有需要且已评审」的持有方）。',
      );
    }
  });

  test('H1-④：扫描根台账与分母下限（TE-TST-04 口径，防空集即绿）', () {
    for (final r in _presentationRoots) {
      expect(
        Directory(r).existsSync(),
        isTrue,
        reason: '扫描根 $r 不存在 ⇒ 判据扫描面静默缩小。',
      );
    }
    expect(
      presentationFiles.length,
      greaterThanOrEqualTo(20),
      reason: 'presentation 只读到 ${presentationFiles.length} 个 .dart'
          '（实测基线 ≫20）⇒ 抽取口径坏了或目录结构漂移。',
    );
    final stmtLines = presentationFiles.fold<int>(
      0,
      (sum, f) => sum + _importsOf(f).length,
    );
    expect(
      stmtLines,
      greaterThanOrEqualTo(100),
      reason: '读了 ${presentationFiles.length} 个文件却只认出 $stmtLines 行 '
          'import/export ⇒ 抽取塌了（判据同时失明）。',
    );
  });

  test('H1-⑤：判据自证——该拦的行必须拦，合法行不误拦', () {
    expect(
      _dartIoImportRe.hasMatch("import 'dart:io';"),
      isTrue,
      reason: 'dart:io 单引号写法必须被拦',
    );
    expect(
      _dartIoImportRe.hasMatch('import "dart:io";'),
      isTrue,
      reason: 'dart:io 双引号写法必须被拦',
    );
    expect(
      _dartIoImportRe.hasMatch("import 'package:flutter/material.dart';"),
      isFalse,
      reason: '合法 package import 不许误拦',
    );
    expect(
      _mediaCryptoImportRe.hasMatch(
        "import 'package:drawing_notes_app/core/security/media_crypto_service.dart';",
      ),
      isTrue,
      reason: 'MediaCryptoService import 必须被拦（未登记文件）',
    );
    expect(
      _mediaCryptoImportRe.hasMatch(
        "import 'package:drawing_notes_app/core/security/vault_service.dart';",
      ),
      isFalse,
      reason: 'VaultService import 不许误拦（不在本门禁判据内）',
    );
    // 注释行不算 import 语句。
    expect(_importsOf('test/architecture/presentation_io_seam_test.dart')
        .where((l) => l.contains('import'))
        .every((l) => !l.trimLeft().startsWith('//')),
        isTrue,
        reason: '注释里的 import 字样不应被当成语句',
    );
  });
}

/// 递归收集目录下全部 .dart 文件。
List<String> _dartFiles(String dir) {
  if (!Directory(dir).existsSync()) return const [];
  final result = <String>[];
  for (final e in Directory(dir).listSync(recursive: true)) {
    if (e is File && e.path.endsWith('.dart')) result.add(e.path);
  }
  return result;
}

/// 提取 import/export 语句行（行首锚定，单双引号都认）。
List<String> _importsOf(String file) => [
  for (final l in File(file).readAsLinesSync())
    if (RegExp(r'''^\s*(?:import|export)\s+["']''').hasMatch(l)) l,
];
