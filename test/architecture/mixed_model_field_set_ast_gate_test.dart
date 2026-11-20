// M-7 字段集机器判据（三轮审计 2026-11-18，P4 AST 门禁基建）。
//
// 起因：mixed_model_copy_restore_test 是**手抄字段清单**（构造/改脏/断言
// 三处），模型新增字段而 copy+restoreFrom **双双漏跟**时测试不红——门禁
// 名实不符。本门禁改用 analyzer AST 解析源码：枚举模型可变字段声明 vs
// copy()/restoreFrom() 实际覆盖的字段，差集非空即红。机器跟随模型，不手抄。
//
// 判据（对每个混排模型类）：
//   可变字段 = 非 final、非 static、非私有的实例 FieldDeclaration 变量
//   copy 覆盖 = copy() 构造实参的命名参数名集
//   restore 覆盖 = restoreFrom() 体内 `字段 = snapshot.…` 赋值左值名集
//   ① copy 覆盖 == 可变字段 ∪ {id}（id 为 final 身份锚，copy 须带、restore 不改）
//   ② restore 覆盖 == 可变字段
//   ③ copy 覆盖 \ {id} == restore 覆盖（成对一致）
//
// 可恢复集 = 可变实例字段 ∪ 公开 setter（dash 背后 _dashLegacy 私有字段不
// 重复计）；getter 不可赋值不入集。copy/restoreFrom 经 setter 名恢复。
//
// 突变自证：末两例对源码字符串注入「漏跟字段」，验证判据当场红（非恒真）。
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

/// 混排模型类 → 源文件：**自动发现**（扫 canvas_model 目录 `class Page*Item`）。
/// 第四轮审计缺口 2：原先手抄四模型清单，新增模型而门禁漏跟不红；
/// 现在清单从源码生成，新增模型自动纳入（自证钉住已知成员）。
Map<String, String> _discoverModels() {
  final dir = Directory('lib/core/canvas_model');
  final out = <String, String>{};
  for (final f in dir.listSync().whereType<File>()) {
    if (!f.path.endsWith('.dart')) continue;
    for (final m
        in RegExp(r'class\s+(Page\w+Item)\b').allMatches(f.readAsStringSync())) {
      out[m.group(1)!] = f.path;
    }
  }
  return out;
}

final Map<String, String> _models = _discoverModels();

ClassDeclaration _classOf(CompilationUnit unit, String name) => unit.declarations
    .whereType<ClassDeclaration>()
    .firstWhere((c) => c.namePart.typeName.lexeme == name);

List<ClassMember> _membersOf(ClassDeclaration cls) =>
    (cls.body as BlockClassBody).members;

/// 可恢复属性名集 = 可变实例字段（非 final/static/私有）∪ 公开 setter。
///
/// 公开 setter（如 PageShapeItem.dash）背后可以是私有字段（_dashLegacy）+
/// 派生逻辑——copy/restoreFrom 经 setter 名恢复，故 setter 名计入可恢复集；
/// 其背后的私有字段不计（避免重复）。getter 不可赋值，不入集。
Set<String> mutableFieldsOf(ClassDeclaration cls) {
  final out = <String>{};
  for (final m in _membersOf(cls)) {
    if (m is FieldDeclaration) {
      if (m.isStatic || m.fields.isFinal) continue;
      for (final v in m.fields.variables) {
        final n = v.name.lexeme;
        if (!n.startsWith('_')) out.add(n);
      }
    } else if (m is MethodDeclaration && m.isSetter) {
      final n = m.name.lexeme;
      if (!n.startsWith('_')) out.add(n);
    }
  }
  return out;
}

/// copy() 构造实参命名参数名集（含 id）。
Set<String> copyArgsOf(ClassDeclaration cls) {
  final copy = _membersOf(cls).whereType<MethodDeclaration>().firstWhere(
    (m) => m.name.lexeme == 'copy',
  );
  final body = copy.body;
  final expr = body is ExpressionFunctionBody ? body.expression : null;
  // analyzer 11 未解析上下文：无 const/new 的构造调用 `Class(...)` 解析为
  // MethodInvocation（语法歧义），带 new/const 才是 InstanceCreationExpression。
  // 两形态都取 argumentList 的命名实参——判据只关心参数名集。
  final ArgumentList args;
  if (expr is InstanceCreationExpression) {
    args = expr.argumentList;
  } else if (expr is MethodInvocation) {
    args = expr.argumentList;
  } else {
    throw StateError('copy() 须为构造表达式体（=> Class(...)）');
  }
  return {
    for (final a in args.arguments)
      if (a is NamedExpression) a.name.label.name,
  };
}

class _RestoreAssignCollector extends RecursiveAstVisitor<void> {
  final Set<String> names = {};

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    final lhs = node.leftHandSide;
    if (lhs is SimpleIdentifier) names.add(lhs.name);
    super.visitAssignmentExpression(node);
  }
}

/// restoreFrom() 体内 `字段 = …` 赋值左值名集。
Set<String> restoreAssignsOf(ClassDeclaration cls) {
  final restore = _membersOf(cls).whereType<MethodDeclaration>().firstWhere(
    (m) => m.name.lexeme == 'restoreFrom',
  );
  final collector = _RestoreAssignCollector();
  restore.body.accept(collector);
  return collector.names;
}

/// 三判据差集报告（空 = 通过）。供真实门禁与突变自证共用。
List<String> fieldSetViolations(String source, String className) {
  final unit = parseString(content: source).unit;
  final cls = _classOf(unit, className);
  final mutable = mutableFieldsOf(cls);
  final copy = copyArgsOf(cls);
  final restore = restoreAssignsOf(cls);
  final problems = <String>[];
  final copyMissing = mutable.difference(copy);
  final copyExtra = copy.difference(mutable.union({'id'}));
  final restoreMissing = mutable.difference(restore);
  final restoreExtra = restore.difference(mutable);
  if (copyMissing.isNotEmpty) {
    problems.add('copy 漏复制可变字段：$copyMissing');
  }
  if (copyExtra.isNotEmpty) {
    problems.add('copy 多出非字段参数：$copyExtra');
  }
  if (restoreMissing.isNotEmpty) {
    problems.add('restoreFrom 漏恢复可变字段：$restoreMissing');
  }
  if (restoreExtra.isNotEmpty) {
    problems.add('restoreFrom 多恢复非可变字段：$restoreExtra');
  }
  if (!copy.contains('id')) problems.add('copy 未带身份锚 id');
  return problems;
}

void main() {
  test('模型清单自动发现：覆盖已知四模型（扫描失效即红）', () {
    for (final n in const [
      'PageTextItem',
      'PageShapeItem',
      'PageImageItem',
      'PageChartItem',
    ]) {
      expect(
        _models.containsKey(n),
        isTrue,
        reason: '清单未认出 $n ⇒ 目录扫描失配，下面判据会「空集通过」',
      );
    }
  });

  for (final entry in _models.entries) {
    test('${entry.key}：copy/restoreFrom 字段集 == 模型可变字段（AST 机器判据）', () {
      final source = File(entry.value).readAsStringSync();
      final problems = fieldSetViolations(source, entry.key);
      expect(
        problems,
        isEmpty,
        reason:
            '模型加字段须同步 copy+restoreFrom（双双漏跟即红，非手抄清单）：'
            '${problems.join('；')}',
      );
    });
  }

  test('突变自证：模型加字段而 copy+restoreFrom 双双漏跟 → 判据红', () {
    // 在 PageImageItem 注入新可变字段，copy/restoreFrom 不动。
    final source = File(_models['PageImageItem']!).readAsStringSync();
    final mutated = source.replaceFirst(
      '  int zOrder;',
      '  int zOrder;\n  double opacity;',
    );
    expect(mutated, isNot(source), reason: '突变须真实注入字段');
    final problems = fieldSetViolations(mutated, 'PageImageItem');
    expect(problems, isNotEmpty, reason: '漏跟字段必须被机器判据捕获');
    expect(problems.join(), contains('opacity'));
    expect(problems.join(), contains('copy'));
    expect(problems.join(), contains('restoreFrom'));
  });

  test('突变自证：只改 copy 不改 restoreFrom → 判据红（成对一致）', () {
    final source = File(_models['PageImageItem']!).readAsStringSync();
    // 注入字段 + 只补 copy 实参，restoreFrom 不动。
    final mutated = source
        .replaceFirst('  int zOrder;', '  int zOrder;\n  double opacity;')
        .replaceFirst('    zOrder: zOrder,', '    zOrder: zOrder,\n    opacity: opacity,');
    final problems = fieldSetViolations(mutated, 'PageImageItem');
    expect(problems, isNotEmpty);
    expect(problems.join(), contains('restoreFrom 漏恢复'));
    expect(problems.join(), isNot(contains('copy 漏复制')));
  });
}
