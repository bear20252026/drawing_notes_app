// 工具栏契约字段的「冻结增长」棘轮（R47，EUI-12 重采之后新增）。
//
// 实测（台账 §30.1，逐条回读）：`EditorToolbarActions` 43 个字段、`EditorToolbarState` 23 个，
// 合计 66；其中 **40 个没有任何读者**（29 个回调只有测试调用、11 个状态字段连测试都不读）——
// 因为真正在用的是 `EditorLeftToolbar` 自有的 20 个参数与 `PropertiesPanel` 那条路
// （`editor_page_body.dart:176-211/102`）。也就是说：这套「契约对象」是一份**平行门面**，
// 写侧接好了、读侧另有一条路。
//
// 清理它 = 删代码，归业主点名（且它是 B3/插件化路线上的候选门面，不能当成死代码顺手删）。
// 所以本批只做一件不需要点头的事：**冻结增长**。
// 再往这两个类里加一个字段，就必须先给已有的某个字段接上读者或删掉一个——
// 否则「40 个没人读」会一路涨下去，而每一个都是「注释说已接线、其实没人读」的候选。
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _path =
    'lib/features/drawing/presentation/editor_toolbar_contracts.dart';

/// 今天实测的字段数上限（**只紧不松**：要抬高必须先在台账里写清理由并删掉一个旧的）。
const Map<String, int> _caps = <String, int>{
  'EditorToolbarActions': 43,
  'EditorToolbarState': 23,
};

/// 数一个类体里的**字段声明**：两格缩进、`final` 开头、且不带 `=`。
///
/// 排除带 `=` 的那一半是必须的——实测类体里有 3 行 `final x = ...` 是**方法内的局部变量**
/// （两处 `final l10n = AppLocalizations.of(context)`、一处 `final name = switch (align)`），
/// 混进来的话 43 会被数成 46，棘轮就会在第一天把自己判红（R38 那条「计数要实测」的口径）。
int countFieldDeclarations(String classBody) => classBody
    .split('\n')
    .where((line) => line.startsWith('  final ') && !line.contains('='))
    .length;

/// 按 `class X {` 切出类体（到下一个顶层 `class ` 或文件末尾）。
Map<String, String> splitClasses(String source) {
  final lines = source.split('\n');
  final starts = <int, String>{};
  for (var i = 0; i < lines.length; i++) {
    final m = RegExp(r'^class (\w+)').firstMatch(lines[i]);
    if (m != null) starts[i] = m.group(1)!;
  }
  final indexes = starts.keys.toList()..sort();
  final out = <String, String>{};
  for (var k = 0; k < indexes.length; k++) {
    final from = indexes[k];
    final to = k + 1 < indexes.length ? indexes[k + 1] : lines.length;
    out[starts[from]!] = lines.sublist(from, to).join('\n');
  }
  return out;
}

void main() {
  test('分母下限：两个类都扫到了、字段数量级对得上（扫描塌了要当场红）', () {
    final classes = splitClasses(File(_path).readAsStringSync());
    expect(classes.keys.toList()..sort(), _caps.keys.toList()..sort);
    for (final entry in _caps.entries) {
      final body = classes[entry.key]!;
      expect(
        countFieldDeclarations(body),
        greaterThan(10),
        reason: '${entry.key} 字段数塌到 10 以下 ⇒ 抽取规则失效（不是真的没人加字段）',
      );
    }
  });

  test('棘轮：契约字段只许变短不许变长（今天 43 + 23，其中 40 个无读者）', () {
    final classes = splitClasses(File(_path).readAsStringSync());
    for (final entry in _caps.entries) {
      final body = classes[entry.key];
      expect(body, isNotNull, reason: '类 ${entry.key} 不见了/改名了 ⇒ 同步本用例');
      final n = countFieldDeclarations(body!);
      expect(
        n,
        lessThanOrEqualTo(entry.value),
        reason: '${entry.key} 有 $n 个字段，上限 ${entry.value}。'
            '今天这 66 个里 40 个没有任何读者（台账 §30.1）——再加一个就是在扩一份平行门面。'
            '要么先给已有字段接上读者/删掉一个，要么在台账里写明理由后改上限。',
      );
    }
  });

  test('判据自证：局部变量与注释都不算字段，真字段算', () {
    const sample = '''
class EditorToolbarActions {
  /// 注释里写 final fakeField = 1 不算
  final void Function() realOne;
  final int realTwo;

  void m() {
    final localWithEquals = 3;
    final l10n = AppLocalizations.of(context);
  }
}
''';
    expect(countFieldDeclarations(sample), 2);
  });
}
