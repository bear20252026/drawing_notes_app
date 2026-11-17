// R1 收口（架构审查路线图，2026-11-17）：editor_page 库状态刷新单点门禁。
//
// 背景：_applyState(VoidCallback fn) => setState(fn) 是页面整页重建的唯一
// 入口，但此前主文件有 5 处裸 setState 绕过它、persistence 还另立了一个
// notify() 第二包装（同语义两套入口）。收口后本门禁把「单点」钉成机器事实：
// _EditorPageState 作用域（主文件 class 体 + 全部 on _EditorPageState 的
// extension）内，setState( 只允许出现在 _applyState 定义那一行。
//
// 豁免口径（与 kdf_suite_hygiene 同款：豁免必须显式、可审计）：
// - editor_page_dialogs.dart 里的独立对话框 State（_CommandPaletteDialogState /
//   _TextInputDialogState）不是 _EditorPageState——它们的 setState 合法，
//   按「extension/class 作用域」判定自然排除，不需要文件名特判。
// - 注释里的 setState 字样不算调用（先剥注释再判）。
//
// 塌空下限（TE-TST-04 口径）：扫描面文件数与 _applyState 调用数都配下限，
// 计数坏掉时「零违规」会假绿——下限抓「没数到」。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 剥掉行注释与块注释（判据只看真实代码；字符串里的 setState 字样本项目
/// 不存在，若将来出现应按调用点评审而非放宽本门禁）。
String _stripComments(String src) {
  final noBlock = src.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  return noBlock
      .split('\n')
      .map((l) {
        final i = l.indexOf('//');
        return i < 0 ? l : l.substring(0, i);
      })
      .join('\n');
}

/// 返回文件内 _EditorPageState 作用域的裸 setState 调用行号（1-based）。
/// 主文件：class _EditorPageState 体（到文件尾，part 声明不产生新作用域）；
/// part 文件：每个 `extension ... on _EditorPageState` 块（brace 配对）。
List<int> findBareSetStateInEditorStateScope(String path, String source) {
  final code = _stripComments(source);
  final lines = code.split('\n');
  final violations = <int>[];

  bool inScope = false;
  var depth = 0;
  final isMain = path.endsWith('editor_page.dart');
  if (isMain) {
    // 主文件从 class _EditorPageState 声明起进入作用域。
    for (var i = 0; i < lines.length; i++) {
      if (!inScope &&
          RegExp(r'class\s+_EditorPageState\b').hasMatch(lines[i])) {
        inScope = true;
      }
      if (!inScope) continue;
      depth += '{'.allMatches(lines[i]).length -
          '}'.allMatches(lines[i]).length;
      _check(lines[i], i + 1, violations);
      if (depth <= 0 && i > 0 && lines[i].contains('}')) {
        // class 体闭合后主文件不再有 _EditorPageState 代码。
        inScope = false;
      }
    }
    return violations;
  }

  // part 文件：逐个 extension on _EditorPageState 块。
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (!inScope &&
        RegExp(r'extension\s+\w+\s+on\s+_EditorPageState\b').hasMatch(line)) {
      inScope = true;
      depth = 0;
    }
    if (!inScope) continue;
    depth += '{'.allMatches(line).length - '}'.allMatches(line).length;
    _check(line, i + 1, violations);
    if (depth <= 0 && line.contains('}')) inScope = false;
  }
  return violations;
}

void _check(String line, int lineNo, List<int> violations) {
  if (!line.contains('setState(')) return;
  // 唯一合法落点：_applyState 定义行本身。
  if (RegExp(r'void\s+_applyState\s*\(\s*VoidCallback\s+fn\s*\)\s*=>\s*setState\(fn\)')
      .hasMatch(line)) {
    return;
  }
  violations.add(lineNo);
}

void main() {
  List<File> libFiles() {
    final dir = Directory('lib/features/drawing/presentation');
    return dir
        .listSync()
        .whereType<File>()
        .where((f) =>
            f.path.endsWith('.dart') &&
            f.uri.pathSegments.last.startsWith('editor_page'))
        .toList();
  }

  test('分母下限：扫描面与 _applyState 调用数不许塌掉（TE-TST-04 同族）', () {
    final files = libFiles();
    expect(
      files.length,
      greaterThanOrEqualTo(16),
      reason: 'editor_page 主文件 + 15 part + object_mutation 独立库 ≥ 16；'
          '读出个位数说明扫描根错了，那时「零违规」会假绿',
    );
    final calls = files.fold<int>(
      0,
      (n, f) => n + '_applyState('.allMatches(f.readAsStringSync()).length,
    );
    expect(
      calls,
      greaterThanOrEqualTo(90),
      reason: '今天实测 103 处 _applyState 调用；数出个位数说明触发词失效',
    );
  });

  test('判据：_EditorPageState 作用域内 setState 只许出现在 _applyState 定义行', () {
    final violations = <String>[];
    for (final f in libFiles()) {
      final hits = findBareSetStateInEditorStateScope(
        f.path,
        f.readAsStringSync(),
      );
      for (final line in hits) {
        violations.add('${f.path}:$line');
      }
    }
    expect(
      violations,
      isEmpty,
      reason:
          '整页重建必须走 _applyState 单点（R1 收口）——裸 setState 绕过单点，'
          '将来给刷新加守卫/埋点时会漏掉这些口子：\n${violations.join('\n')}',
    );
  });

  test('判据自证：探针裸 setState 必须被抓到（防门禁自身失效）', () {
    const probe = '''
extension _Probe on _EditorPageState {
  void bad() {
    setState(() {});
  }
}
''';
    expect(
      findBareSetStateInEditorStateScope('editor_page_probe.dart', probe),
      // Dart ''' 字符串跳过紧跟的首个换行：extension 在第 1 行，setState 第 3 行。
      [3],
      reason: '探针没被抓到说明作用域解析失效——门禁在空转',
    );
    const okProbe = '''
extension _Probe on _EditorPageState {
  void good() {
    _applyState(() {});
  }
}
''';
    expect(
      findBareSetStateInEditorStateScope('editor_page_probe.dart', okProbe),
      isEmpty,
    );
  });
}