// 由 Claude 团队生成 | Drawing Notes App

/// 「样式是否渲染」这份判据在**生产只读**（R49）。
///
/// 缘起：R46 把两个样式入口按这份判据标灰。为了让 FDC-01 那三条「必须点一下样式」
/// 才能造出形状的用例继续跑（它守的是「正文永远赢」这条裁决，不是入口本身），
/// 判据从 `const` 改成可写的顶层 `bool`——**代价是它也变成了运行时可被改的东西**。
/// 一个决定用户界面能不能点的开关如果能被任何一行业务代码改掉，那它就不再是判据，
/// 而是第 N+1 份真相（本仓反复出事的形状）。⇒ 这条门禁把「谁能写它」变成机器事实：
/// **`lib/` 里只有声明那一行的初值可以赋值它，别处一律红**；测试侧的开关
/// （`setUp`/`tearDown`）不在 `lib/`，本门禁刻意不管它——它管的是出货产物里的那份代码。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 任何形式的「给它赋值」：`name =`、`name +=`，但**不是** `name ==`。
final RegExp _assignment = RegExp(r'\binlineStylesAreRendered\s*(=[^=]|\+=)');

/// 声明本身（初值可以随便改——「接上渲染那天」就是把这里改成 true）。
final RegExp _declaration = RegExp(r'^\s*(const\s+)?bool\s+inlineStylesAreRendered\s*=[^=]');

/// 注释行不算写（trap 56 那一族：文档注释里写着 `inlineStylesAreRendered = false`
/// 是在**解释**，不是语句）。
final RegExp _comment = RegExp(r'^\s*(//|///|\*)');

/// 返回 `(文件:行号, 文本)`；[source] 非空时扫这段字符串而不是扫盘。
List<(String, String)> assignmentLines([String? source]) {
  final out = <(String, String)>[];
  void scan(String label, String line) {
    if (_comment.hasMatch(line)) return;
    if (_assignment.hasMatch(line)) out.add((label, line));
  }

  if (source != null) {
    final lines = source.split('\n');
    for (var i = 0; i < lines.length; i++) {
      scan('synthetic:$i', lines[i]);
    }
    return out;
  }
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final lines = entity.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      scan('${entity.path}:${i + 1}', lines[i]);
    }
  }
  return out;
}

/// 扫盘上的赋值点里，去掉「就是声明」的那些——剩下的就是越权写。
List<(String, String)> illegalWrites(List<(String, String)> found) {
  return found.where((hit) => !_declaration.hasMatch(hit.$2)).toList();
}

/// 判据名字出现在 `lib/` 的总次数（含注释）——分母下限用，防「抽取失效后空集通过」。
int mentionCount() {
  var n = 0;
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    for (final line in entity.readAsLinesSync()) {
      if (line.contains('inlineStylesAreRendered')) n++;
    }
  }
  return n;
}

void main() {
  test('分母下限：判据真的被扫到（抽取失效时不许空集通过）', () {
    // 实测 2026-10-17：`lib/` 里 5 处提及，其中 1 处是声明、2 处是 presentation 读它。
    expect(mentionCount(), greaterThanOrEqualTo(3), reason: '扫不到 ⇒ 扫描本身坏了，下一条会假绿');
    expect(
      assignmentLines().where((h) => _declaration.hasMatch(h.$2)).length,
      1,
      reason: '声明必须恰好一处：0 处=抽取/改名失效，2 处=判据长出第二份',
    );
  });

  test('判据：lib/ 里没有「声明以外」的赋值', () {
    final bad = illegalWrites(assignmentLines());
    expect(
      bad,
      isEmpty,
      reason: '生产代码在运行时改这份判据 ⇒ 标灰开关不再是单一真相：$bad',
    );
  });

  group('判据自证（四种形状要分别落对格子）', () {
    test('越权写会被抓到', () {
      final bad = illegalWrites(
        assignmentLines("void f() {\n  inlineStylesAreRendered = true;\n}\n"),
      );
      expect(bad, hasLength(1), reason: '这条不红就等于门禁没装');
      expect(
        illegalWrites(
          assignmentLines('void f() {\n  inlineStylesAreRendered += 1;\n}\n'),
        ),
        hasLength(1),
        reason: '`+=` 也是写',
      );
    });

    test('声明的初值不算越权写（那天就是改这里）', () {
      expect(
        illegalWrites(assignmentLines('bool inlineStylesAreRendered = true;')),
        isEmpty,
      );
    });

    test('读它不算写', () {
      expect(
        illegalWrites(
          assignmentLines(
            'if (inlineStylesAreRendered) return label;\n'
            'final x = inlineStylesAreRendered ? 1 : 2;\n'
            'if (inlineStylesAreRendered == true) {}\n',
          ),
        ),
        isEmpty,
        reason: '`==` 与三元里的裸引用都是读；算成写就会把 presentation 自己判红',
      );
    });

    test('注释里的同形文本不算写', () {
      expect(
        illegalWrites(assignmentLines('// inlineStylesAreRendered = false 是在解释')),
        isEmpty,
      );
    });
  });
}
