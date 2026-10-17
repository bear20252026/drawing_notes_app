// 「策略拒绝」必须被接住——enforceCheck 调用点的形状门禁（审计 2026-10-16 §21 第 1 条）。
//
// 病灶：`PolicyEngine.enforceCheck` 在 deny 时**先抛** `PolicyDeniedException`，
// 永远不返回 `isAllowed == false`。于是「`final r = enforceCheck(...)` 再
// `if (!r.isAllowed)`」是一个**恒不成立**的分支——提示语从没能执行过，真被拒时异常
// 直接逃到调用方（导出按钮 / TrashPage 的 `Future<bool>` 回调）变成未捕获异常。
// 本轮在同一家族里数到三处：`doc_page_save_export._exportAllowed`、
// `app_shell_routes` 的 restore/purge（原为两行同形复制）。修法统一成
// `home_page_trash._allowTrashOp`（R20）那个形状：`try { enforceCheck(...) }`
// + `on PolicyDeniedException` 里提示并返回 false。
//
// 这条门禁钉的是**形状**（判据行为由 `policy_engine_test.dart` 与 R20 的用例钉）：
// 任何一个新的 enforceCheck 调用点都必须挨着自己的 try 并捕获 PolicyDeniedException。
// 三件本仓栽过的事：① 分母先于结论（扫不到调用点就红，不许「零违规」式绿）；
// ② 判据抽成函数，canary 与真实源码**共用同一份定义**（R11）；
// ③ 边界取「下一个 try {」而不是整文件——跨全文匹配会匹到**别处**的 catch，
//    于是突变测的是不存在的东西（R20 的教训）。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 从 [lines] 里取包住第 [lineIdx] 行的**成员体**（按缩进切，不按正则跨全文匹配）。
///
/// 为什么必须按体切：本仓栽过「跨全文正则匹到**另一个动作**的配对，于是突变测的是
/// 不存在的东西」（R20）。同文件里只要有一处合规的 `on PolicyDeniedException`，
/// 「往全文找 catch」的写法就会把后面任何一处裸调用判成合规。
({int start, int end}) _memberSpan(List<String> lines, int lineIdx) {
  var start = lineIdx;
  while (start > 0 && !_memberHead(lines[start])) {
    start--;
  }
  var end = lineIdx;
  final isHead = _memberHead(lines[lineIdx]);
  while (end + 1 < lines.length && !(isHead ? _closer(lines[end + 1]) : _memberHead(lines[end + 1]))) {
    end++;
  }
  return (start: start, end: end);
}

bool _memberHead(String line) =>
    RegExp(r'^  [^\s/]').hasMatch(line) && line.contains('(');

bool _closer(String line) => line == '  }' || line.startsWith('  } ');

/// 一处 `enforceCheck` 调用点的违规描述；合规返回 null。
String? _violationAt(List<String> lines, int lineIdx) {
  final line = lines[lineIdx];
  // 文档注释里提到的名字不算调用点（本仓踩过「把文档注释当 import」）。
  if (line.trimLeft().startsWith('///')) return null;
  // 声明行 `PolicyResult enforceCheck(` 不是调用点。
  if (line.trimLeft().startsWith('PolicyResult enforceCheck(')) return null;

  final span = _memberSpan(lines, lineIdx);
  final body = lines.sublist(span.start, span.end + 1).join('\n');
  if (!body.contains('try {')) {
    return '第 ${lineIdx + 1} 行的 enforceCheck 不在 try 块里 ⇒ deny 时异常无人接：${line.trim()}';
  }
  if (!body.contains('on PolicyDeniedException')) {
    return '第 ${lineIdx + 1} 行的 enforceCheck 所在成员没捕获 PolicyDeniedException ⇒ '
        '「拿返回值再 if (!isAllowed)」是死分支：${line.trim()}';
  }
  return null;
}

/// 真实调用点所在行号（注释行与声明行都排除在外）。
List<int> _callLineIndices(List<String> lines) => [
  for (var i = 0; i < lines.length; i++)
    if (lines[i].contains('enforceCheck(')) i,
];

/// 扫描一份源码里的全部 enforceCheck 调用点，返回违规清单。
List<String> violationsIn(String source) {
  final lines = source.split(RegExp(r'\r?\n'));
  return [
    for (final i in _callLineIndices(lines)) _violationAt(lines, i),
  ].whereType<String>().toList();
}

/// 真实调用点数量（与 `violationsIn` 共用同一套排除规则）。
int callSiteCount(String source) {
  final lines = source.split(RegExp(r'\r?\n'));
  return _callLineIndices(lines)
      .where((i) => !lines[i].trimLeft().startsWith('///'))
      .where((i) => !lines[i].trimLeft().startsWith('PolicyResult enforceCheck('))
      .length;
}

void main() {
  Iterable<File> dartFiles() => Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));

  test('分母：真实源码里至少扫到 3 处 enforceCheck 调用点，否则这条门禁看不见现场', () {
    final found = <String, int>{};
    for (final f in dartFiles()) {
      final n = callSiteCount(f.readAsStringSync());
      if (n > 0) found[f.path.replaceAll(r'\', '/')] = n;
    }
    final total = found.values.fold<int>(0, (a, b) => a + b);
    expect(
      total,
      greaterThanOrEqualTo(3),
      reason: '导出 / 恢复 / 清除三条腿各一处（$found）——'
          '数量掉到 0 通常是本门禁读错了目录，而不是调用点消失了',
    );
  });

  test('每一处 enforceCheck 都被 try + on PolicyDeniedException 接住', () {
    final all = <String>[];
    for (final f in dartFiles()) {
      final src = f.readAsStringSync();
      for (final v in violationsIn(src)) {
        all.add('${f.path}: $v');
      }
    }
    expect(all, isEmpty, reason: '死分支的代价是「被拒时用户什么都看不到」或一次崩溃：\n${all.join('\n')}');
  });

  test('判据自证：同形违规必须报、合规形状必须零报（canary 与真实源码共用一份定义）', () {
    // ① 死分支形状（本轮改掉的那三处原文）——必须被挑出来。
    const deadBranch = '''
  bool gate(String op) {
    final result = const PolicyEngine().enforceCheck(op);
    if (!result.isAllowed) {
      _snack('被拒绝');
    }
    return result.isAllowed;
  }
''';
    expect(violationsIn(deadBranch), hasLength(1));

    // ② 合规形状（R20 的 `_allowTrashOp`）——不许误报，否则门禁会变成哭墙。
    const compliant = '''
  bool gate(String op) {
    try {
      const PolicyEngine().enforceCheck(op);
      return true;
    } on PolicyDeniedException catch (e) {
      _snack('操作被策略拒绝（\${e.operation}）');
      return false;
    }
  }
''';
    expect(violationsIn(compliant), isEmpty);

    // ③ 边界自证：同一个函数里先有一处合规、后面又出现一处**没有 try** 的调用，
    //    必须只报后者——这条防的是「匹到别处的 catch」。
    const mixed = '''
  bool a(String op) {
    try {
      const PolicyEngine().enforceCheck(op);
      return true;
    } on PolicyDeniedException {
      return false;
    }
  }

  void b(String op) {
    const PolicyEngine().enforceCheck(op);
  }
''';
    expect(violationsIn(mixed), hasLength(1));
    // 钉「报的是哪一处」而不是行号（行号是切分实现的细节，会随样本改动静漂移）：
    // 违规必须是那个**没有 try 的 b()**，而不是同文件里已经合规的 a()。
    final reported = violationsIn(mixed).single;
    expect(reported, contains('不在 try 块里'));
    expect(reported, contains('const PolicyEngine().enforceCheck(op);'));
  });
}
