// H1 架构门禁（2026-11；框架级收口 2026-11-15 收紧）：表现层
// （features/*/presentation/**）不得触碰文件系统 IO（dart:io）与
// **媒体加密原语实现（MediaCryptoService）**。
//
// 背景：表现层承担了本应属于 infrastructure 的文件读写与解密职责
// （readAsString/writeAsBytes/File 构造、EncryptedFileImage 直传 File、
// 直接持有 MediaCryptoService 字段）。本门禁把「下沉到 infrastructure /
// core 例接口」钉成机器事实，新增违规即红。
//
// 框架级收口（2026-11-15）：媒体取钥已收敛到唯一权威编排器
// NotebookMediaKeys——表现层只允许持有/传线**编排器**，不再持有加密
// 原语。原 6 文件「登记豁免」就此**清零**：MediaCryptoService 引用在
// 表现层一律红（无豁免）；编排器引用是合法形状，不在本判据内。
//
// 两条判据：
//   ① `dart:io` —— **零豁免**：表现层任何文件都不得 import 'dart:io'
//      （含双引号写法）。dart:io 是 Web 平台不可用的库，表现层引用它
//      会破坏 Web 构建（本门禁同时充当 Web 平台可用性前置闸门）。
//   ② `MediaCryptoService` —— **零豁免**（收口后）：表现层任何文件都不得
//      import 加密原语；取钥/加解密一律经编排器或 infrastructure。
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

  test('H1-②：features/*/presentation/** 引用 MediaCryptoService 即红（零豁免）', () {
    final offenders = <String>[];
    for (final f in presentationFiles) {
      for (final line in _importsOf(f)) {
        if (_mediaCryptoImportRe.hasMatch(line)) offenders.add('$f: $line');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'H1-② presentation 文件直接引用 MediaCryptoService：\n'
          '${offenders.join('\n')}\n'
          '框架级收口（2026-11-15）后表现层只允许持有/传线取钥权威编排器'
          '（NotebookMediaKeys）；加密原语不得进表现层。',
    );
  });

  test('H1-③：收口自证——原 6 个登记持有方已全部改持编排器（防回退）', () {
    // 框架级收口前的 6 个 MediaCryptoService 持有方（历史登记台账）。
    // 收口后它们必须改持 NotebookMediaKeys——若任一文件又引回加密原语，
    // H1-② 会红；本用例额外钉住「确实改持了编排器」，防「删引用但没接线」
    // 的假收口（删了 import 却仍嗅探密钥内存存在性的退化形状）。
    const formerHolders = [
      'lib/features/drawing/presentation/editor_page.dart',
      'lib/features/notes/presentation/home_page.dart',
      'lib/features/notes/presentation/notebook_reader_page.dart',
      'lib/features/notes/presentation/notebook_view_page.dart',
      'lib/features/notes/presentation/presentation_page.dart',
      'lib/features/notes/presentation/search_page.dart',
    ];
    final orchestratorRe = RegExp(
      r'''^\s*(?:import|export)\s+["'][^"']*notebook_media_keys\.dart["']''',
    );
    for (final f in formerHolders) {
      expect(File(f).existsSync(), isTrue, reason: '持有方 $f 不存在 ⇒ 台账过期');
      expect(
        _importsOf(f).any(orchestratorRe.hasMatch),
        isTrue,
        reason: '$f 应改持取钥权威编排器 NotebookMediaKeys（框架级收口）',
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

/// 递归收集目录下全部 .dart 文件，返回 **posix 归一化**的相对路径。
///
/// Windows 上 `Directory.listSync()` 给出的 `entity.path` 用反斜杠，且根目录
/// 保留调用时写的写法、子级用 `\` 拼接（形如
/// `lib/features/drawing/presentation\editor_page.dart`），而本门禁的
/// `_presentationRoots` 与 H1-③ 的 `formerHolders` 都是正斜杠常量——不归一化
/// 会让路径比对在 Windows 上全部失配（2026-11-11 CI `e6509815` 实测踩中，
/// macOS/Linux 不复现）。口径与 `architecture_boundary_ratchet_test.dart`、
/// `architecture_layering_test.dart` 一致。
List<String> _dartFiles(String dir) {
  if (!Directory(dir).existsSync()) return const [];
  final result = <String>[];
  for (final e in Directory(dir).listSync(recursive: true)) {
    if (e is File && e.path.endsWith('.dart')) {
      result.add(e.path.replaceAll('\\', '/'));
    }
  }
  return result;
}

/// 提取 import/export 语句行（行首锚定，单双引号都认）。
List<String> _importsOf(String file) => [
  for (final l in File(file).readAsLinesSync())
    if (RegExp(r'''^\s*(?:import|export)\s+["']''').hasMatch(l)) l,
];
