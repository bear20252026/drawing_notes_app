// 主题适配层接缝门禁（2026-11-16，迁移评估步骤 2 的机器事实）。
//
// 两条判据：
// ① **模型零框架依赖**：app_theme_spec.dart 只准 import dart:ui——
//    material/widgets/cupertino 任何 UI 框架库出现即红。这是「内部主题
//    模型与具体 Material 实现解耦」的构造性保证：将来切换 material_ui
//    时本文件零改动。
// ② **应用主题构造唯一落点**：lib/ 内 `ThemeData(` 与 `ColorScheme(`
//    构造只准出现在 material_theme_adapter.dart。局部覆写
//    （SliderThemeData/局部 DialogThemeData 等子主题类型）不在此列——
//    判据只认应用级主题/色板的裸构造。
//
// 突变自证：判据抽成 RegExp 常量，正反两控见末用例。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final RegExp _frameworkImportRe = RegExp(
  r'''^\s*(?:import|export)\s+["']package:flutter/(material|widgets|cupertino)\.dart["']''',
);

/// 应用级主题/色板裸构造（`ThemeData(` / `ColorScheme(`，前面不得有
/// 标识符字符——排除 SliderThemeData(/DialogThemeData( 等子主题类型）。
final RegExp _themeCtorRe = RegExp(r'(?<![A-Za-z0-9_])(ThemeData|ColorScheme)\(');

const String _specFile = 'lib/core/theme/app_theme_spec.dart';
const String _adapterFile = 'lib/core/theme/material_theme_adapter.dart';

List<String> _libDartFiles() {
  final result = <String>[];
  for (final e in Directory('lib').listSync(recursive: true)) {
    if (e is File && e.path.endsWith('.dart')) {
      result.add(e.path.replaceAll('\\', '/'));
    }
  }
  return result;
}

List<String> _importsOf(String file) => [
  for (final l in File(file).readAsLinesSync())
    if (RegExp(r'''^\s*(?:import|export)\s+["']''').hasMatch(l)) l,
];

/// 去掉注释行后的源码（判据只认真实代码，注释里的示例不触发）。
String _codeOf(String file) => File(file)
    .readAsLinesSync()
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  test('①：内部主题模型零 Material 依赖（只准 dart:ui）', () {
    expect(File(_specFile).existsSync(), isTrue, reason: '模型文件不存在 ⇒ 门禁失明');
    final imports = _importsOf(_specFile);
    expect(imports, isNotEmpty, reason: '模型至少 import dart:ui');
    for (final line in imports) {
      expect(
        _frameworkImportRe.hasMatch(line),
        isFalse,
        reason: '① $_specFile 引入 UI 框架库：$line\n'
            '内部主题模型必须与 Material 实现解耦（迁移接缝的前提）。',
      );
      // 项目内 import 也禁止——模型是纯数据，不依赖任何令牌类/适配器。
      expect(
        line.contains('package:drawing_notes_app') ||
            RegExp(r'''["'][^"']*\.dart["']''').firstMatch(line)?.group(0)?.startsWith('dart:') == false,
        isFalse,
        reason: '① $_specFile 只准 dart: 库 import：$line',
      );
    }
  });

  test('②：ThemeData/ColorScheme 应用级构造唯一落点 = 适配器', () {
    final files = _libDartFiles();
    expect(files.length, greaterThanOrEqualTo(300), reason: 'lib 扫描面塌了');
    final offenders = <String>[];
    var adapterHits = 0;
    for (final f in files) {
      final hits = _themeCtorRe.allMatches(_codeOf(f)).length;
      if (hits == 0) continue;
      if (f == _adapterFile) {
        adapterHits += hits;
      } else {
        offenders.add('$f（$hits 处）');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: '② 应用级主题/色板构造散落：\n${offenders.join('\n')}\n'
          '一律经 MaterialThemeAdapter（内部模型 → Material 的唯一转换点）。',
    );
    expect(
      adapterHits,
      greaterThanOrEqualTo(2),
      reason: '适配器内至少各一处 ThemeData(/ColorScheme( 构造——'
          '0 命中说明判据正则失明或适配器被搬空',
    );
  });

  test('③：接缝台账——模型/适配器/委托三方都在（防门禁空转）', () {
    expect(File(_adapterFile).existsSync(), isTrue);
    final appDesign = File('lib/core/theme/app_design.dart').readAsStringSync();
    expect(
      appDesign.contains('MaterialThemeAdapter.themeOf'),
      isTrue,
      reason: 'AppDesign 主题产出必须经适配器（薄委托被绕过即红）',
    );
    expect(
      appDesign.contains('AppThemeSpec.resolve'),
      isTrue,
      reason: 'AppDesign 必须消费内部模型（决策不得回流到 Material 层）',
    );
  });

  test('判据自证：该拦的拦，合法的不误拦', () {
    expect(
      _frameworkImportRe.hasMatch("import 'package:flutter/material.dart';"),
      isTrue,
    );
    expect(
      _frameworkImportRe.hasMatch("import 'dart:ui' show Color;"),
      isFalse,
    );
    expect(_themeCtorRe.hasMatch('final base = ThemeData('), isTrue);
    expect(_themeCtorRe.hasMatch('return const ColorScheme('), isTrue);
    expect(_themeCtorRe.hasMatch('data: SliderThemeData('), isFalse);
    expect(_themeCtorRe.hasMatch('dialogTheme: DialogThemeData('), isFalse);
    expect(_themeCtorRe.hasMatch('CardThemeData('), isFalse);
  });
}