import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 专家 I-006（2026-08-16——批次 A）：V2 架构边界测试——
/// editor_core / notebook_domain 纯 Dart（R-02：无 Flutter/dart:io——
/// 禁依赖）+ V2 绝不 import legacy（R-02）。
void main() {
  test('editor_core 纯 Dart：无 Flutter 依赖（R-02）', () {
    for (final f in _dartFiles('packages/editor_core/lib')) {
      final imports = _importsOf(f);
      for (final line in imports) {
        expect(line.contains('package:flutter'), isFalse, reason: '$f: $line');
      }
    }
  });

  test('editor_core 纯 Dart：无 dart:io（R-02）', () {
    for (final f in _dartFiles('packages/editor_core/lib')) {
      final imports = _importsOf(f);
      for (final line in imports) {
        expect(line.contains("import 'dart:io'"), isFalse, reason: '$f: $line');
      }
    }
  });

  test('notebook_domain 纯 Dart：无 Flutter/dart:io（R-02）', () {
    for (final f in _dartFiles('packages/notebook_domain/lib')) {
      final imports = _importsOf(f);
      for (final line in imports) {
        expect(line.contains('package:flutter'), isFalse, reason: '$f: $line');
        expect(line.contains("import 'dart:io'"), isFalse, reason: '$f: $line');
      }
    }
  });

  test('V2 绝不 import legacy（R-02——无 legacy 依赖）', () {
    final files = [
      ..._dartFiles('packages/editor_core/lib'),
      ..._dartFiles('packages/notebook_domain/lib'),
    ];
    for (final f in files) {
      final imports = _importsOf(f);
      for (final line in imports) {
        expect(line.contains('legacy'), isFalse, reason: '$f: $line');
      }
    }
  });
}

/// 递归收集目录下全部 .dart 文件。
List<String> _dartFiles(String dir) {
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
      .where((l) => l.trimLeft().startsWith("import '") || l.trimLeft().startsWith("export '"))
      .toList();
}
