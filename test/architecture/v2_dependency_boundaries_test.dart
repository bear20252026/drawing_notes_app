import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 专家第一周更正期 V-004~V-006（2026-08-16）：
/// V2 依赖方向边界测试——V-004 纯度 / V-005 V2 不 import Legacy / V-006
/// UI 不直接访问文件·密钥·具体存储。
/// （专家 C-003 要求的 v2_dependency_boundaries_test——加入 pr-architecture。）
void main() {
  test(
    'V-004：editor_core/notebook_domain 纯 Dart（无 Flutter/dart:io/dart:ui/平台包）',
    () {
      final files = [
        ..._dartFiles('packages/editor_core/lib'),
        ..._dartFiles('packages/notebook_domain/lib'),
      ];
      expect(files, isNotEmpty, reason: 'V2 包目录应存在');
      for (final f in files) {
        for (final line in _importsOf(f)) {
          for (final bad in [
            'package:flutter',
            'dart:io',
            'dart:ui',
            'file_selector',
            'path_provider',
            'shared_preferences',
          ]) {
            expect(line.contains(bad), isFalse, reason: 'V-004 $f: $line');
          }
        }
      }
    },
  );

  test(
    'V-005：V2 不得 import Legacy（features/drawing|notes|drawing_controller|editor_page|legacy/）',
    () {
      final files = [
        ..._dartFiles('packages/editor_core/lib'),
        ..._dartFiles('packages/notebook_domain/lib'),
        ..._dartFiles('lib/features/editor_v2'),
      ];
      final legacy = RegExp(
        'features/drawing|features/notes|drawing_controller|editor_page|legacy/',
      );
      for (final f in files) {
        for (final line in _importsOf(f)) {
          expect(legacy.hasMatch(line), isFalse, reason: 'V-005 $f: $line');
        }
      }
    },
  );

  test('V-006：UI（app）不得直接访问文件/密钥/具体存储', () {
    final files = [
      ..._dartFiles('lib/app'),
      ..._dartFiles('lib/features/editor_v2'),
    ];
    final forbidden = RegExp(
      'dart:io|VaultService|MediaCryptoService|NotebookStorage',
    );
    for (final f in files) {
      for (final line in _importsOf(f)) {
        expect(forbidden.hasMatch(line), isFalse, reason: 'V-006 $f: $line');
      }
    }
  });
}

/// 递归收集目录下全部 .dart 文件（目录不存在时返回空）。
List<String> _dartFiles(String dir) {
  if (!Directory(dir).existsSync()) return const [];
  final result = <String>[];
  for (final e in Directory(dir).listSync(recursive: true)) {
    if (e is File && e.path.endsWith('.dart')) result.add(e.path);
  }
  return result;
}

/// 提取 import/export 语句（行首——排除注释与字符串）。
List<String> _importsOf(String file) {
  return File(file)
      .readAsLinesSync()
      .where(
        (l) =>
            l.trimLeft().startsWith("import '") ||
            l.trimLeft().startsWith("export '"),
      )
      .toList();
}
